//
//  SiteMenu.swift
//  Luna
//
//  §3.2's site menu: everything you can say about **the page you are on**,
//  behind the sliders glyph on the URL pill's trailing edge.
//
//  The glyph has been drawn since the sidebar was built and did nothing until
//  now — `onSiteMenu` was declared, forwarded twice, and never wired to
//  anything. This is what it opens.
//
//  **Per-site, not global.** That is the whole reason this surface exists
//  rather than three more rows in Settings. "Block ads" as a preference is a
//  decision you make once and then fight with on the four sites it breaks;
//  "Block Ads & Trackers" here is a decision about *this* site, taken where you
//  noticed the problem, and it is the only place those answers can be given.
//  Settings keeps the questions that are genuinely global — which filter lists
//  are on at all, HTTPS-Only, clearing everything — and has given up the ones
//  that were secretly per-site (SETTINGS-SPEC §3.3).
//
//  A plain `NSMenu`, which on macOS 26 *is* the liquid-glass menu: AppKit draws
//  its own material, its own blur and its own submenu chevrons, and a hand-rolled
//  panel would be a worse copy of it that also had to re-implement keyboard
//  navigation, VoiceOver and Reduce Transparency.
//

import AppKit
import BrowserKit
import WebKit

@MainActor
enum SiteMenu {

    /// Opens the menu under `anchor` — §3.2's sliders glyph, or §4's.
    static func present(from anchor: NSView) {
        build().popUp(positioning: nil, at: NSPoint(x: 0, y: anchor.bounds.maxY), in: anchor)
    }

    /// The menu for whatever page is on screen right now. Built fresh every
    /// time: every item in it is a statement about the current tab, and a menu
    /// held over from the last one would be checkmarks for another site.
    static func build() -> NSMenu {
        let menu = NSMenu()
        // Closure items are their own target so AppKit would enable them anyway;
        // turning this off is for the two that must stay *dis*abled.
        menu.autoenablesItems = false
        guard let page = current else {
            menu.addItem(SidebarMenu.header(String(localized: "No page")))
            return menu
        }

        // **`standardShareMenuItem`, not a hand-rolled submenu.** The reference
        // shows Share with a chevron, which is `sharingServices(forItems:)` —
        // deprecated since macOS 13, with Apple's own deprecation note pointing
        // here. This item reads "Share…" and opens the system picker on the
        // spot instead of nesting, and it lists the same ten destinations
        // (measured). A submenu is not worth building a stale copy of the
        // system's share sheet to get.
        //
        // The picker is **held, not let go**: the item is its, and a picker
        // that falls out of scope at the end of this function takes the item's
        // behaviour with it.
        let picker = NSSharingServicePicker(items: [page.url])
        sharePicker = picker
        menu.addItem(picker.standardShareMenuItem)
        menu.addItem(copyLink(page.url))
        menu.addItem(.separator())

        menu.addItem(blocking(host: page.host))
        menu.addItem(permission(
            .automaticPictureInPicture,
            title: String(localized: "Automatic Picture-In-Picture"),
            symbol: "pip",
            host: page.host,
            thenReload: false
        ))
        menu.addItem(permission(
            .localNetwork,
            title: String(localized: "Local Network"),
            symbol: nil,
            host: page.host,
            thenReload: true
        ))
        menu.addItem(.separator())

        let settings = NSMenuItem(title: String(localized: "Site Settings"), action: nil, keyEquivalent: "")
        settings.submenu = siteSettings(host: page.host)
        menu.addItem(settings)

        if let security = security(page) {
            menu.addItem(.separator())
            menu.addItem(security)
        }
        return menu
    }

    // MARK: - The page

    /// Everything the menu needs to know about the tab on screen. A page with
    /// no host — `luna:new-tab`, `about:blank` — is not a site and has no
    /// per-site answers to give, so the menu says so rather than offering
    /// switches that would be filed under an empty string.
    private struct Page {
        var url: URL
        var host: String
        var webView: WKWebView?
    }

    private static var session: BrowserSession? { (NSApp.delegate as? AppDelegate)?.session }

    /// See `build()`. One at a time: the menu is modal, so the previous one is
    /// always finished with by the time the next is made.
    private static var sharePicker: NSSharingServicePicker?

    private static var current: Page? {
        guard let session, let id = session.activeTabID, let tab = session.tab(id) else { return nil }
        // The tab's URL is the one the sidebar is showing; the web view's is the
        // one WebKit has, and they differ mid-navigation. The pill's is right.
        guard let host = tab.url.host(percentEncoded: false)?.lowercased(), !host.isEmpty else { return nil }
        return Page(url: tab.url, host: host, webView: session.controller(for: id)?.webView)
    }

    // MARK: - Items

    private static func copyLink(_ url: URL) -> NSMenuItem {
        let item = SidebarMenu.item(title: String(localized: "Copy Link")) {
            NSPasteboard.general.clearContents()
            // As a string as well as a URL: a plain text field pasted into gets
            // the address rather than nothing at all.
            NSPasteboard.general.writeObjects([url as NSURL])
            NSPasteboard.general.setString(url.absoluteString, forType: .string)
        }
        item.image = symbol("link")
        return item
    }

    /// §17.2's per-site exemption, read the way round a user thinks about it:
    /// the checkmark means blocking is **on** here, not that an exemption is.
    private static func blocking(host: String) -> NSMenuItem {
        let on = !ContentBlocker.shared.isDisabled(forHost: host)
        let item = SidebarMenu.item(title: String(localized: "Block Ads & Trackers")) {
            ContentBlocker.shared.setDisabled(on, forHost: host)
            reapplyRules(reload: true)
        }
        item.state = on ? .on : .off
        item.image = symbol("hand.raised")
        return item
    }

    private static func permission(
        _ permission: BrowserStore.SitePermission,
        title: String,
        symbol name: String?,
        host: String,
        thenReload reload: Bool
    ) -> NSMenuItem {
        let on = SitePermissions.shared.isAllowed(permission, forHost: host)
        let item = SidebarMenu.item(title: title) {
            SitePermissions.shared.setAllowed(!on, permission, forHost: host)
            // Only the ones that change what the page may *load*. Picture-in-
            // Picture is read at the moment the tab is left, so re-loading the
            // page to apply it would throw away the video it is about.
            if reload { reapplyRules(reload: true) }
        }
        item.state = on ? .on : .off
        if let name { item.image = symbol(name) }
        return item
    }

    private static func siteSettings(host: String) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(SidebarMenu.item(title: String(localized: "Clear Cache")) {
            clear(SiteData.caches, host: host, thenReload: true)
        })
        menu.addItem(SidebarMenu.item(title: String(localized: "Clear Cookies")) {
            clear(SiteData.cookies, host: host, thenReload: true)
        })
        menu.addItem(.separator())
        menu.addItem(SidebarMenu.item(title: String(localized: "Advanced Settings")) {
            (NSApp.delegate as? AppDelegate)?.showSettings(section: AdvancedSection.id)
        })
        return menu
    }

    /// A caption, not a control: it states what the connection is and there is
    /// nothing to do about it from here.
    ///
    /// `hasOnlySecureContent` is the whole question — an https page that pulled
    /// an image over http is not a secure page, and saying otherwise beside a
    /// padlock is the one lie a browser must never tell.
    private static func security(_ page: Page) -> NSMenuItem? {
        guard let scheme = page.url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return nil }
        let secure = scheme == "https" && (page.webView?.hasOnlySecureContent ?? true)
        let item = NSMenuItem(
            title: secure
                ? String(localized: "Connection is secure")
                : String(localized: "Connection is not secure"),
            action: nil,
            keyEquivalent: ""
        )
        item.isEnabled = false
        item.image = symbol(secure ? "lock" : "lock.open")
        return item
    }

    // MARK: - Doing the work

    /// Re-attaches the rule lists for the site's *new* answers and, where the
    /// answer changes what may load, fetches the page again — a rule list only
    /// binds loads that have not happened yet.
    private static func reapplyRules(reload: Bool) {
        guard let session, let id = session.activeTabID,
              let webView = session.controller(for: id)?.webView
        else { return }
        ContentBlocker.shared.apply(
            to: webView.configuration.userContentController,
            host: webView.url?.host(percentEncoded: false)
        )
        if reload { webView.reload() }
    }

    /// The two groups §3.2's submenu offers. Split the way the user means it:
    /// **Clear Cache** should not sign you out, and **Clear Cookies** should.
    private enum SiteData {
        static let caches: Set<String> = [
            WKWebsiteDataTypeDiskCache,
            WKWebsiteDataTypeMemoryCache,
            WKWebsiteDataTypeOfflineWebApplicationCache
        ]
        static let cookies: Set<String> = [
            WKWebsiteDataTypeCookies,
            WKWebsiteDataTypeLocalStorage,
            WKWebsiteDataTypeSessionStorage,
            WKWebsiteDataTypeIndexedDBDatabases
        ]
    }

    /// This site's records only. `WKWebsiteDataRecord.displayName` is the
    /// registrable domain — `apple.com` for `www.apple.com` — so a host matches
    /// its own record and every record it is a subdomain of, and nothing else.
    ///
    /// The store is the **tab's**, not `.default()`: a Space with its own
    /// Profile has its own `WKWebsiteDataStore` (§5.1), and clearing the wrong
    /// one would report success and change nothing.
    private static func clear(_ types: Set<String>, host: String, thenReload reload: Bool) {
        guard let session, let id = session.activeTabID,
              let webView = session.controller(for: id)?.webView
        else { return }
        let store = webView.configuration.websiteDataStore
        Task {
            let records = await store.dataRecords(ofTypes: types)
            let mine = records.filter { host == $0.displayName || host.hasSuffix(".\($0.displayName)") }
            guard !mine.isEmpty else { return }
            await store.removeData(ofTypes: types, for: mine)
            if reload { webView.reload() }
        }
    }

    /// The reference draws a glyph beside each item, and these are set for it.
    ///
    /// **macOS 26 does not draw them.** Measured, on this build, with a probe
    /// that put five images on five menu items — a template symbol, a
    /// non-template one, one with an explicit 16 pt size, a plain red square
    /// and a named AppKit template — and popped the menu up: none of the five
    /// appeared, in Luna or in a bare test app. `NSMenuItem.image` is the only
    /// API there is for this, it is set correctly, and the system currently
    /// declines. Left in place rather than deleted: it costs one assignment,
    /// it is what the menu is supposed to look like, and it comes back by
    /// itself if a system update starts honouring it again.
    private static func symbol(_ name: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: Tokens.Metric.menuSwatch, weight: .regular))
    }
}
