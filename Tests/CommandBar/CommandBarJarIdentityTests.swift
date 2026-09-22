//
//  CommandBarJarIdentityTests.swift
//  LunaTests
//
//  §9 / D-S8: "the identity behind a row's cookies must appear on every surface
//  where tabs from different jars can meet". The answer here is that they do not
//  meet. The bar is opened from inside a Space and offered that Space's things
//  and nothing else, so there is no second jar in the list to tell apart.
//
//  The report this exists for is zen#14371 — two identical "Google Gemini —
//  Switch to tab" rows, two accounts, no way to tell them apart, and picking
//  wrong teleports you into the other Space. Luna answered it twice. First with
//  a badge, a row per (URL, jar) and a Space name on each; then, once `v7` made
//  the Space the cookie jar and `v8` gave it its own history, by not offering
//  the other Space at all. A page you can only reach in Personal is not
//  something Work should be suggesting, however well it is labelled.
//
//  So the boundary is upstream of the ranking now, and this file tests it at the
//  two places it is drawn: `BrowserSession`, which decides what the bar is
//  handed, and `CommandBarRanking`, which must still fold two ways to the same
//  page inside one Space into one row.
//
//  The store's half — a visit in one Space being invisible from the other — is
//  `StoreMigrationTests.aVisitInOneSpaceIsInvisibleFromTheOther`.
//

import BrowserKit
import XCTest
@testable import Luna

@MainActor
final class CommandBarJarIdentityTests: XCTestCase {

    private let directory = URL.temporaryDirectory.appending(path: "luna-tests-\(UUID().uuidString)")

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeSession() async throws -> BrowserSession {
        try await BrowserSession.restored(store: BrowserStore(path: directory.appending(path: "luna.sqlite")))
    }

    private func url(_ text: String) -> URL { URL(string: text)! }

    // MARK: - What the bar is handed

    /// The proof. A tab open in the Space you are not in is not on offer, so no
    /// row in the list can activate it.
    func testTheBarIsOfferedOnlyTheSpaceItWasOpenedIn() async throws {
        let session = try await makeSession()
        let personal = session.activeSpaceID
        let mine = session.newTab(url: url("https://gemini.google.com/app"))

        let work = try await session.createSpace(name: "Work")
        session.switchSpace(work.id)
        let theirs = session.newTab(url: url("https://gemini.google.com/app"))

        let offered = session.tabsInActiveSpace(includeArchived: true).map(\.id)
        XCTAssertTrue(offered.contains(theirs), "the Space you are in is on offer")
        XCTAssertFalse(offered.contains(mine), "the Space you are not in is not")

        session.switchSpace(personal)
        XCTAssertEqual(session.tabsInActiveSpace(includeArchived: true).map(\.id), [mine])
    }

    /// §6.3's archive is a Space's archive too. What you closed in Personal is
    /// not in Work's list, in the bar or in §6.4's panel.
    func testTheArchiveOnOfferIsTheSpacesOwn() async throws {
        let session = try await makeSession()
        let closedInPersonal = session.newTab(url: url("https://mail.example/inbox"))
        session.closeTab(closedInPersonal)

        let work = try await session.createSpace(name: "Work")
        session.switchSpace(work.id)

        XCTAssertTrue(session.archivedInActiveSpace.isEmpty)
        XCTAssertFalse(session.tabsInActiveSpace(includeArchived: true).contains { $0.id == closedInPersonal })
        XCTAssertTrue(
            session.archived.contains { $0.id == closedInPersonal },
            "it is still archived — the app keeps every Space's, the bar offers one"
        )
    }

    /// And `⌘⇧T` reopens the last tab closed *here*, not the last one closed
    /// anywhere: the keystroke means "undo the close I just did".
    func testReopeningTheLastClosedTabStaysInTheSpace() async throws {
        let session = try await makeSession()
        let closedInPersonal = session.newTab(url: url("https://mail.example/inbox"))
        session.closeTab(closedInPersonal)

        let work = try await session.createSpace(name: "Work")
        session.switchSpace(work.id)
        session.reopenLastArchived()

        XCTAssertTrue(session.tabs.isEmpty, "there was nothing closed in this Space to reopen")
        XCTAssertTrue(session.archived.contains { $0.id == closedInPersonal })
    }

    // MARK: - The dedupe that is left

    private func tab(_ address: String, title: String, in spaceID: UUID, minutesAgo: Double) -> Tab {
        Tab(
            spaceID: spaceID,
            url: url(address),
            title: title,
            lastActiveAt: Date(timeIntervalSinceReferenceDate: 100_000 - minutesAgo * 60)
        )
    }

    /// One page open twice in one Space is one row. Both tabs are in the same
    /// cookie jar, so they are the same page signed in as the same person and a
    /// second row would be a choice with no difference behind it.
    func testOnePageOpenTwiceInOneSpaceIsOneRow() {
        let space = UUID()
        var sources = CommandBarSources()
        sources.tabs = [
            tab("https://gemini.google.com/app", title: "Gemini", in: space, minutesAgo: 1),
            tab("https://gemini.google.com/app", title: "Gemini", in: space, minutesAgo: 5)
        ]

        let results = CommandBarRanking.merge(query: "gemini", sources: sources, limit: 8)
        XCTAssertEqual(results.filter { $0.source == .openTab }.count, 1)
    }

    /// A history hit for a page that is open collapses onto the live tab
    /// (§19.4) — the pre-existing behaviour, unchanged.
    func testHistoryStillCollapsesOntoTheOpenTab() {
        let space = UUID()
        var sources = CommandBarSources()
        sources.tabs = [tab("https://github.com/luna", title: "Luna", in: space, minutesAgo: 1)]
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

    // MARK: - §9.7's budget

    /// The dedupe must not cost the keystroke path anything. 400 tabs, half of
    /// them pairs on the same URL, against §9.7's one-frame budget.
    ///
    /// The bound is one frame rather than the time the merge actually takes.
    /// Set to 5 ms it failed on a CI runner at 5.03: a bound a hair above the
    /// measurement tests the machine the suite is running on, and `BudgetTests`
    /// is where wall-clock assertions of that kind belong. What is worth
    /// catching here is an accidental O(n²), which misses a frame by orders of
    /// magnitude rather than by half a percent.
    func testDedupeStaysInsideTheKeystrokeBudget() {
        let space = UUID()
        var sources = CommandBarSources()
        sources.tabs = (0 ..< 400).map { index in
            tab("https://site\(index / 2).example/", title: "Site \(index / 2)", in: space, minutesAgo: Double(index))
        }

        let started = ContinuousClock.now
        for _ in 0 ..< 20 {
            _ = CommandBarRanking.merge(query: "site1", sources: sources, limit: 8)
        }
        let perKeystroke = (ContinuousClock.now - started) / 20

        XCTAssertLessThan(perKeystroke, .milliseconds(16), "§9.7: local merge fits in one 16 ms frame")
    }
}
