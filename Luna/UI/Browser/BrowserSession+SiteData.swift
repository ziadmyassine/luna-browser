//
//  BrowserSession+SiteData.swift
//  Luna
//
//  What a site keeps in a Space's cookie jar, and taking it out: the Command
//  Bar's Clear Cookies (§9.2) and History's Forget This Site (§11.3). The jar
//  is the Space's, never `.default()` — a Space has its own
//  `WKWebsiteDataStore` (§5.1), and clearing the wrong one would report
//  success and change nothing.
//

import BrowserKit
import Foundation
import WebKit

extension BrowserSession {

    /// What Clear Cookies takes: what signs a site in and what it keeps about
    /// the user, and not its caches, which sign nobody out.
    static let cookieDataTypes: Set<String> = [
        WKWebsiteDataTypeCookies,
        WKWebsiteDataTypeLocalStorage,
        WKWebsiteDataTypeSessionStorage,
        WKWebsiteDataTypeIndexedDBDatabases
    ]

    /// The registrable domain of the page in the active tab, or nil when it
    /// shows no web page.
    var activeSite: String? {
        guard let url = activeURL, ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return PublicSuffix.siteKey(forHost: url.host())
    }

    /// Clears the active tab's site's cookies and storage from the Space's
    /// jar and reloads the tab, so the page shows itself signed out. Returns
    /// the site, or nil when there was none.
    func clearCookiesOfActiveSite() async -> String? {
        guard let site = activeSite else { return nil }
        let tab = activeTabID
        await Self.removeWebsiteData(ofSite: site, from: dataStore(forSpace: activeSpaceID), types: Self.cookieDataTypes)
        if let tab { controller(for: tab)?.reload() }
        return site
    }

    /// Every record WebKit keeps for the site, of `types`. A record's
    /// `displayName` is its registrable domain, so `apple.com`'s holds
    /// `developer.apple.com`'s cookies too; the suffix match takes a record
    /// named by a subdomain as well, should WebKit ever give one its own.
    static func removeWebsiteData(
        ofSite site: String,
        from store: WKWebsiteDataStore,
        types: Set<String> = WKWebsiteDataStore.allWebsiteDataTypes()
    ) async {
        let records = await store.dataRecords(ofTypes: types).filter {
            $0.displayName == site || $0.displayName.hasSuffix(".\(site)")
        }
        guard !records.isEmpty else { return }
        await store.removeData(ofTypes: types, for: records)
    }
}
