//
//  CommandBarLeadTests.swift
//  LunaTests
//
//  The row that leads when what was typed is the start of a site the user has
//  been to (`CommandBarRanking+Lead`): it completes inline, Return opens it,
//  and the search row is second. Synthetic sites and tabs, each test the
//  shape of a miss `Tools/ranking-check.sh` found on a real history.
//

import BrowserKit
import XCTest
@testable import Luna

final class CommandBarLeadTests: XCTestCase {

    private let space = UUID()

    private func url(_ text: String) -> URL { URL(string: text)! }

    private func site(_ host: String, _ address: String? = nil, score: Double = 400) -> VisitedSite {
        VisitedSite(
            host: host,
            domain: PublicSuffix.siteKey(forHost: host),
            url: url(address ?? "https://\(host)/"),
            title: host,
            score: score
        )
    }

    private func tab(_ address: String, title: String, archived: Bool = false) -> Tab {
        let when = Date(timeIntervalSinceReferenceDate: 100_000)
        return Tab(spaceID: space, url: url(address), title: title, lastActiveAt: when, archivedAt: archived ? when : nil)
    }

    private func merge(_ query: String, _ sources: CommandBarSources) -> [CommandBarResult] {
        CommandBarRanking.merge(query: query, sources: sources, limit: 8)
    }

    // MARK: - A site leads

    /// Two letters of a site's address put the site first and complete it,
    /// ahead of a tab that holds the letters inside a word — `it` in `Edit` —
    /// which used to take the top row and leave nothing to complete.
    func testTheStartOfAVisitedSiteLeadsOverATabHoldingTheLetters() {
        var sources = CommandBarSources()
        sources.sites = [site("itslearning.com")]
        sources.tabs = [tab("https://notes.example/42", title: "Edit profile")]

        for query in ["it", "itslearning"] {
            let results = merge(query, sources)
            XCTAssertEqual(results.first?.url, url("https://itslearning.com/"), query)
            XCTAssertEqual(results.dropFirst().first?.source, .search, "the search is second for \(query)")
            XCTAssertEqual(CommandBarRanking.autofill(query: query, results: results), "itslearning.com")
        }
    }

    /// `gi` is GitHub, not a tab called `Digital…`. The tab is still offered,
    /// below the history: it holds the letters, but not at the start of a word.
    func testATabMatchedInsideAWordRanksBelowHistory() {
        var sources = CommandBarSources()
        sources.sites = [site("github.com")]
        sources.tabs = [tab("https://bank.example/", title: "Digital banking")]
        sources.history = [HistoryHit(url: url("https://gist.github.com/"), title: "Gists", score: 50)]

        let results = merge("gi", sources)

        XCTAssertEqual(results.map(\.source), [.history, .search, .history, .openTab])
        XCTAssertEqual(results.first?.url, url("https://github.com/"))
        XCTAssertEqual(results.last?.isLooseMatch, true)
        XCTAssertEqual(CommandBarRanking.autofill(query: "gi", results: results), "github.com")
    }

    /// A tab whose own name starts with the letters is not loose, and keeps its
    /// tier above history — under the site that leads.
    func testATabMatchedAtAWordStartKeepsItsTier() {
        var sources = CommandBarSources()
        sources.sites = [site("github.com")]
        sources.tabs = [tab("https://git-scm.com/", title: "Git")]
        sources.history = [HistoryHit(url: url("https://gist.github.com/"), title: "Gists", score: 50)]

        let results = merge("gi", sources)

        XCTAssertEqual(results.map(\.source), [.history, .search, .openTab, .history])
        XCTAssertEqual(results[2].isLooseMatch, false)
    }

    /// The best site leads: the list arrives best first, so the first match is it.
    func testTheBestOfSeveralSitesLeads() {
        var sources = CommandBarSources()
        sources.sites = [site("linkedin.com", score: 900), site("linuxcommand.org", score: 200)]

        XCTAssertEqual(merge("li", sources).first?.url, url("https://linkedin.com/"))
        XCTAssertEqual(merge("linu", sources).first?.url, url("https://linuxcommand.org/"))
    }

    /// A site's front page is what it opens, so the field completes to the
    /// host — and when the store had no front page, to the page it chose.
    func testTheFieldCompletesToTheSitesOwnPage() {
        var sources = CommandBarSources()
        sources.sites = [site("uow.edu.au", "https://www.uow.edu.au/study/")]

        XCTAssertEqual(CommandBarRanking.autofill(query: "uo", results: merge("uo", sources)), "uow.edu.au/study/")
    }

    // MARK: - The search keeps the top

    /// Words are a search, whatever site they begin.
    func testASearchLikeQueryKeepsTheSearchFirst() {
        var sources = CommandBarSources()
        sources.sites = [site("weather.com")]

        let results = merge("weather tomorrow", sources)

        XCTAssertEqual(results.first?.source, .search)
        XCTAssertNil(CommandBarRanking.autofill(query: "weather tomorrow", results: results))
    }

    /// One word that begins no visited site is a search too, even when a tab
    /// holds it somewhere.
    func testAWordThatStartsNoSiteIsSearchedFirst() {
        var sources = CommandBarSources()
        sources.sites = [site("github.com")]
        sources.tabs = [tab("https://notes.example/", title: "Credits")]

        XCTAssertEqual(merge("edi", sources).first?.source, .search)
    }

    /// A host typed out in full is an address, and its own row answers it.
    func testAHostTypedInFullIsLeftToItsAddress() {
        var sources = CommandBarSources()
        sources.sites = [site("github.com")]

        XCTAssertEqual(merge("github.com", sources).first?.source, .directURL)
    }

    // MARK: - The adaptive table

    /// A page learned for exactly these letters leads instead of the site's
    /// front page — and only for exactly them.
    func testALearnedPageLeadsOnlyForItsOwnLetters() {
        var sources = CommandBarSources()
        sources.sites = [site("github.com")]
        sources.adaptive = [AdaptiveEntry(typed: "gi", url: url("https://github.com/luna/browser"), useCount: 3)]

        let learned = merge("gi", sources)
        XCTAssertEqual(learned.first?.url, url("https://github.com/luna/browser"))
        XCTAssertEqual(learned.first?.source, .adaptive)
        XCTAssertEqual(CommandBarRanking.autofill(query: "gi", results: learned), "github.com/luna/browser")

        for query in ["g", "git"] {
            XCTAssertEqual(merge(query, sources).first?.url, url("https://github.com/"), query)
        }
    }

    /// A lesson learned on the way to a longer string does not take the lead:
    /// `git` → one repository used to win every `gi` the user typed.
    func testALessonForALongerStringDoesNotLead() {
        var sources = CommandBarSources()
        sources.sites = [site("github.com")]
        sources.adaptive = [AdaptiveEntry(typed: "git", url: url("https://gitstats.example/x"), useCount: 9)]

        let results = merge("gi", sources)

        XCTAssertEqual(results.first?.url, url("https://github.com/"))
        XCTAssertTrue(results.contains { $0.source == .adaptive }, "the lesson is still offered")
    }

    // MARK: - Tabs and other hosts

    /// The page the lead opens is already open: the lead switches to it, as
    /// Safari's top hit does, and the field still completes its address.
    func testTheLeadSwitchesToItsPageWhenThatPageIsOpen() {
        var sources = CommandBarSources()
        sources.sites = [site("github.com")]
        let open = tab("https://github.com/", title: "GitHub")
        sources.tabs = [open]

        let results = merge("gi", sources)

        XCTAssertEqual(results.first?.action, .activateTab(open.id))
        XCTAssertEqual(results.filter { $0.url == self.url("https://github.com/") }.count, 1)
        XCTAssertEqual(CommandBarRanking.autofill(query: "gi", results: results), "github.com")
    }

    /// The start of a registrable domain finds a site on a subdomain. It leads,
    /// but the field cannot complete `its` to `sdu.its…`, so it is left as typed.
    func testTheStartOfARegistrableDomainLeadsWithoutCompleting() {
        var sources = CommandBarSources()
        sources.sites = [site("sdu.itslearning.com", "https://sdu.itslearning.com/index.aspx")]

        let results = merge("itslearning", sources)

        XCTAssertEqual(results.first?.url, url("https://sdu.itslearning.com/index.aspx"))
        XCTAssertEqual(results.dropFirst().first?.source, .search)
        XCTAssertNil(CommandBarRanking.autofill(query: "itslearning", results: results))
    }

    /// §9.7: the site list is scanned on every keystroke, so a long one has to
    /// stay inside the frame — here 5,000 sites none of which match, the worst
    /// case, since a match stops the scan.
    func testScanningFiveThousandSitesStaysInsideTheFrame() {
        var sources = CommandBarSources()
        sources.sites = (0..<5000).map { site("site\($0).example") }

        let started = ContinuousClock.now
        for _ in 0..<20 {
            _ = merge("zz", sources)
        }
        XCTAssertLessThan((ContinuousClock.now - started) / 20, .milliseconds(5))
    }
}
