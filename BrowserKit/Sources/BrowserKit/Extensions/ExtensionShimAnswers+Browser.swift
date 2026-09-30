import Foundation
import WebKit

// Adapted from Search's ExtensionShims.swift (github.com/driceroland/Search),
// MIT License, Copyright (c) 2026 Office Commun; the full notice is at the top
// of Resources/ExtensionShim.js.

/// The shim's calls about the browser: history, closed tabs, search,
/// downloads, the side panel, sign-in and site data. Tabs and groups are in
/// `ExtensionShimAnswers+Tabs`. What only the app knows goes through
/// `ExtensionServices`.
extension ExtensionHost {

    func answerBrowserFamily(_ api: String, _ args: [Any], context: WKWebExtensionContext) async throws -> ShimAnswer? {
        switch String(api.prefix { $0 != "." }) {
        case "tabs", "tabGroups": try answerTabs(api, args, context: context) ?? answerTabGroups(api, args)
        case "history": try await answerHistory(api, args.first as? [String: Any] ?? [:])
        case "topSites", "sessions": try await answerSessions(api, args)
        case "search": try answerSearch(api, args.first as? [String: Any] ?? [:])
        case "downloads": try await answerDownloads(api, args, context: context)
        case "sidePanel": answerSidePanel(api, args.first as? [String: Any] ?? [:], context: context)
        case "identity": try await answerIdentity(api, args.first as? [String: Any] ?? [:], context: context)
        case "browsingData", "readingList": try await answerSiteData(api, args)
        case "capture": throw ExtensionShimRefusal(why: "Recording the screen isn't available to extensions in Luna")
        default: nil
        }
    }

    // MARK: - History and closed tabs

    private func answerHistory(_ api: String, _ spec: [String: Any]) async throws -> ShimAnswer? {
        guard let store else { throw ExtensionShimRefusal.unavailable(api) }
        switch api {
        case "history.search":
            // Chrome's default: the last day, unless the extension says otherwise.
            let start = (spec["startTime"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) } ?? Date(timeIntervalSinceNow: -86_400)
            let end = (spec["endTime"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) } ?? .distantFuture
            let limit = max(spec["maxResults"] as? Int ?? 100, 0)
            let hits = try await store.browsingHistory(matching: spec["text"] as? String ?? "", limit: max(limit, 1) * 4, inSpace: spaceID)
            let inRange = hits.filter { (start ... end).contains($0.lastVisit ?? .distantPast) }
            return ShimAnswer(inRange.prefix(limit).map(Self.historyItem))
        case "history.getVisits":
            guard let url = spec["url"] as? String else { return ShimAnswer([Any]()) }
            let hits = try await store.browsingHistory(matching: "", limit: 5000, inSpace: spaceID)
            return ShimAnswer(hits.filter { $0.url.absoluteString == url }.map(Self.visit))
        case "history.addUrl":
            guard let url = (spec["url"] as? String).flatMap(URL.init(string:)) else { return ShimAnswer(nil) }
            try await store.recordVisit(url: url, title: spec["title"] as? String ?? "", kind: .link, at: Date(), inSpace: spaceID)
            return ShimAnswer(nil)
        case "history.deleteUrl", "history.deleteRange", "history.deleteAll":
            throw ExtensionShimRefusal(why: "Extensions can't delete history in Luna yet")
        default:
            return nil
        }
    }

    private func answerSessions(_ api: String, _ args: [Any]) async throws -> ShimAnswer? {
        switch api {
        case "topSites.get":
            guard let store else { return ShimAnswer([Any]()) }
            let hits = try await store.browsingHistory(matching: "", limit: 500, inSpace: spaceID)
            var byHost: [String: (hit: HistoryHit, count: Int)] = [:]
            for hit in hits {
                guard let host = hit.url.host() else { continue }
                byHost[host, default: (hit, 0)].count += 1
            }
            return ShimAnswer(byHost.values.sorted { $0.count > $1.count }.prefix(10).map {
                ["url": $0.hit.url.absoluteString, "title": $0.hit.title]
            })
        case "sessions.getRecentlyClosed":
            guard let store else { return ShimAnswer([Any]()) }
            let limit = (args.first as? [String: Any])?["maxResults"] as? Int ?? 25
            let closed = try await store.tabs(inSpace: spaceID, includeArchived: true)
                .filter { $0.archivedAt != nil }
                .sorted { ($0.archivedAt ?? .distantPast) > ($1.archivedAt ?? .distantPast) }
            return ShimAnswer(closed.prefix(limit).map(Self.closedSession))
        case "sessions.getDevices":
            return ShimAnswer([Any]())
        case "sessions.restore":
            let id = (args.first as? String).flatMap(UUID.init(uuidString:))
            guard let restored = try services(for: api).extensionRestoreClosed(id, inSpace: spaceID) else {
                throw ExtensionShimRefusal(why: "Nothing to restore")
            }
            sync()
            let tab: [String: Any] = ["url": restored.url.absoluteString, "title": restored.title, "index": 0, "windowId": 1]
            return ShimAnswer(["lastModified": Int(Date().timeIntervalSince1970), "tab": tab])
        default:
            return nil
        }
    }

    /// A stable id for a page, since Luna's history rows are not numbered for
    /// extensions: the same page gives the same id every time it is asked for.
    private static func historyID(_ url: URL) -> String {
        String(UInt32(truncatingIfNeeded: url.absoluteString.utf8.reduce(UInt64(5381)) { ($0 << 5) &+ $0 &+ UInt64($1) }))
    }

    private static func historyItem(_ hit: HistoryHit) -> [String: Any] {
        ["id": historyID(hit.url), "url": hit.url.absoluteString, "title": hit.title,
         "lastVisitTime": (hit.lastVisit ?? Date()).timeIntervalSince1970 * 1000, "visitCount": 1, "typedCount": 0]
    }

    /// Luna shows extensions a page's last visit, so that is its one visit.
    private static func visit(_ hit: HistoryHit) -> [String: Any] {
        ["id": historyID(hit.url), "visitId": historyID(hit.url), "visitTime": (hit.lastVisit ?? Date()).timeIntervalSince1970 * 1000,
         "referringVisitId": "0", "transition": "link"]
    }

    private static func closedSession(_ tab: Tab) -> [String: Any] {
        ["lastModified": Int((tab.archivedAt ?? Date()).timeIntervalSince1970),
         "tab": ["sessionId": tab.id.uuidString, "url": tab.url.absoluteString, "title": tab.title, "index": 0, "windowId": 1,
                 "active": false, "pinned": false, "highlighted": false, "incognito": false, "selected": false,
                 "discarded": false, "autoDiscardable": true, "groupId": -1] as [String: Any]]
    }

    // MARK: - Search and downloads

    /// Words to search for, as in Chrome: never an address, which the address
    /// field would take.
    private func answerSearch(_ api: String, _ spec: [String: Any]) throws -> ShimAnswer? {
        guard api == "search.query" else { return nil }
        guard let url = try services(for: api).extensionSearchURL(for: spec["text"] as? String ?? "") else { return ShimAnswer(nil) }
        switch spec["disposition"] as? String {
        case "NEW_TAB", "NEW_WINDOW": _ = browser?.openExtensionTab(url: url, inSpace: spaceID, configuration: nil, activate: true)
        default: if let tab = snapshot.activeTab { browser?.loadURL(url, inTab: tab) }
        }
        return ShimAnswer(nil)
    }

    private func answerDownloads(_ api: String, _ args: [Any], context: WKWebExtensionContext) async throws -> ShimAnswer? {
        let spec = args.first as? [String: Any] ?? [:]
        switch api {
        case "downloads.download":
            guard let url = (spec["url"] as? String).flatMap(URL.init(string:)) else {
                throw ExtensionShimRefusal(why: "No url to download")
            }
            // A name it asks for may carry folders: only the last part is kept.
            let name = (spec["filename"] as? String).flatMap { $0.isEmpty ? nil : ($0 as NSString).lastPathComponent }
            let download = try await services(for: api).extensionDownload(url, filename: name, inSpace: spaceID)
            shim.ownDownloads[context.uniqueIdentifier, default: []].insert(download.id)
            return ShimAnswer(downloadNumber(download.id))
        case "downloads.search":
            let wanted = spec["id"] as? Int
            return ShimAnswer(try services(for: api).extensionDownloads(inSpace: spaceID)
                .filter { wanted == nil || downloadNumber($0.id) == wanted }
                .map(chromeDownload))
        case "downloads.show", "downloads.open":
            try showOrOpen(api, number: args.first as? Int, context: context)
            return ShimAnswer(nil)
        case "downloads.showDefaultFolder":
            try services(for: api).extensionShowDownloadsFolder()
            return ShimAnswer(nil)
        case "downloads.erase":
            return ShimAnswer([Int]())
        default:
            return nil
        }
    }

    /// Showing a file in Finder is always allowed. Opening it is, as in Chrome,
    /// its own permission, only just after the person used the extension, and
    /// only for a file this extension downloaded itself.
    private func showOrOpen(_ api: String, number: Int?, context: WKWebExtensionContext) throws {
        let id = context.uniqueIdentifier
        let services = try services(for: api)
        guard let number, let download = services.extensionDownloads(inSpace: spaceID).first(where: { downloadNumber($0.id) == number })
        else { return }
        guard api == "downloads.open" else { return services.extensionRevealDownload(download.id) }
        guard shimAllowed(context).contains("downloads.open") else { throw ExtensionShimRefusal.notAsked("downloads.open") }
        guard let pressed = shim.lastPress[id], Date().timeIntervalSince(pressed) < Self.pressWindow else {
            throw ExtensionShimRefusal(why: "downloads.open() may only be called in response to a user gesture.")
        }
        guard shim.ownDownloads[id]?.contains(download.id) == true else {
            throw ExtensionShimRefusal(why: "Only a download this extension started can be opened by it")
        }
        services.extensionOpenDownload(download.id)
    }

    /// Chrome's download ids are numbers: one per download, kept while Luna runs.
    private func downloadNumber(_ id: UUID) -> Int {
        if let known = shim.downloadNumbers[id] { return known }
        let number = shim.downloadNumbers.count + 1
        shim.downloadNumbers[id] = number
        return number
    }

    private func chromeDownload(_ download: ExtensionDownload) -> [String: Any] {
        ["id": downloadNumber(download.id), "url": download.url.absoluteString, "finalUrl": download.url.absoluteString,
         "filename": download.path, "state": download.state.rawValue, "exists": download.exists,
         "startTime": ISO8601DateFormatter().string(from: download.startTime), "mime": "", "paused": false,
         "canResume": false, "bytesReceived": download.bytesReceived, "totalBytes": download.totalBytes,
         "fileSize": download.totalBytes, "danger": "safe", "incognito": false]
    }

    // MARK: - Side panel and sign-in

    private func answerSidePanel(_ api: String, _ spec: [String: Any], context: WKWebExtensionContext) -> ShimAnswer? {
        let id = context.uniqueIdentifier
        switch api {
        case "sidePanel.setOptions":
            if let path = spec["path"] as? String { shim.panelPath[id] = path }
            return ShimAnswer(nil)
        case "sidePanel.getOptions":
            return ShimAnswer(["enabled": true, "path": shim.panelPath[id] ?? Self.defaultPanel(context) ?? ""])
        case "sidePanel.setPanelBehavior":
            if let opens = spec["openPanelOnActionClick"] as? Bool {
                if opens { shim.panelOnPress.insert(id) } else { shim.panelOnPress.remove(id) }
            }
            return ShimAnswer(nil)
        case "sidePanel.getPanelBehavior":
            return ShimAnswer(["openPanelOnActionClick": shim.panelOnPress.contains(id)])
        case "sidePanel.open":
            openPanel(context)
            return ShimAnswer(nil)
        default:
            return nil
        }
    }

    private func answerIdentity(_ api: String, _ spec: [String: Any], context: WKWebExtensionContext) async throws -> ShimAnswer? {
        switch api {
        case "identity.launchWebAuthFlow":
            guard let url = (spec["url"] as? String).flatMap(URL.init(string:)) else {
                throw ExtensionShimRefusal(why: "No authorization url")
            }
            // Silent sign-in needs a page nobody sees finishing on its own;
            // Luna shows every sign-in, so it answers as Chrome does when that
            // cannot be done without the user.
            guard spec["interactive"] as? Bool == true else { throw ExtensionShimRefusal(why: "User interaction required.") }
            guard let browser else { throw ExtensionShimRefusal.unavailable(api) }
            let answer = try await ExtensionAuthFlows.run(url, extensionID: context.uniqueIdentifier, inSpace: spaceID, browser: browser)
            return ShimAnswer(answer.absoluteString)
        case "identity.getProfileUserInfo":
            return ShimAnswer(["email": "", "id": ""])
        case "identity.removeCachedAuthToken", "identity.clearAllCachedAuthTokens":
            return ShimAnswer(nil)
        case "identity.getAuthToken":
            throw ExtensionShimRefusal(why: "getAuthToken needs a Google account signed into Chrome; Luna has none to give")
        default:
            return nil
        }
    }

    static func defaultPanel(_ context: WKWebExtensionContext) -> String? {
        (context.webExtension.manifest["side_panel"] as? [String: Any])?["default_path"] as? String
    }

    /// Luna's window has one column for pages, so the side panel is a tab of
    /// its own. The path is resolved, not appended: it can carry a query
    /// (sidepanel.html?tabId=…) that appending would escape into the file's
    /// name. A full address given as a path is refused.
    func openPanel(_ context: WKWebExtensionContext) {
        guard let path = shim.panelPath[context.uniqueIdentifier] ?? Self.defaultPanel(context) else { return }
        let base = context.baseURL
        guard let url = URL(string: path.trimmingCharacters(in: CharacterSet(charactersIn: "/")), relativeTo: base)?.absoluteURL,
              url.scheme == base.scheme, url.host() == base.host()
        else { return }
        _ = browser?.openExtensionTab(url: url, inSpace: spaceID, configuration: context.webViewConfiguration, activate: true)
        sync()
    }

    /// Whether pressing the extension's button opens its side panel.
    func opensPanelOnPress(_ id: String) -> Bool { shim.panelOnPress.contains(id) }

    // MARK: - Site data

    private func answerSiteData(_ api: String, _ args: [Any]) async throws -> ShimAnswer? {
        switch api {
        case "browsingData.settings":
            let permitted = Dictionary(uniqueKeysWithValues: Self.siteDataTypes.keys.map { ($0, true) })
            return ShimAnswer(["options": ["since": 0], "dataToRemove": [String: Bool](), "dataRemovalPermitted": permitted])
        case _ where api.hasPrefix("browsingData.remove"):
            try await removeSiteData(api, args)
            return ShimAnswer(nil)
        case "readingList.query":
            return ShimAnswer([Any]())
        case "readingList.addEntry", "readingList.removeEntry", "readingList.updateEntry":
            throw ExtensionShimRefusal(why: "Luna has no reading list")
        default:
            return nil
        }
    }

    private static let siteDataTypes: [String: Set<String>] = [
        "cache": [WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache, WKWebsiteDataTypeFetchCache],
        "cacheStorage": [WKWebsiteDataTypeFetchCache], "appcache": [WKWebsiteDataTypeOfflineWebApplicationCache],
        "cookies": [WKWebsiteDataTypeCookies], "localStorage": [WKWebsiteDataTypeLocalStorage, WKWebsiteDataTypeSessionStorage],
        "indexedDB": [WKWebsiteDataTypeIndexedDBDatabases], "serviceWorkers": [WKWebsiteDataTypeServiceWorkerRegistrations],
        "webSQL": [WKWebsiteDataTypeWebSQLDatabases], "fileSystems": [WKWebsiteDataTypeFileSystem]
    ]

    /// Kinds of data only the user clears, never an extension.
    private static let usersToClear = ["history", "downloads", "passwords", "formData"]

    /// chrome.browsingData, on this Space's own sites only: what WebKit keeps for them.
    private func removeSiteData(_ api: String, _ args: [Any]) async throws {
        let options = args.first as? [String: Any] ?? [:]
        let what: [String: Bool]
        if api == "browsingData.remove" {
            what = (args.dropFirst().first as? [String: Any] ?? [:]).compactMapValues { $0 as? Bool }
        } else {
            let key = String(api.dropFirst("browsingData.remove".count))
            what = [key.prefix(1).lowercased() + key.dropFirst(): true]
        }
        guard !Self.usersToClear.contains(where: { what[$0] == true }) else {
            throw ExtensionShimRefusal(why: "Extensions can't clear history, downloads, passwords or form data in Luna")
        }
        let types = what.filter(\.value).keys.reduce(into: Set<String>()) { $0.formUnion(Self.siteDataTypes[$1] ?? []) }
        guard !types.isEmpty else { return }
        let since = Date(timeIntervalSince1970: (options["since"] as? Double ?? 0) / 1000)
        guard let origins = (options["origins"] as? [String])?.compactMap({ URL(string: $0)?.host() }) else {
            return await dataStore.removeData(ofTypes: types, modifiedSince: since)
        }
        let records = await dataStore.dataRecords(ofTypes: types).filter { record in
            origins.contains { $0 == record.displayName || $0.hasSuffix("." + record.displayName) }
        }
        await dataStore.removeData(ofTypes: types, for: records)
    }
}
