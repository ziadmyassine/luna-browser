//
//  SiteMenu.swift
//  Luna
//
//  §3.2's site settings: everything you can say about the page you are on,
//  behind the sliders glyph on the URL pill and on §4's selected tab. What
//  it shows is `SiteSettingsPanel`; this is what goes in it and what each
//  row does.
//
//  Per-site, not global, which is why this exists rather than three more rows
//  in Settings. "Block ads" as a preference is a decision you make once and
//  then fight with on the four sites it breaks; "Block Ads & Trackers" here is
//  a decision about this site, taken where you noticed the problem. Settings
//  keeps the genuinely global questions — which filter lists are on at all,
//  HTTPS-Only, clearing everything (SETTINGS-SPEC §3.3).
//

import AppKit
import BrowserKit
import WebKit

@MainActor
enum SiteMenu {

    /// Opens the pop-out on `anchor`, or closes it if it is already up.
    ///
    /// One controller for every window: a pop-out is the thing under the
    /// pointer, and there is only one pointer.
    static func present(from anchor: NSView) {
        guard let window = anchor.window else { return }
        let edge: PopoutEdge = anchor.convert(anchor.bounds, to: nil).midY > window.contentLayoutRect.midY
            ? .below
            : .above
        controller.toggle(in: window, from: anchor, edge: edge, content: content(from: anchor))
    }

    static let controller = SiteSettingsController()

    /// What the pop-out shows for whatever page is on screen right now. Built
    /// fresh every time: every row in it is a statement about the current tab,
    /// and one held over from the last would be switches for another site.
    ///
    /// - Parameter anchor: the glyph the pop-out stands on, which the share
    ///   sheet points at too — the pop-out is gone by the time Share fires.
    static func content(from anchor: NSView) -> SiteSettingsContent {
        guard let page = current else {
            return SiteSettingsContent(heading: String(localized: "No site settings for this page"))
        }
        var content = SiteSettingsContent(heading: page.host)
        if let secure = isSecure(page) {
            content.connection = secure ? .secure : .insecure
            content.heading = secure
                ? String(localized: "Connection is Secure")
                : String(localized: "Connection is Not Secure")
        }
        content.toggles = [
            blocking(host: page.host),
            permission(
                .automaticPictureInPicture,
                title: String(localized: "Automatic Picture-in-Picture"),
                symbol: Glyph.pictureInPicture,
                host: page.host,
                thenReload: false
            ),
            permission(
                .localNetwork,
                title: String(localized: "Local Network"),
                symbol: Glyph.localNetwork,
                host: page.host,
                thenReload: true
            )
        ]
        content.actions = [
            [share(page.url, from: anchor), copyLink(page.url)],
            [
                .init(title: String(localized: "Clear Cache"), symbol: Glyph.cache) {
                    clear(SiteData.caches, host: page.host, thenReload: true)
                },
                .init(title: String(localized: "Clear Cookies"), symbol: Glyph.cookies) {
                    clear(SiteData.cookies, host: page.host, thenReload: true)
                },
                .init(title: String(localized: "More Settings…"), symbol: Glyph.advanced) {
                    (NSApp.delegate as? AppDelegate)?.showSettings(section: AdvancedSection.id)
                }
            ]
        ]
        return content
    }

    // MARK: - The page

    /// Everything the pop-out needs to know about the tab on screen. A page
    /// with no host — `luna:new-tab`, `about:blank` — is not a site and has no
    /// per-site answers to give, so the pop-out says so rather than offering
    /// switches that would be filed under an empty string.
    private struct Page {
        var url: URL
        var host: String
        var webView: WKWebView?
    }

    private static var session: BrowserSession? { (NSApp.delegate as? AppDelegate)?.session }

    /// See `share(_:from:)`. One at a time: the sheet is modal, so the previous
    /// one is always finished with by the time the next is asked for.
    private static var sharePicker: NSSharingServicePicker?

    private static var current: Page? {
        guard let session, let id = session.activeTabID, let tab = session.tab(id) else { return nil }
        // The tab's URL is the one the sidebar is showing; the web view's is the
        // one WebKit has, and they differ mid-navigation. The pill's is right.
        guard let host = tab.url.host(percentEncoded: false)?.lowercased(), !host.isEmpty else { return nil }
        return Page(url: tab.url, host: host, webView: session.controller(for: id)?.webView)
    }

    // MARK: - Rows

    /// The system picker, pointed at the glyph the pop-out stood on. Held, not
    /// let go: a picker that falls out of scope as the closure returns takes
    /// the sheet with it.
    private static func share(_ url: URL, from anchor: NSView) -> SiteSettingsContent.Action {
        .init(title: String(localized: "Share…"), symbol: Glyph.share) { [weak anchor] in
            guard let anchor, anchor.window != nil else { return }
            let picker = NSSharingServicePicker(items: [url])
            sharePicker = picker
            picker.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        }
    }

    private static func copyLink(_ url: URL) -> SiteSettingsContent.Action {
        .init(title: String(localized: "Copy Link"), symbol: Glyph.link) {
            NSPasteboard.general.clearContents()
            // As a string as well as a URL: a plain text field pasted into gets
            // the address rather than nothing at all.
            NSPasteboard.general.writeObjects([url as NSURL])
            NSPasteboard.general.setString(url.absoluteString, forType: .string)
        }
    }

    /// §17.2's per-site exemption, read the way round a user thinks about it:
    /// the switch on means blocking is on here, not that an exemption is.
    private static func blocking(host: String) -> SiteSettingsContent.Toggle {
        let scope = session?.sitePermissions ?? .shared
        return .init(
            title: String(localized: "Block Ads & Trackers"),
            symbol: Glyph.blocking,
            isOn: !ContentBlocker.shared.isDisabled(forHost: host, in: scope)
        ) { on in
            ContentBlocker.shared.setDisabled(!on, forHost: host, in: scope)
            reapplyRules(reload: true)
        }
    }

    private static func permission(
        _ permission: BrowserStore.SitePermission,
        title: String,
        symbol name: String,
        host: String,
        thenReload reload: Bool
    ) -> SiteSettingsContent.Toggle {
        let scope = session?.sitePermissions ?? .shared
        return .init(title: title, symbol: name, isOn: scope.isAllowed(permission, forHost: host)) { on in
            scope.setAllowed(on, permission, forHost: host)
            // Only the ones that change what the page may load. Picture-in-
            // Picture is read at the moment the tab is left, so re-loading the
            // page to apply it would throw away the video it is about.
            if reload { reapplyRules(reload: true) }
        }
    }

    /// Nil for a page that is not on the web at all.
    ///
    /// `hasOnlySecureContent` is the whole question — an https page that pulled
    /// an image over http is not a secure page, and saying otherwise beside a
    /// padlock is the one lie a browser must never tell.
    private static func isSecure(_ page: Page) -> Bool? {
        guard let scheme = page.url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return nil }
        return scheme == "https" && (page.webView?.hasOnlySecureContent ?? true)
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

    /// The two clears the pop-out offers. Split the way the user means it:
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

    /// Every symbol the pop-out draws, named in one place.
    ///
    /// A misspelt SF Symbol is not an error and not a fallback box — `NSImage` returns nil
    /// and the row is simply drawn without its glyph, one row silently out of line with
    /// the rest. `SiteMenuGlyphTests` walks this list so that a name the system does not
    /// have is a test failure instead.
    enum Glyph {
        static let share = "square.and.arrow.up"
        static let link = "link"
        static let blocking = "hand.raised"
        static let pictureInPicture = "pip"
        static let localNetwork = "network"
        static let cache = "internaldrive"
        static let cookies = "trash"
        /// The sliders that open the pop-out in the first place (§3.2), which is as close
        /// as the family comes to "the rest of the settings are through here".
        static let advanced = "slider.horizontal.3"
        static let secure = "lock"
        static let insecure = "lock.open"
        /// The header of a page that is not on the web, where there is no connection to
        /// speak of — `SidebarRowContent.siteFallbackSymbol`, the mark such a tab wears.
        static let site = SidebarRowContent.siteFallbackSymbol

        static let all = [
            share, link, blocking, pictureInPicture, localNetwork,
            cache, cookies, advanced, secure, insecure, site
        ]
    }
}
