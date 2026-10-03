//
//  RankingCheckTests.swift
//  LunaTests
//
//  §9.3's acceptance check, run against a real history: is the page the user
//  meant the Command Bar's first row after two typed characters?
//
//  The pages are the 30 newest the user typed or chose their way to (`typed`
//  visits), less search results pages — those were searches, and what was
//  typed for them was the words, not an address. The query is what a person
//  types for a page: its host without `www.`, cut to 2, 3 and 4 characters.
//  Each one is ranked by the real thing — `BrowserStore.searchHistory` and
//  `CommandBarRanking.merge` over the Space's tabs, sites, adaptive lessons, commands
//  and settings — and the first row is compared with the page, and with its
//  site.
//
//  Skipped unless `Tools/ranking-check.sh` has named a database. The script
//  hands over a read-only backup, and this copies that again before opening
//  it, because `BrowserStore` migrates whatever it opens. The pages and the
//  misses go to the output file on this Mac and nowhere else; only the
//  counts are for docs/PERF.md.
//

import GRDB
import XCTest
@testable import BrowserKit
@testable import Luna

@MainActor
final class RankingCheckTests: XCTestCase {

    /// Holds the path of the database to check. A file, not an environment
    /// variable, for the reason `BudgetTests.enabledMarker` gives.
    static let marker = "/tmp/luna-ranking-db"
    static let output = "/tmp/luna-ranking-check.txt"
    static let pages = 30

    private struct Target {
        let url: URL
        let space: UUID
        /// The host as typed: lowercased, without `www.`.
        let typed: String
    }

    private struct Outcome {
        var pageFirst: [Int: Bool] = [:]
        var siteFirst: [Int: Bool] = [:]
        var rows: [Int: [CommandBarResult]] = [:]
    }

    func testTheThirtyNewestTypedPages() async throws {
        guard let named = try? String(contentsOfFile: Self.marker, encoding: .utf8) else {
            throw XCTSkip("§9.3's ranking check — run Tools/ranking-check.sh")
        }
        let source = named.trimmingCharacters(in: .whitespacesAndNewlines)
        let directory = URL.temporaryDirectory.appending(path: "luna-ranking-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let copy = directory.appending(path: "luna.sqlite")
        try FileManager.default.copyItem(at: URL(fileURLWithPath: source), to: copy)
        let store = try BrowserStore(path: copy)

        let targets = try await Self.targets(in: store)
        XCTAssertEqual(targets.count, Self.pages, "fewer typed pages than the check asks for")
        var lines: [String] = []
        var outcomes: [Outcome] = []
        var searchTimes: [Double] = []
        // Read once per Space, as the bar reads it once per opening.
        var sites: [UUID: [VisitedSite]] = [:]
        var siteTimes: [Double] = []
        for target in targets {
            if sites[target.space] == nil {
                let start = CFAbsoluteTimeGetCurrent()
                sites[target.space] = try await store.visitedSites(inSpace: target.space)
                siteTimes.append((CFAbsoluteTimeGetCurrent() - start) * 1000)
            }
            var outcome = Outcome()
            for length in 2...4 {
                let query = String(target.typed.prefix(length))
                let start = CFAbsoluteTimeGetCurrent()
                let rows = try await Self.rows(for: query, inSpace: target.space, sites: sites[target.space] ?? [], store: store)
                searchTimes.append((CFAbsoluteTimeGetCurrent() - start) * 1000)
                let first = rows.first
                outcome.rows[length] = rows
                outcome.pageFirst[length] = first?.url.map(CommandBarURL.dedupeKey) == CommandBarURL.dedupeKey(target.url)
                outcome.siteFirst[length] = first?.url.flatMap(Self.typedHost) == target.typed
            }
            outcomes.append(outcome)
            if outcome.pageFirst[2] != true { lines.append(Self.miss(target, outcome)) }
        }
        let siteCount = sites.values.map(\.count).reduce(0, +)
        lines.insert(Self.summary(outcomes, searchTimes: searchTimes, siteTimes: siteTimes, siteCount: siteCount), at: 0)
        try lines.joined(separator: "\n").appending("\n").write(toFile: Self.output, atomically: true, encoding: .utf8)
    }

    private static func miss(_ target: Target, _ outcome: Outcome) -> String {
        let shown = (outcome.rows[2] ?? []).prefix(3).map { "\($0.source) \($0.url?.absoluteString ?? $0.title)" }
        let place = (outcome.rows[2] ?? []).firstIndex {
            $0.url.map(CommandBarURL.dedupeKey) == CommandBarURL.dedupeKey(target.url)
        }
        return "MISS \"\(target.typed.prefix(2))\" wanted \(target.url.absoluteString)"
            + (outcome.siteFirst[2] == true ? " (its site was first)" : "")
            + "; the page was \(place.map { "row \($0 + 1)" } ?? "not in the list")"
            + ", first at \(firstLength(outcome.pageFirst).map { "\($0) chars" } ?? "no prefix up to 4")"
            + "\n     rows: " + shown.joined(separator: " | ")
    }

    // MARK: - The pages

    private static func targets(in store: BrowserStore) async throws -> [Target] {
        let rows = try await store.pool.read { db in
            try Row.fetchAll(db, sql: """
            SELECT p.url AS url, v.spaceID AS spaceID, MAX(v.at) AS at
            FROM visits v JOIN places p ON p.id = v.placeId
            WHERE v.type = 'typed' AND v.spaceID IS NOT NULL
            GROUP BY p.id, v.spaceID
            ORDER BY at DESC
            """).map { (url: $0["url"] as String, space: $0["spaceID"] as UUID) }
        }
        var seen: Set<String> = []
        var targets: [Target] = []
        for row in rows {
            guard let url = URL(string: row.url),
                  !isSearchResults(url), let typed = typedHost(url), typed.count >= 2,
                  seen.insert(CommandBarURL.dedupeKey(url)).inserted
            else { continue }
            targets.append(Target(url: url, space: row.space, typed: typed))
            if targets.count == pages { break }
        }
        return targets
    }

    /// A results page of one of the engines the bar searches with: its
    /// address and path, with a query.
    private static func isSearchResults(_ url: URL) -> Bool {
        let asked = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.contains { $0.name == "q" } ?? false
        return asked && SearchEngine.allCases.compactMap(\.template).contains { template in
            guard let engine = URL(string: template.replacingOccurrences(of: "%s", with: "x")) else { return false }
            return engine.host() == url.host() && engine.path() == url.path()
        }
    }

    /// What a person types for a page: its host, without `www.`.
    private static func typedHost(_ url: URL) -> String? {
        guard let host = url.host()?.lowercased(), !host.isEmpty else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    // MARK: - Ranking

    /// The bar's rows for `query`, from the same sources it opens with. No
    /// suggestions: they come from the network, and the check is offline.
    private static func rows(
        for query: String, inSpace space: UUID, sites: [VisitedSite], store: BrowserStore
    ) async throws -> [CommandBarResult] {
        var sources = CommandBarSources()
        sources.sites = sites
        sources.tabs = try await store.tabs(inSpace: space, includeArchived: true)
        sources.adaptive = try await store.inputHistory(inSpace: space).map {
            AdaptiveEntry(typed: $0.typed, url: $0.url, useCount: $0.useCount)
        }
        sources.shortcuts = BrowserCommand.commandBarEntries
        sources.settings = SettingsSectionRegistry.commandBarEntries
        sources.history = try await store.searchHistory(query, limit: CommandBarMetrics.historyLimit, inSpace: space)
        return CommandBarRanking.merge(query: query, sources: sources, limit: CommandBarMetrics.visibleRows)
    }

    private static func firstLength(_ hits: [Int: Bool]) -> Int? {
        (2...4).first { hits[$0] == true }
    }

    private static func summary(_ outcomes: [Outcome], searchTimes: [Double], siteTimes: [Double], siteCount: Int) -> String {
        func count(_ hit: (Outcome) -> Bool) -> String {
            let hits = outcomes.filter(hit).count
            return "\(hits)/\(outcomes.count) (\(Int((Double(hits) / Double(max(outcomes.count, 1)) * 100).rounded())) %)"
        }
        let sorted = searchTimes.sorted()
        let median = sorted.isEmpty ? 0 : sorted[sorted.count / 2]
        return "RANKING \(outcomes.count) typed pages. Page first at 2 chars \(count { $0.pageFirst[2] == true }), "
            + "by 3 \(count { firstLength($0.pageFirst).map { $0 <= 3 } ?? false }), "
            + "by 4 \(count { firstLength($0.pageFirst) != nil }). "
            + "Site first at 2 chars \(count { $0.siteFirst[2] == true }), "
            + "by 3 \(count { firstLength($0.siteFirst).map { $0 <= 3 } ?? false }), "
            + "by 4 \(count { firstLength($0.siteFirst) != nil }). "
            + String(format: "Sources, store search and merge per query: median %.1f ms. ", median)
            + String(format: "Sites read: %d in %d Space(s), slowest %.1f ms.", siteCount, siteTimes.count, siteTimes.max() ?? 0)
    }
}
