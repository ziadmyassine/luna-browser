//
//  SiteMenu.swift
//  Luna
//
//  §3.2's site menu: everything you can say about the page you are on,
//  behind the sliders glyph on the URL pill's trailing edge.
//
//  Per-site, not global, which is why this exists rather than three more rows
//  in Settings. "Block ads" as a preference is a decision you make once and
//  then fight with on the four sites it breaks; "Block Ads & Trackers" here is
//  a decision about this site, taken where you noticed the problem. Settings
//  keeps the genuinely global questions — which filter lists are on at all,
//  HTTPS-Only, clearing everything (SETTINGS-SPEC §3.3).
//
//  A plain `NSMenu`, which on macOS 26 is the liquid-glass menu: AppKit draws
//  its own material, blur and submenu chevrons, and a hand-rolled panel would
//  be a worse copy that also had to re-implement keyboard navigation,
//  VoiceOver and Reduce Transparency.
//
//  The glyphs ride in the titles, because `NSMenuItem.image` draws nothing
//  here — the measurement is in `SidebarMenu.label(symbol:title:in:)`, which
//  draws this menu and §3.4a's tab menu, so the two cannot drift apart on icon
//  size, tint or alignment.
//

import AppKit
import BrowserKit
import WebKit

@MainActor
enum SiteMenu {

    /// Opens the menu under `anchor` — §3.2's sliders glyph, or §4's.
    static func present(from anchor: NSView) {
        build(from: anchor).popUp(positioning: nil, at: NSPoint(x: 0, y: anchor.bounds.maxY), in: anchor)
    }

    /// The menu for whatever page is on screen right now. Built fresh every
    /// time: every item in it is a statement about the current tab, and a menu
    /// held over from the last one would be checkmarks for another site.
    ///
    /// - Parameter anchor: the glyph the menu hangs off, which the share sheet
    ///   hangs off too — the menu is gone by the time Share fires, and a
    ///   picker needs a view on screen to point at.
    static func build(from anchor: NSView) -> NSMenu {
        let menu = NSMenu()
        // Closure items are their own target so AppKit would enable them anyway;
        // turning this off is for the two that must stay *dis*abled.
        menu.autoenablesItems = false
        guard let page = current else {
            menu.addItem(SidebarMenu.header(String(localized: "No page")))
            return menu
        }

        // The system picker, from an ordinary item. Not
        // `NSSharingServicePicker.standardShareMenuItem`, and not a submenu
        // either: the reference's chevron is `sharingServices(forItems:)`,
        // deprecated since macOS 13 with Apple's own note pointing at the
        // picker, and a submenu is not worth building a stale copy of the share
        // sheet to get. What this item shows is the same sheet with the same
        // destinations; all it gives up is AppKit assembling the row.
        //
        // Which it assembles wrong here. `standardShareMenuItem` draws a share
        // glyph nothing on the item controls: `image` is nil before the menu
        // opens and still nil after `menu.update()` — probed — and AppKit draws
        // one regardless, a size under this menu's own glyphs. Dressed like
        // every other row it came out as two share marks side by side; left
        // undressed it is AppKit's smaller mark with a title 4 pt short of the
        // column.
        //
        // The picker is held, not let go: a picker that falls out of scope
        // as the closure returns takes the sheet with it.
        let share = SidebarMenu.item(title: String(localized: "Share…")) { [weak anchor, url = page.url] in
            guard let anchor else { return }
            let picker = NSSharingServicePicker(items: [url])
            sharePicker = picker
            picker.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        }
        menu.addItem(glyph(Glyph.share, on: share))
        menu.addItem(copyLink(page.url))
        menu.addItem(.separator())

        menu.addItem(blocking(host: page.host))
        menu.addItem(permission(
            .automaticPictureInPicture,
            title: String(localized: "Automatic Picture-In-Picture"),
            symbol: Glyph.pictureInPicture,
            host: page.host,
            thenReload: false
        ))
        menu.addItem(permission(
            .localNetwork,
            title: String(localized: "Local Network"),
            symbol: Glyph.localNetwork,
            host: page.host,
            thenReload: true
        ))
        menu.addItem(.separator())

        let settings = NSMenuItem(title: String(localized: "Site Settings"), action: nil, keyEquivalent: "")
        settings.submenu = siteSettings(host: page.host)
        menu.addItem(glyph(Glyph.siteSettings, on: settings))

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

    /// See `build(from:)`. One at a time: the sheet is modal, so the previous
    /// one is always finished with by the time the next is asked for.
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
        return glyph(Glyph.link, on: item)
    }

    /// §17.2's per-site exemption, read the way round a user thinks about it:
    /// the checkmark means blocking is on here, not that an exemption is.
    private static func blocking(host: String) -> NSMenuItem {
        let scope = session?.sitePermissions ?? .shared
        let on = !ContentBlocker.shared.isDisabled(forHost: host, in: scope)
        let item = SidebarMenu.item(title: String(localized: "Block Ads & Trackers")) {
            ContentBlocker.shared.setDisabled(on, forHost: host, in: scope)
            reapplyRules(reload: true)
        }
        item.state = on ? .on : .off
        return glyph(Glyph.blocking, on: item)
    }

    private static func permission(
        _ permission: BrowserStore.SitePermission,
        title: String,
        symbol name: String,
        host: String,
        thenReload reload: Bool
    ) -> NSMenuItem {
        let scope = session?.sitePermissions ?? .shared
        let on = scope.isAllowed(permission, forHost: host)
        let item = SidebarMenu.item(title: title) {
            scope.setAllowed(!on, permission, forHost: host)
            // Only the ones that change what the page may load. Picture-in-
            // Picture is read at the moment the tab is left, so re-loading the
            // page to apply it would throw away the video it is about.
            if reload { reapplyRules(reload: true) }
        }
        item.state = on ? .on : .off
        return glyph(name, on: item)
    }

    private static func siteSettings(host: String) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(glyph(Glyph.cache, on: SidebarMenu.item(title: String(localized: "Clear Cache")) {
            clear(SiteData.caches, host: host, thenReload: true)
        }))
        menu.addItem(glyph(Glyph.cookies, on: SidebarMenu.item(title: String(localized: "Clear Cookies")) {
            clear(SiteData.cookies, host: host, thenReload: true)
        }))
        menu.addItem(.separator())
        menu.addItem(glyph(Glyph.advanced, on: SidebarMenu.item(title: String(localized: "Advanced Settings")) {
            (NSApp.delegate as? AppDelegate)?.showSettings(section: AdvancedSection.id)
        }))
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
        // Drawn like any other item and then dimmed by AppKit, attachment and all —
        // measured, because an attributed title could as easily have come out at full
        // strength beside a greyed word. No hand-applied secondary ink: on top of the
        // system's own dimming it reads as faded rather than quiet.
        return glyph(secure ? Glyph.secure : Glyph.insecure, on: item)
    }

    // MARK: - Doing the work

    /// Re-attaches the rule lists for the site's new answers and, where the
    /// answer changes what may load, fetches the page again — a rule list only
    /// binds loads that have not happened yet.
    private static func reapplyRules(reload: Bool) {
        guard let session, let id = session.activeTabID,
              let webView = session.controller(for: id)?.webView
        else { return }
        ContentBlocker.shared.apply(
            to: webView.configuration.userContentController,
            host: webView.url?.host(percentEncoded: false),
            scope: session.sitePermissions
        )
        if reload { webView.reload() }
    }

    /// The two groups §3.2's submenu offers. Split the way the user means it:
    /// Clear Cache should not sign you out, and Clear Cookies should.
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
    /// The store is the tab's, not `.default()`: a Space with its own
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

    // MARK: - The glyphs

    /// Puts the reference's glyph beside an item's word.
    ///
    /// Not `NSMenuItem.image`, which draws nothing on this macOS. Measured with
    /// five images on five items — template symbol, non-template symbol,
    /// explicit size, a plain red square and a named AppKit template — in Luna
    /// and in a bare test app, and not one appeared.
    /// `SidebarMenu.label(symbol:title:in:)` puts the symbol in the title
    /// instead, keeping the native highlight, arrow keys and submenu chevron a
    /// custom `NSMenuItem.view` would have cost.
    ///
    /// Read `item.title` before writing it: `attributedTitle` is what `title` returns once
    /// one is set, so this may be applied to any item exactly once. The plain title stays
    /// underneath for VoiceOver and type-select.
    @discardableResult
    static func glyph(_ name: String, on item: NSMenuItem) -> NSMenuItem {
        item.attributedTitle = SidebarMenu.label(symbol: name, title: item.title)
        return item
    }

    /// Every symbol this menu draws, named in one place.
    ///
    /// A misspelt SF Symbol is not an error and not a fallback box — `NSImage` returns nil
    /// and the label is simply drawn without its glyph, one item silently out of line with
    /// the rest. `SiteMenuGlyphTests` walks this list so that a name the system does not
    /// have is a test failure instead.
    enum Glyph {
        static let share = "square.and.arrow.up"
        static let link = "link"
        /// §4's layout has no reload button, so its copy of this menu grows a Reload row
        /// (`TopBarURLPill`). The glyph is named here with the rest so the row that only
        /// one layout ever sees is covered by the same test as the rows everyone sees.
        static let reload = "arrow.clockwise"
        static let blocking = "hand.raised"
        static let pictureInPicture = "pip"
        static let localNetwork = "network"
        static let siteSettings = "gearshape"
        static let cache = "internaldrive"
        static let cookies = "trash"
        /// The sliders that open this menu in the first place (§3.2), which is as close as
        /// the family comes to "the rest of the settings are through here".
        static let advanced = "slider.horizontal.3"
        static let secure = "lock"
        static let insecure = "lock.open"

        static let all = [
            share, link, reload, blocking, pictureInPicture, localNetwork,
            siteSettings, cache, cookies, advanced, secure, insecure
        ]
    }
}
