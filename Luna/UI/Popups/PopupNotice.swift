//
//  PopupNotice.swift
//  Luna
//
//  §17: the news that a pop-up was blocked, with Open and Always Allow. It is
//  a page toast (`PageToast`) with two words on it, not a chip of its own:
//  most blocked pop-ups are meant to stay blocked, so this is news rather than
//  a question, and news over the page is Luna's one toast.
//
//  It was a floating panel with a solid plate and a placement setting (under
//  the site-menu glyph, or at the page's foot). The toast drops from under
//  the bar like every other one, so the setting went with the panel.
//

import AppKit
import BrowserKit

/// Whether a blocked pop-up says so, beside the blocking mode in Privacy.
@MainActor
enum PopupNoticeSettings {
    static let notifiesKey = "privacy.popupNotify"

    /// Off, pop-ups are still blocked and listed in the site menu, and the
    /// shortcut still opens the last one; nothing appears over the page.
    static var notifies: Bool {
        get { UserDefaults.standard.object(forKey: notifiesKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: notifiesKey) }
    }
}

/// The count of pop-ups blocked while one notice is down, so a burst reads
/// "3 pop-ups blocked" on one toast rather than three toasts in a row.
@MainActor
final class PopupNotice {

    private(set) var count = 0
    private(set) var toast: PageToast?
    private var shownAt: Date?

    /// The notice for one more block of `url`: the count goes up while the
    /// last notice is still down and starts again once it has gone.
    func next(
        _ url: URL,
        shortcut: String?,
        showsAddress: Bool = PopupPolicy.showsAddress(),
        now: Date = Date(),
        open: @escaping @MainActor () -> Void,
        allow: @escaping @MainActor () -> Void
    ) -> PageToast {
        let stillDown = shownAt.map { now.timeIntervalSince($0) < Tokens.Motion.toastActionDwell } ?? false
        count = stillDown && toast != nil ? count + 1 : 1
        shownAt = now
        let address = showsAddress ? (url.host(percentEncoded: false) ?? url.absoluteString) : nil
        let toast = PageToast.popupBlocked(count: count, address: address, shortcut: shortcut, open: open, allow: allow)
        self.toast = toast
        return toast
    }

    /// Taken back up: the tab it spoke for was left, or its pop-up opened.
    func putAway(in window: NSWindow?) {
        toast?.putAway(in: window)
        toast = nil
        shownAt = nil
        count = 0
    }
}

extension PageToast {

    /// - Parameter address: the pop-up's host, when Privacy says to show it.
    static func popupBlocked(
        count: Int,
        address: String?,
        shortcut: String?,
        open: @escaping @MainActor () -> Void,
        allow: @escaping @MainActor () -> Void
    ) -> PageToast {
        PageToast(
            symbol: "rectangle.on.rectangle.slash",
            text: count == 1 ? String(localized: "Pop-up blocked") : String(localized: "\(count) pop-ups blocked"),
            detail: address,
            actions: [
                Action(
                    title: shortcut.map { String(localized: "Open \($0)") } ?? String(localized: "Open"),
                    label: String(localized: "Open the pop-up"),
                    toolTip: shortcut.map { String(localized: "Open the pop-up (\($0))") },
                    run: open
                ),
                Action(
                    title: String(localized: "Always Allow"),
                    label: String(localized: "Always allow pop-ups on this site"),
                    run: allow
                )
            ]
        )
    }
}
