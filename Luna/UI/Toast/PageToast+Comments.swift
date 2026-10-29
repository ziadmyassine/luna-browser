//
//  PageToast+Comments.swift
//  Luna
//
//  Comment mode's toasts (§5c), kept apart so `PageToast.swift` stays inside
//  SwiftLint's file length.
//

import Foundation

extension PageToast {

    /// Comment mode's export of one page on `site`, whose prompt is on the
    /// clipboard. Reveal selects that export's `COMMENTS.md` in Finder.
    static func commentsExported(_ count: Int, site: String, reveal: @escaping @MainActor () -> Void) -> PageToast {
        PageToast(
            symbol: "doc.on.clipboard",
            text: String(localized: "Prompt copied"),
            detail: count == 1 ? String(localized: "1 comment on \(site)") : String(localized: "\(count) comments on \(site)"),
            actions: [Action(title: String(localized: "Reveal"), label: String(localized: "Show the comments in Finder"), run: reveal)]
        )
    }

    static func commentsNotExported(_ reason: String) -> PageToast {
        PageToast(symbol: "exclamationmark.triangle", text: String(localized: "Couldn’t export comments"), detail: reason)
    }

    static let commentNotCaptured = PageToast(
        symbol: "exclamationmark.triangle", text: String(localized: "Couldn’t capture that element")
    )

    static let areaNotCaptured = PageToast(
        symbol: "exclamationmark.triangle", text: String(localized: "Couldn’t capture that area")
    )
}
