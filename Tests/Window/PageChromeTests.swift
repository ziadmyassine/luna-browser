//
//  PageChromeTests.swift
//  LunaTests
//
//  §3.2b: the address bar on the page instead of in the sidebar.
//
//  Two things are asserted here and nowhere else. The rule for when the bar is
//  open is a value (`PageBarScroll`) so the awkward cases can be written down
//  rather than discovered by scrolling a particular site a particular way. And
//  the setting resolves two keys into one answer, which is what stops the
//  sidebar dropping its pill in a layout that has no page bar to put it in.
//

import XCTest
@testable import Luna

@MainActor
final class PageBarScrollTests: XCTestCase {

    private var slack: Double { PageBarScroll.slack }

    /// A rule that has heard where its page starts, which every real one has:
    /// the injected listener posts the offset the moment it runs. The first
    /// report is an arrival rather than a scroll — see
    /// `testAPageThatArrivesScrolledStillOpensTheBar` — so a test about
    /// scrolling has to get past it first.
    private func loaded(at start: Double = 0) -> PageBarScroll {
        var scroll = PageBarScroll()
        scroll.page(movedTo: start)
        return scroll
    }

    func testTheBarStartsOpen() {
        XCTAssertFalse(PageBarScroll().isCollapsed)
    }

    func testScrollingDownPastTheSlackClosesIt() {
        var scroll = loaded()
        XCTAssertTrue(scroll.page(movedTo: slack * 3))
        XCTAssertTrue(scroll.isCollapsed)
    }

    /// The reason the rule is not "collapsed whenever the page is not at the
    /// top": once it is out of the way, reaching for the address must not mean
    /// scrolling all the way back up.
    func testScrollingBackUpOpensItWithoutReturningToTheTop() {
        var scroll = loaded()
        scroll.page(movedTo: slack * 10)
        XCTAssertTrue(scroll.isCollapsed)
        XCTAssertTrue(scroll.page(movedTo: slack * 8))
        XCTAssertFalse(scroll.isCollapsed)
    }

    /// The whole reason there is an anchor. A page that answers a scroll by
    /// nudging itself — an anchor jump, a sticky header settling, momentum
    /// unwinding — used to flip the bar while the user was holding still.
    func testAWobbleSmallerThanTheSlackChangesNothing() {
        var scroll = loaded()
        scroll.page(movedTo: slack * 10)
        for offset in stride(from: slack * 10, to: slack * 10 + slack, by: 1) {
            XCTAssertFalse(scroll.page(movedTo: offset), "\(offset) moved the bar")
        }
        XCTAssertTrue(scroll.isCollapsed)
    }

    /// The anchor trails the page while it keeps going the same way, so the
    /// reversal is measured from where the user stopped rather than from where
    /// they started. Without this, a long scroll down leaves the bar needing a
    /// scroll back to the start before it will reopen.
    func testTheReversalIsMeasuredFromWhereTheScrollStopped() {
        var scroll = loaded()
        for step in 1...50 { scroll.page(movedTo: Double(step) * slack) }
        XCTAssertTrue(scroll.isCollapsed)
        XCTAssertTrue(scroll.page(movedTo: 50 * slack - slack * 2))
        XCTAssertFalse(scroll.isCollapsed)
    }

    func testTheTopOfThePageAlwaysShowsTheBar() {
        var scroll = loaded()
        scroll.page(movedTo: slack * 10)
        XCTAssertTrue(scroll.isCollapsed)
        // A jump rather than a drag — `scrollTo(0)`, a fragment link, a reload.
        XCTAssertTrue(scroll.page(movedTo: 0))
        XCTAssertFalse(scroll.isCollapsed)
    }

    func testANewPageOpensItAgain() {
        var scroll = loaded()
        scroll.page(movedTo: slack * 10)
        scroll.reset()
        XCTAssertFalse(scroll.isCollapsed)
        // And the anchor went with it: the next page's own offsets are measured
        // from its top, not from where the last page happened to be left.
        XCTAssertFalse(scroll.page(movedTo: slack / 2))
    }

    /// A page that loads already scrolled is still an arrival. WebKit
    /// restores the scroll position on a reload and on back/forward, and plenty
    /// of pages jump to an anchor of their own as they load — so the first
    /// thing heard from a document can be `y = 4000`. Measured from an anchor of
    /// zero that reads as a 4000 pt scroll down, and the bar collapsed the
    /// instant the site appeared.
    func testAPageThatArrivesScrolledStillOpensTheBar() {
        var scroll = PageBarScroll()
        scroll.reset()
        XCTAssertFalse(scroll.page(movedTo: slack * 200))
        XCTAssertFalse(scroll.isCollapsed)
    }

    /// And that first offset becomes the anchor, so the bar answers to what the
    /// user does from there rather than to where the page happened to open.
    func testTheFirstOffsetIsWhereTheNextScrollIsMeasuredFrom() {
        var scroll = PageBarScroll()
        scroll.reset()
        scroll.page(movedTo: slack * 200)
        XCTAssertFalse(scroll.page(movedTo: slack * 200 + slack / 2), "a wobble on arrival")
        XCTAssertTrue(scroll.page(movedTo: slack * 202))
        XCTAssertTrue(scroll.isCollapsed)
    }

    func testTheStateOnlyChangesWhenItReallyChanges() {
        var scroll = loaded()
        XCTAssertTrue(scroll.page(movedTo: slack * 4))
        XCTAssertFalse(scroll.page(movedTo: slack * 8), "a second collapse is not a change")
    }
}

@MainActor
final class SearchBarPlacementTests: XCTestCase {

    private var storedLayout: ChromeLayoutPreference!
    private var storedPlacement: SearchBarPlacement!

    override func setUp() {
        super.setUp()
        storedLayout = Settings.chromeLayout
        storedPlacement = Settings.searchBarPlacement
    }

    override func tearDown() {
        Settings.chromeLayout = storedLayout
        Settings.searchBarPlacement = storedPlacement
        super.tearDown()
    }

    /// A setting that moves a landmark must not move it for a user who has
    /// never heard of the setting.
    func testThePillIsInTheSidebarUntilSomebodyMovesIt() {
        Settings.chromeLayout = .sidebar
        XCTAssertEqual(SearchBarPlacement.sidebar.rawValue, "sidebar")
        UserDefaults.standard.removeObject(forKey: "luna.searchBarPlacement")
        XCTAssertEqual(Settings.searchBarPlacement, .sidebar)
        XCTAssertFalse(Settings.searchBarIsOnPage)
    }

    func testMovingItToThePageIsWhatPutsTheBarOnScreen() {
        Settings.chromeLayout = .sidebar
        Settings.searchBarPlacement = .page
        XCTAssertTrue(Settings.searchBarIsOnPage)
    }

    /// §4's bar holds tabs and no address, so the page bar stands under it
    /// whatever the placement says — the placement is a sidebar question.
    func testTheTopBarAlwaysHasThePageBar() {
        Settings.chromeLayout = .topBar
        for placement in SearchBarPlacement.allCases {
            Settings.searchBarPlacement = placement
            XCTAssertTrue(Settings.searchBarIsOnPage)
        }
    }

    func testBothPlacementsSurviveARoundTripThroughDefaults() {
        for placement in SearchBarPlacement.allCases {
            Settings.searchBarPlacement = placement
            XCTAssertEqual(Settings.searchBarPlacement, placement)
            XCTAssertFalse(placement.title.isEmpty)
        }
    }
}

/// §3.2b's bar stands above the page, so the page starts below it — in both
/// states, which makes the band a real height the page has to answer to.
@MainActor
final class PageBarInsetTests: XCTestCase {

    func testTheBandIsTheOpenHeightUntilItCollapses() {
        let bar = PageChromeBar()
        XCTAssertEqual(bar.bandHeight, Tokens.Metric.pageBar)
        bar.setCollapsed(true, animated: false)
        XCTAssertEqual(bar.bandHeight, Tokens.Metric.pageBarCollapsed)
        bar.setCollapsed(false, animated: false)
        XCTAssertEqual(bar.bandHeight, Tokens.Metric.pageBar)
    }

    /// Reported before the bar moves, so the page's animation and the bar's
    /// start on the same frame rather than one chasing the other.
    func testEveryStateChangeTellsThePageWhatRoomItHas() {
        let bar = PageChromeBar()
        var reported: [CGFloat] = []
        bar.onBandHeight = { height, _ in reported.append(height) }
        bar.setCollapsed(true, animated: false)
        bar.setCollapsed(false, animated: false)
        XCTAssertEqual(reported, [Tokens.Metric.pageBarCollapsed, Tokens.Metric.pageBar])
    }

    /// A state it is already in is not a change, and must not reflow the page.
    func testSettingTheSameStateTwiceSaysNothing() {
        let bar = PageChromeBar()
        bar.setCollapsed(true, animated: false)
        var reported = 0
        bar.onBandHeight = { _, _ in reported += 1 }
        bar.setCollapsed(true, animated: false)
        XCTAssertEqual(reported, 0)
    }

    /// The card takes the inset once and ignores a repeat of it, because the
    /// repeat would animate a constraint to the value it already holds.
    func testTheCardOnlyMovesThePageWhenTheInsetActuallyChanges() {
        let card = ContentCardView()
        let page = NSView()
        card.setContent(page)
        card.setContentTopInset(Tokens.Metric.pageBar, animated: false)
        card.layoutSubtreeIfNeeded()
        let top = page.frame.maxY
        card.setContentTopInset(Tokens.Metric.pageBar, animated: false)
        card.layoutSubtreeIfNeeded()
        XCTAssertEqual(page.frame.maxY, top)
    }
}
