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
