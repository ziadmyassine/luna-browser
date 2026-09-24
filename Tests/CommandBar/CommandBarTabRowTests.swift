//
//  CommandBarTabRowTests.swift
//  LunaTests
//
//  §9.2's two answers about a tab, and the line between them.
//
//  · An address you typed is an instruction: it goes to the page, in a new tab,
//    even when a tab is already on it.
//  · A name is a search of what you have: it finds the tab and switches to it,
//    whether or not that tab has a page loaded right now.
//
//  Both were wrong in the shipped app at the same time and for opposite
//  reasons — the dedupe handed a typed address the open tab's action, and
//  `tabRows` filtered out every tab whose page was closed — so they are
//  asserted together. Split from `CommandBarRankingTests` for that file's
//  type-body limit; the fixtures are deliberately its own rather than shared,
//  because none of these tests wants the ordering fixture.
//

import BrowserKit
import XCTest
@testable import Luna

final class CommandBarTabRowTests: XCTestCase {

    private let space = UUID()

    private func url(_ text: String) -> URL { URL(string: text)! }

    private func tab(
        _ address: String,
        title: String,
        minutesAgo: Double,
        archived: Bool = false
    ) -> Tab {
        let when = Date(timeIntervalSinceReferenceDate: 100_000 - minutesAgo * 60)
        return Tab(
            spaceID: space,
            url: url(address),
            title: title,
            lastActiveAt: when,
            archivedAt: archived ? when : nil
        )
    }

    // MARK: - An address is an instruction (§9.3)

    /// Typing the address of a page you already have open goes to the page.
    ///
    /// `directURL` outranks `openTab` by tier, so the top row was always the
    /// typed address — but the dedupe then handed it the tab's own action, and
    /// the one string that unambiguously means "go here" was the one that would
    /// not. It is a new tab, in `⌘T`'s mode, and a load in the pill's.
    func testTypingTheAddressOfAnOpenTabOpensItRatherThanSwitchingToIt() {
        var sources = CommandBarSources()
        sources.tabs = [tab("https://google.com/", title: "Google", minutesAgo: 1)]

        let results = CommandBarRanking.merge(query: "google.com", sources: sources, limit: 8)
        let top = try? XCTUnwrap(results.first)
        XCTAssertEqual(top?.source, .directURL)
        guard case .open = top?.action else {
            return XCTFail("A typed address must go to the page, not to a tab that happens to be on it.")
        }
        XCTAssertFalse(
            results.contains { if case .activateTab = $0.action { true } else { false } },
            "Nothing in an address's list switches tabs — the address is the instruction."
        )
    }

    /// And its name still finds it. The tab's title is not an address, so it
    /// answers the way everything that is not an address answers: with what you
    /// already have open.
    func testTypingTheNameOfThatSameTabSwitchesToIt() {
        var sources = CommandBarSources()
        sources.tabs = [tab("https://google.com/", title: "Google", minutesAgo: 1)]

        let results = CommandBarRanking.merge(query: "google", sources: sources, limit: 8)
        let row = try? XCTUnwrap(results.first { $0.source == .openTab })
        XCTAssertEqual(row?.title, "Google")
        XCTAssertEqual(row?.subtitle, CommandBarRanking.switches, "the row has to say what it will do")
        guard case .activateTab = row?.action else {
            return XCTFail("A tab found by name is switched to (§19.4).")
        }
    }

    /// The row said the tab's address, which every other row in the list also
    /// says — so the one row that was going to do something entirely different
    /// looked exactly like the ones that load a page. Reported as the bar not
    /// showing `Switch to tab` when you type a tab's name: it was showing the
    /// row and saying nothing about it.
    func testEveryTabRowSaysWhetherItSwitchesOrReopens() {
        var sources = CommandBarSources()
        sources.tabs = [
            tab("https://google.com/", title: "Google", minutesAgo: 1),
            tab("https://google.co.uk/", title: "Google UK", minutesAgo: 90, archived: true)
        ]

        let results = CommandBarRanking.merge(query: "google", sources: sources, limit: 8)
        XCTAssertEqual(results.first { $0.source == .openTab }?.subtitle, "Switch to tab")
        XCTAssertEqual(results.first { $0.source == .archive }?.subtitle, "Reopen tab")
    }

    /// A cold tab is still a tab. §19.2 drops the page of everything but the
    /// last few and keeps every row, so "switch" has to mean the row rather
    /// than the process — otherwise the bar would only ever offer the three or
    /// four tabs that happen to be loaded.
    func testATabWithNoPageLoadedIsStillOfferedAsASwitch() {
        var sources = CommandBarSources()
        // No `TabController` anywhere in this test: nothing here has a page.
        sources.tabs = [tab("https://news.example/", title: "The News", minutesAgo: 600)]

        let results = CommandBarRanking.merge(query: "news", sources: sources, limit: 8)
        let row = try? XCTUnwrap(results.first { $0.source == .openTab })
        XCTAssertEqual(row?.subtitle, CommandBarRanking.switches)
        guard case .activateTab = row?.action else {
            return XCTFail("A cold tab is switched to, not loaded a second time.")
        }
    }

    /// And the row that borrows a tab's action borrows the line that says so.
    /// The adaptive row is the one the tab dedupes onto, so it is that row's.
    func testAnAdaptiveRowThatSwitchesTabsSaysSo() {
        var sources = CommandBarSources()
        sources.tabs = [tab("https://github.com/luna", title: "Luna", minutesAgo: 1)]
        sources.adaptive = [AdaptiveEntry(typed: "lun", url: url("https://github.com/luna"), useCount: 9)]

        let results = CommandBarRanking.merge(query: "lun", sources: sources, limit: 8)
        let row = try? XCTUnwrap(results.first { $0.source == .adaptive })
        XCTAssertEqual(row?.subtitle, CommandBarRanking.switches)
    }

    /// The adaptive tier is not a way round it. A remembered `(typed → URL)`
    /// pair ranks above everything, and it used to adopt the open tab's action
    /// on the way past.
    func testAnAdaptiveMatchOnAnAddressStillOpensThePage() {
        var sources = CommandBarSources()
        sources.tabs = [tab("https://google.com/", title: "Google", minutesAgo: 1)]
        sources.adaptive = [AdaptiveEntry(typed: "google.com", url: url("https://google.com/"), useCount: 9)]

        let results = CommandBarRanking.merge(query: "google.com", sources: sources, limit: 8)
        XCTAssertFalse(
            results.contains { if case .activateTab = $0.action { true } else { false } },
            "A lesson learned about an address must not turn the address into a tab switch."
        )
    }

    // MARK: - §3.4b closed rows

    /// A §3.4b row whose page is not loaded is still a tab, and the bar offers
    /// it as one.
    ///
    /// This used to assert the opposite: a dormant row was filtered out, on the
    /// reasoning that choosing it put the site back into the folder it had been
    /// closed in. What that cost was the search a user is most likely to run —
    /// a kept tab is dormant almost all of the time, which is what §3.4b's
    /// first press is for, so a pinned `Google` in a folder called Google
    /// answered to nothing and typing its name returned nothing but archived
    /// searches that mentioned it. Reported from the running app.
    ///
    /// Putting it back where it stands is what clicking the dimmed row in the
    /// column does too, so the bar and the column now agree.
    func testARowWhosePageIsClosedIsStillATabYouCanSwitchTo() {
        var sources = CommandBarSources()
        var kept = tab("https://git-scm.com/", title: "Git", minutesAgo: 5)
        kept.kind = .pinned
        kept.isDormant = true
        sources.tabs = [kept]
        sources.history = [HistoryHit(url: url("https://git-scm.com/"), title: "Git", score: 10)]

        let results = CommandBarRanking.merge(query: "git", sources: sources, limit: 8)
        let row = try? XCTUnwrap(results.first { $0.source == .openTab })
        XCTAssertEqual(row?.subtitle, CommandBarRanking.switches)
        guard case .activateTab = row?.action else {
            return XCTFail("A kept tab is reached by switching to it, not by loading a second copy.")
        }
    }

    /// And a history hit for a page that is only in the archive stays a history
    /// hit: it loads the page.
    ///
    /// Adoption is for open tabs alone. An archived one was adopted too, which
    /// turned every history hit for a page the user had ever closed into
    /// `Reopen tab` — in a Space with a long archive that was the whole list.
    func testAHistoryHitIsNotTurnedIntoAnArchiveReopen() {
        var sources = CommandBarSources()
        sources.tabs = [tab("https://git-scm.com/", title: "Git", minutesAgo: 90, archived: true)]
        sources.history = [HistoryHit(url: url("https://git-scm.com/"), title: "Git", score: 10)]

        let results = CommandBarRanking.merge(query: "git", sources: sources, limit: 8)
        let row = try? XCTUnwrap(results.first { $0.url == self.url("https://git-scm.com/") })
        XCTAssertEqual(row?.source, .history, "history outranks the archive and keeps its place")
        guard case .open = row?.action else {
            return XCTFail("A page found in history is loaded, not pulled back off §6.3's shelf.")
        }
    }
}
