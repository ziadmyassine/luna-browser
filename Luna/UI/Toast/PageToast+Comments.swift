//
//  PageToast+Comments.swift
//  Luna
//
//  Comment mode's toasts (§5c), kept apart so `PageToast.swift` stays inside
//  SwiftLint's file length.
//

import Foundation

extension PageToast {

    /// Comment mode's export. The prompt on the clipboard is for one site's
    /// bundle, `copied`; `others` were written too and are only named.
    /// Reveal selects every bundle's `COMMENTS.md` in Finder.
    static func commentsExported(
        _ count: Int, copied: String, others: [String], reveal: @escaping @MainActor () -> Void
    ) -> PageToast {
        let site = count == 1
            ? String(localized: "1 comment on \(copied)")
            : String(localized: "\(count) comments on \(copied)")
        let also = others.isEmpty ? "" : String(localized: ", also \(others.joined(separator: ", "))")
        return PageToast(
            symbol: "doc.on.clipboard",
            text: String(localized: "Prompt copied"),
            detail: site + also,
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
