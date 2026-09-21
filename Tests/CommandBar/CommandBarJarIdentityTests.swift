//
//  CommandBarJarIdentityTests.swift
//  LunaTests
//
//  Goal 16 of the Spaces wave: §9 / D-S8, "the identity behind a row's cookies
//  must appear on every surface where tabs from different jars can meet".
//
//  The report this exists for is zen#14371 — two identical "Google Gemini —
//  Switch to tab" rows, two accounts, no way to tell them apart, and picking
//  wrong teleports you into the other Space. Luna's bar had the same shape of
//  bug from the other direction: the two rows deduped into one, and the
//  surviving row silently adopted whichever tab the loop reached last.
//
//  The jar was a Profile until §9's `v7` and is a Space now, which is what
//  three of these tests used to be about: naming the Profile on the badge,
//  merging two Spaces that shared one, and degrading when the Profile's name
//  was unknown. The badge names the Space, the Space is the jar, and there is
//  nothing left to qualify.
//
//  Deliberately not `@MainActor`. `CommandBarRanking` is non-isolated so an
//  order can be computed without a window, and §9.7's budget depends on `merge`
//  staying a pure function on the keystroke path. A test needing a main actor
//  would be the first sign that stopped being true.
//

import BrowserKit
import XCTest
@testable import Luna

final class CommandBarJarIdentityTests: XCTestCase {

    private func url(_ text: String) -> URL { URL(string: text)! }

    private func space(_ name: String) -> Space {
        Space(name: name, symbolName: "hammer", gradient: .defaultSpace)
    }

    private func tab(_ address: String, title: String, in space: Space, minutesAgo: Double) -> Tab {
        Tab(
            spaceID: space.id,
            url: url(address),
            title: title,
            lastActiveAt: Date(timeIntervalSinceReferenceDate: 100_000 - minutesAgo * 60)
        )
    }

    /// One page open twice, in two Spaces. Same title, same URL, different
    /// cookie jars — which is the case the badge has to survive.
    private func twoJars() -> CommandBarSources {
        let workSpace = space("Studio")
        let personalSpace = space("Home")
        var sources = CommandBarSources()
        sources.spaces = [workSpace.id: workSpace, personalSpace.id: personalSpace]
        sources.tabs = [
            tab("https://gemini.google.com/app", title: "Gemini", in: workSpace, minutesAgo: 1),
            tab("https://gemini.google.com/app", title: "Gemini", in: personalSpace, minutesAgo: 5)
        ]
        return sources
    }

    // MARK: - Goal 16's proof

    /// The proof. Two same-URL tabs in different jars produce two rows, and the
    /// rows are distinguishable: different identities, different labels, and —
    /// the part that actually matters — different actions, so choosing one
    /// cannot land you in the other Space.
    func testSameURLInTwoJarsProducesTwoDistinguishableRows() {
        let sources = twoJars()
        let results = CommandBarRanking.merge(query: "gemini", sources: sources, limit: 8)
        let tabs = results.filter { $0.source == .openTab }

        XCTAssertEqual(tabs.count, 2, "One row for two cookie jars is zen#14371.")
        XCTAssertEqual(Set(tabs.map(\.id)).count, 2, "§9.7 carries selection by id; two rows need two ids.")
        XCTAssertEqual(Set(tabs.map(\.action)).count, 2, "Each row must activate its own tab.")
        XCTAssertEqual(Set(tabs.compactMap { $0.badge?.name }), ["Studio", "Home"])
    }

    /// The badge names the Space, which is the jar — a colour says which Space,
    /// never whose cookies, and §21.2 needs the name anyway.
    ///
    /// It used to qualify with the Profile's name whenever the tabs on offer
    /// spanned more than one ("Studio · Work"), and drop the qualifier when
    /// they did not, because "Work · Work" on every row teaches people to stop
    /// reading badges. One name says both things now.
    func testTheBadgeNamesTheSpace() {
        let research = space("Research")
        var sources = twoJars()
        sources.spaces[research.id] = research
        sources.tabs.append(tab("https://gemini.google.com/settings", title: "Gemini", in: research, minutesAgo: 9))

        let labels = Set(
            CommandBarRanking.merge(query: "gemini", sources: sources, limit: 8)
                .filter { $0.source == .openTab }
                .compactMap { $0.badge?.name }
        )
        XCTAssertEqual(labels, ["Studio", "Home", "Research"])
    }

    /// The dedupe still does its job — this is not "never merge anything". One
    /// page open once is one row however many Spaces exist beside it.
    func testOnePageOpenOnceIsStillOneRow() {
        let first = space("Work")
        let second = space("Research")
        var sources = CommandBarSources()
        sources.spaces = [first.id: first, second.id: second]
        sources.tabs = [tab("https://gemini.google.com/app", title: "Gemini", in: first, minutesAgo: 1)]

        let results = CommandBarRanking.merge(query: "gemini", sources: sources, limit: 8)
        XCTAssertEqual(results.filter { $0.source == .openTab }.count, 1)
    }

    /// A history hit for a page that is open in one jar still collapses onto
    /// the live tab (§19.4) — the pre-existing behaviour, unchanged.
    func testHistoryStillCollapsesOntoTheOpenTab() {
        let only = space("Work")
        var sources = CommandBarSources()
        sources.spaces = [only.id: only]
        sources.tabs = [tab("https://github.com/luna", title: "Luna", in: only, minutesAgo: 1)]
        sources.history = [HistoryHit(url: url("https://github.com/luna"), title: "Luna", score: 500)]

        let results = CommandBarRanking.merge(query: "luna", sources: sources, limit: 8)
        let matching = results.filter { $0.url == self.url("https://github.com/luna") }
        XCTAssertEqual(matching.count, 1, "One page, one cookie jar, one row.")
        // §9.3's tiers put an open tab above history outright, so the tab row is
        // the one that survives and the history hit is the one that vanishes.
        XCTAssertEqual(matching.first?.source, .openTab)
        if case .activateTab = matching.first?.action {} else {
            XCTFail("The surviving row must switch to the live tab (§19.4).")
        }
    }

    /// …and when the page is open in two jars, the history row hands its place
    /// to the first and the second gets a row of its own, so both tabs stay
    /// reachable. Three ways to the same page would be two too many.
    func testAHistoryHitDoesNotHideTheSecondJarsTab() {
        var sources = twoJars()
        sources.history = [HistoryHit(url: url("https://gemini.google.com/app"), title: "Gemini", score: 500)]

        let results = CommandBarRanking.merge(query: "gemini", sources: sources, limit: 8)
        let reachable = results.compactMap { result -> UUID? in
            if case let .activateTab(id) = result.action { return id }
            return nil
        }
        XCTAssertEqual(Set(reachable).count, 2, "Both open tabs must be reachable.")
        XCTAssertEqual(results.count, 3, "Two tab rows plus the search floor — no third copy of the page.")
    }

    // MARK: - §9.7's budget

    /// The Profile-aware dedupe must not cost the keystroke path anything. 400
    /// tabs spread across two Profiles, which is the shape that exercises every
    /// new branch, against §9.7's 100 ms budget.
    ///
    /// The bound is one frame rather than the time the merge actually takes.
    /// Set to 5 ms it failed on a CI runner at 5.03: a bound a hair above the
    /// measurement tests the machine the suite is running on, and `BudgetTests`
    /// is where wall-clock assertions of that kind belong. What is worth
    /// catching here is an accidental O(n²), which misses a frame by orders of
    /// magnitude rather than by half a percent.
    func testJarAwareDedupeStaysInsideTheKeystrokeBudget() {
        let workSpace = space("Work")
        let personalSpace = space("Personal")
        var sources = CommandBarSources()
        sources.spaces = [workSpace.id: workSpace, personalSpace.id: personalSpace]
        sources.tabs = (0 ..< 400).map { index in
            tab(
                "https://site\(index / 2).example/",
                title: "Site \(index / 2)",
                in: index.isMultiple(of: 2) ? workSpace : personalSpace,
                minutesAgo: Double(index)
            )
        }

        let started = ContinuousClock.now
        for _ in 0 ..< 20 {
            _ = CommandBarRanking.merge(query: "site1", sources: sources, limit: 8)
        }
        let perKeystroke = (ContinuousClock.now - started) / 20

        XCTAssertLessThan(perKeystroke, .milliseconds(16), "§9.7: local merge fits in one 16 ms frame")
    }
}
