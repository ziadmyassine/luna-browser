//
//  BrowserSession+History.swift
//  Luna
//
//  Deleting history (§11.3), in the Space in front: chosen pages, a span of
//  time, or a whole site together with what the site keeps in the Space's
//  cookie jar. The store does the deleting; this picks the Space and the jar,
//  and tells the Command Bar's in-memory lessons that they are stale.
//

import BrowserKit
import Foundation
import WebKit

/// The spans History ▸ Clear History… offers, Safari's four.
enum HistoryClearRange: CaseIterable {
    case lastHour, today, todayAndYesterday, everything

    var title: String {
        switch self {
        case .lastHour: String(localized: "the last hour")
        case .today: String(localized: "today")
        case .todayAndYesterday: String(localized: "today and yesterday")
        case .everything: String(localized: "all history")
        }
    }

    /// Where the span starts, or nil for all of it. Days are calendar days,
    /// so "today" at 00:30 is half an hour.
    func start(now: Date = Date(), calendar: Calendar = .current) -> Date? {
        let midnight = calendar.startOfDay(for: now)
        switch self {
        case .lastHour: return now.addingTimeInterval(-60 * 60)
        case .today: return midnight
        case .todayAndYesterday: return calendar.date(byAdding: .day, value: -1, to: midnight)
        case .everything: return nil
        }
    }
}

extension BrowserSession {

    /// Posted with the store as its object after history was deleted, for what
    /// holds a copy of it: `AdaptiveHistory`'s table, which the Command Bar
    /// reads without asking SQLite.
    static let historyDidChange = Notification.Name("LunaHistoryDidChange")

    /// These pages, out of the active Space's history.
    func deleteHistory(of urls: [URL]) async {
        let space = activeSpaceID
        try? await store.deleteHistory(of: urls, inSpace: space)
        announceHistoryChange()
    }

    func clearHistory(_ range: HistoryClearRange, now: Date = Date()) async {
        let space = activeSpaceID
        try? await store.deleteHistory(since: range.start(now: now), inSpace: space)
        announceHistoryChange()
    }

    /// The site's pages out of the active Space's history, and its cookies,
    /// storage and caches out of the Space's jar. Only this Space's: another
    /// Space is another login (§9.2).
    ///
    /// - Parameter site: a registrable domain, as `PublicSuffix.siteKey` gives it.
    func forgetSite(_ site: String) async {
        let space = activeSpaceID
        try? await store.deleteHistory(ofSite: site, inSpace: space)
        announceHistoryChange()
        await Self.removeWebsiteData(ofSite: site, from: dataStore(forSpace: space))
    }

    /// Every record WebKit keeps for the site. A record's `displayName` is its
    /// registrable domain, so `apple.com`'s holds `developer.apple.com`'s
    /// cookies too; the suffix match is for a host with no registrable domain
    /// (`localhost`), whose record is named by the host itself.
    static func removeWebsiteData(ofSite site: String, from store: WKWebsiteDataStore) async {
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        let records = await store.dataRecords(ofTypes: types).filter {
            $0.displayName == site || $0.displayName.hasSuffix(".\(site)")
        }
        guard !records.isEmpty else { return }
        await store.removeData(ofTypes: types, for: records)
    }

    private func announceHistoryChange() {
        NotificationCenter.default.post(name: Self.historyDidChange, object: store)
    }
}
