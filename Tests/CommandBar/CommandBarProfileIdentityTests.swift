//
//  CommandBarProfileIdentityTests.swift
//  LunaTests
//
//  Goal 16 of the Spaces wave: §9 / D-S8, "the Profile identity must appear on
//  every surface where tabs from different Profiles can meet".
//
//  The report this exists for is zen#14371 — two identical "Google Gemini —
//  Switch to tab" rows, two Profiles, two accounts, no way to tell them apart,
//  and picking wrong teleports you into the other Space. Luna's bar had the
//  same shape of bug from the other direction: the two rows deduped into one,
//  and the surviving row silently adopted whichever tab the loop reached last.
//
//  This file is deliberately not `@MainActor`. `CommandBarRanking` is
//  non-isolated so an order can be computed without a window, and §9.7's budget
//  depends on `merge` staying a pure function on the keystroke path. A test that
//  needed a main actor to run would be the first sign that stopped being true.
//

import BrowserKit
import XCTest
@testable import Luna

final class CommandBarProfileIdentityTests: XCTestCase {
    private let work = Profile(name: "Work")
    private let personal = Profile(name: "Personal")

    private func url(_ text: String) -> URL { URL(string: text)! }

    private func space(_ name: String, profile: Profile) -> Space {
        Space(name: name, symbolName: "hammer", gradient: .defaultSpace, profileID: profile.id)
    }

    private func tab(_ address: String, title: String, in space: Space, minutesAgo: Double) -> Tab {
        Tab(
            spaceID: space.id,
            url: url(address),
            title: title,
            lastActiveAt: Date(timeIntervalSinceReferenceDate: 100_000 - minutesAgo * 60)
        )
    }

    /// One page open twice: once in a Space on the Work profile, once in a Space
    /// on the Personal profile. Same title, same URL, different cookie jars.
    private func twoProfiles(namingProfiles: Bool = true) -> CommandBarSources {
        // The Spaces are named for what they hold, the Profiles for whose login
        // they carry — which is the case the badge has to survive.
        let workSpace = space("Studio", profile: work)
        let personalSpace = space("Home", profile: personal)
        var sources = CommandBarSources()
        sources.spaces = [workSpace.id: workSpace, personalSpace.id: personalSpace]
        if namingProfiles { sources.profiles = [work.id: work, personal.id: personal] }
        sources.tabs = [
            tab("https://gemini.google.com/app", title: "Gemini", in: workSpace, minutesAgo: 1),
            tab("https://gemini.google.com/app", title: "Gemini", in: personalSpace, minutesAgo: 5)
        ]
        return sources
    }

    // MARK: - Goal 16's proof

    /// The proof. Two same-URL tabs in different Profiles produce two rows,
    /// and the rows are distinguishable: different identities, different labels,
    /// and — the part that actually matters — different actions, so choosing one
    /// cannot land you in the other Space.
    func testSameURLInTwoProfilesProducesTwoDistinguishableRows() {
        let sources = twoProfiles()
        let results = CommandBarRanking.merge(query: "gemini", sources: sources, limit: 8)
        let tabs = results.filter { $0.source == .openTab }

        XCTAssertEqual(tabs.count, 2, "One row for two Profiles is zen#14371.")
        XCTAssertEqual(Set(tabs.map(\.id)).count, 2, "§9.7 carries selection by id; two rows need two ids.")
        XCTAssertEqual(Set(tabs.map(\.action)).count, 2, "Each row must activate its own tab.")
        XCTAssertEqual(Set(tabs.compactMap { $0.badge?.name }), ["Studio · Work", "Home · Personal"])
    }

    /// The badge names the Profile, not only the Space — a Space colour says
    /// which Space, never whose cookies. Two Spaces on the Work profile and one
    /// on Personal, so every row has to say which jar it came out of.
    func testBadgeNamesTheProfileWhenProfilesDiffer() {
        let research = space("Research", profile: work)
        var sources = twoProfiles()
        sources.spaces[research.id] = research
        sources.tabs.append(tab("https://gemini.google.com/settings", title: "Gemini", in: research, minutesAgo: 9))

        let labels = Set(
            CommandBarRanking.merge(query: "gemini", sources: sources, limit: 8)
                .filter { $0.source == .openTab }
                .compactMap { $0.badge?.name }
        )
        XCTAssertEqual(labels, ["Studio · Work", "Home · Personal", "Research · Work"])
    }

    /// Two Spaces, one Profile: one cookie jar, so one row. The dedupe still
    /// does its job — this is not "never merge anything".
    func testSameURLInTwoSpacesOnOneProfileStaysOneRow() {
        let first = space("Work", profile: work)
        let second = space("Research", profile: work)
        var sources = CommandBarSources()
        sources.spaces = [first.id: first, second.id: second]
        sources.profiles = [work.id: work]
        sources.tabs = [
            tab("https://gemini.google.com/app", title: "Gemini", in: first, minutesAgo: 1),
            tab("https://gemini.google.com/app", title: "Gemini", in: second, minutesAgo: 5)
        ]

        let results = CommandBarRanking.merge(query: "gemini", sources: sources, limit: 8)
        XCTAssertEqual(results.filter { $0.source == .openTab }.count, 1)
    }

    /// One Profile in the window means the badge has nothing to disambiguate, so
    /// it says the Space and stops. "Work · Work" on every row teaches people to
    /// stop reading badges.
    func testBadgeStaysPlainWhenThereIsOnlyOneProfile() {
        let only = space("Work", profile: work)
        var sources = CommandBarSources()
        sources.spaces = [only.id: only]
        sources.profiles = [work.id: work]
        sources.tabs = [tab("https://github.com/luna", title: "Luna", in: only, minutesAgo: 1)]

        let row = CommandBarRanking.merge(query: "luna", sources: sources, limit: 8).first
        XCTAssertEqual(row?.badge?.name, "Work")
    }

    /// Without the Profile table the rows must still stay apart — separation is
    /// derived from `Space.profileID` and needs no name. Only the label degrades.
    func testRowsStaySeparateEvenWhenProfileNamesAreUnknown() {
        let results = CommandBarRanking.merge(
            query: "gemini", sources: twoProfiles(namingProfiles: false), limit: 8
        )
        let tabs = results.filter { $0.source == .openTab }

        XCTAssertEqual(tabs.count, 2)
        XCTAssertEqual(Set(tabs.compactMap { $0.badge?.name }), ["Studio", "Home"])
    }

    /// A history hit for a page that is open in one Profile still collapses onto
    /// the live tab (§19.4) — the pre-existing behaviour, unchanged.
    func testHistoryStillCollapsesOntoTheOpenTab() {
        let only = space("Work", profile: work)
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

    /// …and when the page is open in two Profiles, the history row hands its
    /// place to the first and the second gets a row of its own, so both tabs stay
    /// reachable. Three ways to the same page would be two too many.
    func testAHistoryHitDoesNotHideTheSecondProfilesTab() {
        var sources = twoProfiles()
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
    /// new branch, against §9.7's 100 ms budget and the 9.3 ms median it has
    /// today. Loose on purpose — this catches an accidental O(n²), not a
    /// microsecond.
    func testProfileAwareDedupeStaysInsideTheKeystrokeBudget() {
        let workSpace = space("Work", profile: work)
        let personalSpace = space("Personal", profile: personal)
        var sources = CommandBarSources()
        sources.spaces = [workSpace.id: workSpace, personalSpace.id: personalSpace]
        sources.profiles = [work.id: work, personal.id: personal]
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

        XCTAssertLessThan(perKeystroke, .milliseconds(5), "§9.7: local merge fits in one 16 ms frame")
    }
}
