//
//  CommentSet.swift
//  Luna
//
//  A comment as comment mode keeps it: the owner's note on one picked
//  element, with what the page looked like when it was picked.
//

import BrowserKit
import Foundation

struct Comment: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    /// The owner's words: the instruction, so never scrubbed.
    var note: String
    let created: Date
    /// The slug of `CommentBundle.slug(for:)`, which groups the export.
    let origin: String
    let page: PageState
    /// From the picker, every string scrubbed at capture.
    let element: PageElement
    /// The crop's file name in the draft folder.
    let image: String
    /// The viewport picture's file name, taken on local origins only.
    let context: String?
    /// A drag's area, every string scrubbed at capture; `element` is then what
    /// holds it. Optional, so a draft written before regions still decodes.
    var region: PageRegion?

    enum Kind: String, Codable, Sendable { case element, region }

    var kind: Kind { region == nil ? .element : .region }
}

/// Scrubbed at capture. `dark` is `prefers-color-scheme`, not a site's own toggle.
struct PageState: Codable, Equatable, Sendable {
    let url: String
    let viewportWidth: Double
    let dark: Bool
    let scrollX: Double
    let scrollY: Double
}

extension Comment {
    /// Luna's own folder, as `ControlService.documentsFolder` finds it.
    static var support: URL {
        URL.applicationSupportDirectory.appending(path: Bundle.main.bundleIdentifier ?? "dev.novapps.luna")
    }
}

/// The comments not yet exported, for every window: in memory while comment
/// mode runs, and in `draft.json` after each change so a crash or a relaunch
/// loses none. The draft sits outside `Comments/`, where no slug can collide
/// with it and an agent's read rule does not reach.
///
/// Each change is one step on `undoManager`, which the note field owns so ⌘Z
/// there never reaches the window's list. The pictures stay in the draft until
/// the set is made afresh, because an undone delete or export needs them back.
@MainActor
final class CommentSet {

    static var draftFolder: URL { Comment.support.appending(path: "Comment Draft", directoryHint: .isDirectory) }

    let folder: URL
    let undoManager: UndoManager
    private(set) var comments: [Comment] = []
    /// Why the last write of `draft.json` failed, nil once one succeeds. The set in memory is intact either way.
    private(set) var saveError: (any Error)?
    /// Where the last export left its step, if anywhere.
    private weak var exportedOn: UndoManager?

    private var file: URL { folder.appending(path: "draft.json") }

    init(folder: URL = CommentSet.draftFolder, undoManager: UndoManager = UndoManager()) {
        self.folder = folder
        self.undoManager = undoManager
        comments = Self.saved(in: folder)
        sweep()
    }

    /// The draft as last written, read without making a set: Export asks
    /// before anything has made one this launch.
    static func saved(in folder: URL = draftFolder) -> [Comment] {
        guard let data = try? Data(contentsOf: folder.appending(path: "draft.json")) else { return [] }
        return (try? JSONDecoder().decode([Comment].self, from: data)) ?? []
    }

    func add(_ comment: Comment) {
        change("Add Comment", to: comments + [comment])
    }

    /// An empty note deletes the comment, as clearing the field does.
    /// - Parameter undoable: false for the note an export commits first. In
    ///   one event the two steps share the event's undo group, so ⌘Z on the
    ///   export would take the note back with it.
    func setNote(_ note: String, of id: UUID, undoable: Bool = true) {
        guard !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return delete(id, undoable: undoable) }
        guard let index = comments.firstIndex(where: { $0.id == id }), comments[index].note != note else { return }
        var edited = comments
        edited[index].note = note
        change("Edit Comment", to: edited, undoable: undoable)
    }

    func delete(_ id: UUID, undoable: Bool = true) {
        guard comments.contains(where: { $0.id == id }) else { return }
        change("Delete Comment", to: comments.filter { $0.id != id }, undoable: undoable)
    }

    /// Writes every origin's bundle, then clears the set as one step. A failed
    /// write throws before anything is cleared, so the draft survives it.
    /// - Parameter outer: the window's list, where the Edit menu's ⌘Z looks;
    ///   it gets a step that undoes this export here, for as long as this
    ///   export is the last change.
    @discardableResult
    func export(to root: URL = CommentBundle.folder, now: Date = .now, undoingOn outer: UndoManager? = nil) throws
        -> [String: URL] {
        guard !comments.isEmpty else { return [:] }
        let written = try CommentBundle.write(comments, images: folder, to: root, now: now)
        change("Export Comments", to: [])
        outer?.registerUndo(withTarget: self) { set in
            MainActor.assumeIsolated { set.undoManager.undo() }
        }
        outer?.setActionName(String(localized: "Export Comments"))
        exportedOn = outer
        return written
    }

    /// The one way the set changes, so undo and redo are each the change back.
    private func change(_ name: String, to new: [Comment], undoable: Bool = true) {
        // Past the export, undoing this list would undo this change instead,
        // so the window's step for it goes; its own run is the one that stays.
        if let outer = exportedOn, !outer.isUndoing { outer.removeAllActions(withTarget: self) }
        let old = comments
        comments = new
        save()
        guard undoable else { return }
        undoManager.beginUndoGrouping()
        undoManager.registerUndo(withTarget: self) { set in
            MainActor.assumeIsolated { set.change(name, to: old) }
        }
        undoManager.setActionName(name)
        undoManager.endUndoGrouping()
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try JSONEncoder().encode(comments).write(to: file, options: .atomic)
            saveError = nil
        } catch {
            saveError = error
        }
    }

    /// A new set has no undo history, so a picture no comment names can never come back.
    private func sweep() {
        let named = Set(comments.flatMap { [$0.image, $0.context].compactMap(\.self) })
        let files = FileManager.default
        for name in (try? files.contentsOfDirectory(atPath: folder.path)) ?? [] where name.hasSuffix(".png") && !named.contains(name) {
            try? files.removeItem(at: folder.appending(path: name))
        }
    }
}
