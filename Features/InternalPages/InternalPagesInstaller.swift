//
//  InternalPagesInstaller.swift
//  Luna
//
//  The one assembly call that turns `BrowserKit`'s `luna://` handler into a
//  working History page (§6.4).
//
//  §3.5's History button no longer comes through here. It opens
//  `HistoryPanel` — a floating panel over the page — rather than a tab on
//  `luna://history`; the route still resolves and still renders, because a URL
//  someone has bookmarked should not stop working, but nothing in the chrome
//  navigates to it any more. `luna://archive`, the address it had before the
//  rename, resolves here too.
//
//  `BrowserKit` cannot reach the tab list or `Design/`, so the three things
//  internal pages need from the app are set here, once, and read live
//  afterwards. Everything captures the session weakly: these are process-wide
//  statics and a strong capture would outlive the window.
//

import AppKit
import BrowserKit

@MainActor
enum InternalPagesInstaller {

    static func install(session: BrowserSession) {
        // §8.1's tokens, as CSS. Generated once: light, dark and both contrast
        // variants all ship in the block and the page picks with `prefers-*`.
        InternalPages.palette = InternalPageTheme.css()

        InternalPages.content = { [weak session] in
            guard let session else { return InternalPageContent() }
            // This Space's closed tabs, newest first, the way the Command Bar and
            // §6.4's list already treat it (§9.2).
            return InternalPageContent(archived: session.archivedInActiveSpace.map(entry))
        }

        InternalPages.onAction = { [weak session] action, _ in
            guard let session else { return }
            switch action {
            case .commandBar:
                // §4.5's error page, asking for the one surface that can take
                // an address — and asking for a tab, because the one it is
                // standing in is the one that failed.
                session.presentCommandBar?(.newTab, nil)
            case let .restore(id):
                session.unarchiveTab(id)
            case .retry, .proceed:
                // Performed by `TabController` itself; never routed here.
                break
            }
        }
    }

    private static func entry(_ tab: Tab) -> InternalPageContent.Entry {
        InternalPageContent.Entry(
            id: tab.id,
            title: tab.title,
            url: tab.url,
            archivedAt: tab.archivedAt
        )
    }
}
