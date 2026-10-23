//
//  CommentSetTests.swift
//  LunaTests
//
//  The comments not yet exported: kept in `draft.json` so a relaunch loses
//  none, and undoable step by step. Every folder is a temporary one.
//

import XCTest
@testable import Luna

@MainActor
final class CommentSetTests: XCTestCase {

    private var base: URL!
    private var draft: URL { base.appending(path: "Comment Draft") }
    private var undo: UndoManager!

    override func setUpWithError() throws {
        base = URL.temporaryDirectory.appending(path: "luna-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: draft, withIntermediateDirectories: true)
        undo = UndoManager()
        // One step per change, as a menu command would make it, without a run loop to close the groups.
        undo.groupsByEvent = false
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: base)
    }

    private func set() -> CommentSet { CommentSet(folder: draft, undoManager: undo) }

    /// A comment whose pictures are already in the draft, as capture leaves them.
    private func captured(_ note: String = "Make it taller") throws -> Comment {
        let comment = Comment.fixture(note: note)
        for name in [comment.image, comment.context].compactMap(\.self) {
            try Data("png".utf8).write(to: draft.appending(path: name))
        }
        return comment
    }

    private func onDisk() throws -> [Comment] {
        try JSONDecoder().decode([Comment].self, from: Data(contentsOf: draft.appending(path: "draft.json")))
    }

    func testAddingWritesTheDraft() throws {
        let comments = set()
        let comment = try captured()
        comments.add(comment)

        XCTAssertEqual(comments.comments, [comment])
        XCTAssertEqual(try onDisk(), [comment])
    }

    func testAFreshSetRestoresTheDraftAndSweepsPicturesNothingNames() throws {
        let first = set()
        let comment = try captured()
        first.add(comment)
        try Data("png".utf8).write(to: draft.appending(path: "orphan.png"))

        let restored = set()

        XCTAssertEqual(restored.comments, [comment])
        XCTAssertFalse(FileManager.default.fileExists(atPath: draft.appending(path: "orphan.png").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: draft.appending(path: comment.image).path))
    }

    func testDeleteThenUndoBringsBackTheNoteAndItsPictures() throws {
        let comments = set()
        let comment = try captured("Drop the shadow")
        comments.add(comment)
        comments.delete(comment.id)
        XCTAssertEqual(comments.comments, [])
        XCTAssertEqual(try onDisk(), [])

        undo.undo()

        XCTAssertEqual(comments.comments.map(\.note), ["Drop the shadow"])
        XCTAssertEqual(try onDisk(), [comment])
        for name in [comment.image, comment.context].compactMap(\.self) {
            XCTAssertTrue(FileManager.default.fileExists(atPath: draft.appending(path: name).path), name)
        }

        undo.redo()
        XCTAssertEqual(comments.comments, [])
    }

    func testEditingTheNoteIsOneStepAndAnEmptyNoteDeletes() throws {
        let comments = set()
        let comment = try captured("Taller")
        comments.add(comment)
        comments.setNote("Shorter", of: comment.id)
        XCTAssertEqual(try onDisk().map(\.note), ["Shorter"])

        undo.undo()
        XCTAssertEqual(comments.comments.map(\.note), ["Taller"])

        comments.setNote("", of: comment.id)
        XCTAssertEqual(comments.comments, [])
    }

    func testClearingAfterExportIsOneUndoStep() throws {
        let comments = set()
        let first = try captured("One"), second = try captured("Two")
        comments.add(first)
        comments.add(second)

        let written = try comments.export(to: base.appending(path: "Comments"))

        XCTAssertEqual(Array(written.keys), ["localhost-3002"])
        XCTAssertEqual(comments.comments, [])
        XCTAssertEqual(try onDisk(), [])

        undo.undo()
        XCTAssertEqual(comments.comments, [first, second])
        XCTAssertEqual(try onDisk(), [first, second])
    }
}
