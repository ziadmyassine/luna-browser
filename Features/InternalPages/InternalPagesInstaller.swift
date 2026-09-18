//
//  InternalPagesInstaller.swift
//  Luna
//
//  The one assembly call that turns `BrowserKit`'s `luna://` handler into a
//  working New Tab page (§30.19) and archive browser (§6.4).
//
//  **§3.5's History button no longer comes through here.** It opens
//  `HistoryPanel` — a floating panel over the page — rather than a tab on
//  `luna://archive`; the route still resolves and still renders, because a URL
//  someone has bookmarked should not stop working, but nothing in the chrome
//  navigates to it any more.
//
//  `BrowserKit` cannot reach the tab list, the Command Bar or `Design/`, so the
//  three things internal pages need from the app are set here, once, and read
//  live afterwards. Everything captures the session **weakly**: these are
//  process-wide statics and a strong capture would outlive the window.
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
            return InternalPageContent(
                // §7.1's Favorites are Essentials in the active Space — one
                // `Tab` with a `kind`, not a second table (§9.3's M1 correction).
                favorites: session.tabs.filter { $0.kind == .essential }.map(entry),
                // Every Space's archive, newest first, the way the Command Bar
                // already treats it (§9.2).
                archived: session.archived.map(entry)
            )
        }

        InternalPages.onAction = { [weak session] action, _ in
            guard let session else { return }
            switch action {
            case .commandBar, .addFavorite:
                // §30.19: the New Tab pill hands off to the Command Bar rather
                // than being a second input surface with its own ranking.
                session.presentCommandBar?(.search(""))
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
