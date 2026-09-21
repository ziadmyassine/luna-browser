//
//  CommandBarRankingTests.swift
//  LunaTests
//
//  §9.3, asserted against hand-computed numbers, the same way
//  `FrecencyRankingTests` asserts the store's half. The expected order is
//  spelled out in the test rather than derived from the code under test.
//
//  Frecency itself is not re-tested here. `BrowserStore` computes it and owns
//  its tests; what this file asserts is the half the store cannot see — the tier
//  order across §9.2's sources, the dedupe, and §9.3's adaptive input history.
//

import BrowserKit
import XCTest
@testable import Luna

final class CommandBarRankingTests: XCTestCase {

    private let workSpace = Space(
        name: "Work",
        symbolName: "hammer",
        gradient: .defaultSpace
    )

    private func url(_ text: String) -> URL { URL(string: text)! }

    private func tab(
        _ address: String,
        title: String,
        minutesAgo: Double,
        archived: Bool = false
    ) -> Tab {
        let when = Date(timeIntervalSinceReferenceDate: 100_000 - minutesAgo * 60)
        return Tab(
            spaceID: workSpace.id,
            url: url(address),
            title: title,
            lastActiveAt: when,
            archivedAt: archived ? when : nil
        )
    }

    /// The fixture every ordering test below reads. Query is "git" throughout.
    ///
    /// Adaptive (§9.3, matched by remembered input starts with what you typed):
    ///   "git"    → github.com/luna   useCount 2.71
    ///   "gitlab" → gitlab.com        useCount 5.20
    ///   "news"   → news.example      does not match "git"
    /// Open tabs: github.com/luna (also the adaptive winner), git-scm.com.
    /// Archived: gitea.example.
    /// History: gitbig.example 9999, git-scm.com 340, gitbook.example 120.
    private func fixture() -> (sources: CommandBarSources, githubTab: Tab) {
        let githubTab = tab("https://github.com/luna", title: "Luna", minutesAgo: 1)
        var sources = CommandBarSources()
        sources.spaces = [workSpace.id: workSpace]
        sources.tabs = [
            githubTab,
            tab("https://git-scm.com/", title: "Git", minutesAgo: 30),
            tab("https://example.com/", title: "Example", minutesAgo: 2),
            tab("https://gitea.example/", title: "Gitea", minutesAgo: 90, archived: true)
        ]
        sources.adaptive = [
            AdaptiveEntry(typed: "git", url: url("https://github.com/luna"), useCount: 2.71),
            AdaptiveEntry(typed: "gitlab", url: url("https://gitlab.com/"), useCount: 5.20),
            AdaptiveEntry(typed: "news", url: url("https://news.example/"), useCount: 9.0)
        ]
        sources.history = [
            HistoryHit(url: url("https://gitbig.example/"), title: "GitBig", score: 9999),
            HistoryHit(url: url("https://git-scm.com/"), title: "Git", score: 340),
            HistoryHit(url: url("https://gitbook.example/"), title: "GitBook", score: 120)
        ]
        return (sources, githubTab)
    }

    // MARK: - §9.3 the merge

    /// The whole order, by hand:
    ///
    ///  1 gitlab.com   adaptive, useCount 5.20 — highest in the top tier
    ///  2 Luna         adaptive, useCount 2.71 — deduped onto the open GitHub tab
    ///  3 Git          open tab (git-scm.com); its 340-point history row deduped away
    ///  4 GitBig       history, 9999
    ///  5 GitBook      history, 120
    ///  6 Gitea        archive
    ///  7 git          search — the floor, always last
    ///
    /// "example.com" is absent because it does not match, and neither app command
    /// contains "git".
    func testMergesEverySourceIntoOneHandComputedOrder() {
        let results = CommandBarRanking.merge(query: "git", sources: fixture().sources, limit: 8)

        XCTAssertEqual(
            results.map(\.title),
            ["gitlab.com", "Luna", "Git", "GitBig", "GitBook", "Gitea", "git"]
        )
        XCTAssertEqual(
            results.map(\.source),
            [.adaptive, .adaptive, .openTab, .history, .history, .archive, .search]
        )
    }

    /// §9.3's headline rule: "adaptive matches rank above all frecency results."
    /// `GitBig` scores 9999 against an adaptive entry used 2.71 times, and still
    /// loses — the two numbers are different units and are never compared.
    func testAdaptiveOutranksEveryFrecencyResultRegardlessOfScore() {
        let results = CommandBarRanking.merge(query: "git", sources: fixture().sources, limit: 8)

        let lastAdaptive = results.lastIndex { $0.source == .adaptive }
        let firstHistory = results.firstIndex { $0.source == .history }
        XCTAssertEqual(lastAdaptive, 1)
        XCTAssertEqual(firstHistory, 3)
        XCTAssertEqual(results[1].score, 2.71, accuracy: 0.0001)
        XCTAssertEqual(results[3].score, 9999, accuracy: 0.0001)
    }

    /// Within the adaptive tier, `useCount` orders and nothing else does.
    func testAdaptiveTierIsOrderedByUseCount() {
        let results = CommandBarRanking.merge(query: "git", sources: fixture().sources, limit: 8)

        XCTAssertEqual(results[0].score, 5.20, accuracy: 0.0001)
        XCTAssertGreaterThan(results[0].score, results[1].score)
    }

    /// §9.2's dedupe, and the part of it that matters: the winning row keeps its
    /// rank but inherits the open tab's action, so a page that is both the
    /// adaptive favourite and already open switches to the live tab instead of
    /// loading a second copy of it (§19.4).
    func testDedupeKeepsTheBestRankButAdoptsTheOpenTabAction() {
        let (sources, githubTab) = fixture()
        let results = CommandBarRanking.merge(query: "git", sources: sources, limit: 8)

        XCTAssertEqual(results.filter { $0.title == "Luna" }.count, 1)
        XCTAssertEqual(results[1].source, .adaptive)
        XCTAssertEqual(results[1].action, .activateTab(githubTab.id))
        // §9.2's Space badge comes with it.
        XCTAssertEqual(results[1].badge?.name, "Work")
    }

    /// The same rule the other way: a history hit for a page that is already open
    /// disappears rather than appearing twice. `git-scm.com` is in both.
    func testDedupeCollapsesAHistoryHitOntoItsOpenTab() {
        let results = CommandBarRanking.merge(query: "git", sources: fixture().sources, limit: 8)

        XCTAssertEqual(results.filter { $0.title == "Git" }.count, 1)
        XCTAssertEqual(results[2].source, .openTab)
    }

    /// §9.3 skips adaptive on an empty query on purpose: every remembered string
    /// starts with "", so `⌘T`'s opening list would otherwise be the whole table.
    func testEmptyQueryShowsNoAdaptiveRowsAndNoSearchRow() {
        let results = CommandBarRanking.merge(query: "", sources: fixture().sources, limit: 8)

        XCTAssertFalse(results.contains { $0.source == .adaptive })
        XCTAssertFalse(results.contains { $0.source == .search })
        XCTAssertFalse(results.contains { $0.source == .command })
    }

    func testAppCommandsAppearWhenTheyMatch() {
        let results = CommandBarRanking.merge(query: "space", sources: fixture().sources, limit: 8)

        XCTAssertEqual(results.first { $0.source == .command }?.action, .command(.newSpace))
    }

    // MARK: - §9.3 the adaptive update

    /// `use_count = use_count * 0.9 + 1`, four steps by hand from nothing:
    /// 0 → 1 → 1.9 → 2.71 → 3.439.
    func testAdaptiveUpdateFollowsTheStatedRecurrence() {
        var count = 0.0
        var seen: [Double] = []
        for _ in 0..<4 {
            count = CommandBarRanking.bumped(count)
            seen.append(count)
        }
        for (produced, expected) in zip(seen, [1.0, 1.9, 2.71, 3.439]) {
            XCTAssertEqual(produced, expected, accuracy: 0.000_001)
        }
    }

    /// §9.3's "asymptote 10". It is the recurrence's fixed point — `x = 0.9x + 1`
    /// solves to exactly 10 — not a clamp bolted on afterwards, so the value
    /// approaches 10 from below, never reaches it in finite steps, and never
    /// passes it. A `min(_, 10)` in the implementation would make this test pass
    /// for the wrong reason, which is why the strict inequality is here.
    /// 200 steps, not more, for a floating-point reason worth stating: the gap to
    /// 10 shrinks by 0.9× per step, so somewhere past step ~348 it falls below a
    /// `Double`'s resolution at 10 and the value becomes exactly 10. At 200 the
    /// gap is still ≈7 × 10⁻⁹ — far inside the tolerance below, and far outside
    /// the epsilon that would make the strict inequalities spuriously fail.
    func testAdaptiveUpdateConvergesOnTenWithoutEverReachingIt() {
        var count = 0.0
        for _ in 0..<200 {
            let next = CommandBarRanking.bumped(count)
            XCTAssertGreaterThan(next, count)
            XCTAssertLessThan(next, 10)
            count = next
        }
        XCTAssertEqual(count, 10, accuracy: 0.000_001)
        // Ten is the fixed point: once there, the rule is a no-op.
        XCTAssertEqual(CommandBarRanking.bumped(10), 10, accuracy: 0.000_000_1)
    }

    /// The update has to change the order, or it is arithmetic nobody sees.
    /// GitHub starts behind GitLab, 2.71 against 5.20, and climbs
    /// 2.71 → 3.439 → 4.0951 → 4.68559 → 5.217031. Three uses leave it behind;
    /// the fourth puts it in front. Asserted at exactly that boundary, so a change
    /// to the rule cannot slip past by still being roughly right.
    func testUsingAResultPromotesItAboveARivalOnceTheCountOvertakesIt() {
        var (sources, _) = fixture()
        let github = 0
        func bump(times: Int) {
            for _ in 0..<times {
                sources.adaptive[github].useCount = CommandBarRanking.bumped(sources.adaptive[github].useCount)
            }
        }
        func topTwo() -> [String] {
            Array(CommandBarRanking.merge(query: "git", sources: sources, limit: 8).map(\.title).prefix(2))
        }

        bump(times: 3)
        XCTAssertEqual(sources.adaptive[github].useCount, 4.68559, accuracy: 0.000_001)
        XCTAssertEqual(topTwo(), ["gitlab.com", "Luna"])

        bump(times: 1)
        XCTAssertEqual(sources.adaptive[github].useCount, 5.217031, accuracy: 0.000_001)
        XCTAssertEqual(topTwo(), ["Luna", "gitlab.com"])
    }

    // MARK: - §9.7 no reordering under the cursor

    /// Late results may add rows; they may not move one. Here the incoming list
    /// puts a brand-new row first and reverses the two that are already showing,
    /// and the result keeps the on-screen pair exactly where the user left them.
    func testLateResultsAreAppendedAndNeverReordered() {
        let results = CommandBarRanking.merge(query: "git", sources: fixture().sources, limit: 8)
        let onScreen = Array(results.prefix(2))
        let incoming = [results[3]] + Array(onScreen.reversed())

        let merged = CommandBarRanking.appendingWithoutReordering(onScreen: onScreen, incoming: incoming)

        XCTAssertEqual(merged.map(\.title), ["gitlab.com", "Luna", "GitBig"])
    }

    // MARK: - §9.4 inline autofill

    func testAutofillsTheTopURLKeepingTheCasingTheUserTyped() {
        let results = CommandBarRanking.merge(query: "git", sources: fixture().sources, limit: 8)

        XCTAssertEqual(CommandBarRanking.autofill(query: "git", results: results), "gitlab.com")
        XCTAssertEqual(CommandBarRanking.autofill(query: "GIT", results: results), "GITlab.com")
    }

    /// Nothing to complete is not the same as completing with nothing: a query
    /// that is not a prefix of the top row, or that already is it, autofills
    /// nothing rather than replacing what the user typed.
    func testDoesNotAutofillWhenTheTopResultIsNotACompletion() {
        let results = CommandBarRanking.merge(query: "git", sources: fixture().sources, limit: 8)

        XCTAssertNil(CommandBarRanking.autofill(query: "lab", results: results))
        XCTAssertNil(CommandBarRanking.autofill(query: "gitlab.com", results: results))
        XCTAssertNil(CommandBarRanking.autofill(query: "", results: results))
        XCTAssertNil(CommandBarRanking.autofill(query: "git ", results: results))
        XCTAssertNil(CommandBarRanking.autofill(query: "git", results: []))
    }

    // MARK: - §9.7 the budget

    /// §9.7: "results must render within one frame (16 ms) of keystroke for local
    /// sources." `merge` is the whole of that path — everything else on the
    /// keystroke is AppKit laying out eight rows — so this is the number that has
    /// to hold. Measured against a deliberately unkind snapshot: 400 open tabs and
    /// the 24 history rows the store is asked for.
    ///
    /// The assertion is loose on purpose (a third of the frame, on a CI machine
    /// that may be sharing a core). It is here to catch an accidental O(n²) or a
    /// database call sneaking onto the synchronous path, not to benchmark.
    func testLocalMergeStaysWellInsideOneFrame() {
        var sources = fixture().sources
        sources.tabs = (0..<400).map { tab("https://site\($0).example/", title: "Site \($0)", minutesAgo: Double($0)) }

        let started = ContinuousClock.now
        for _ in 0..<20 {
            _ = CommandBarRanking.merge(query: "site1", sources: sources, limit: 8)
        }
        let perKeystroke = (ContinuousClock.now - started) / 20

        XCTAssertLessThan(perKeystroke, .milliseconds(5), "local merge must fit in one 16 ms frame (§9.7)")
    }
}
