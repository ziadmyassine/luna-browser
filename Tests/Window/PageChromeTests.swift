//
//  PageChromeTests.swift
//  LunaTests
//
//  §3.2b: the address bar on the page instead of in the sidebar.
//
//  Two things are asserted here and nowhere else. The **rule** — when the bar
//  is open — is a value (`PageBarScroll`) precisely so that the awkward cases
//  can be written down rather than discovered by scrolling a particular site a
//  particular way. The **setting** resolves two keys into one answer, and the
//  bug it exists to prevent is the sidebar dropping its pill in a layout that
//  has no page bar to put it in.
//

import XCTest
@testable import Luna

@MainActor
final class PageBarScrollTests: XCTestCase {

    private var slack: Double { PageBarScroll.slack }

    func testTheBarStartsOpen() {
        XCTAssertFalse(PageBarScroll().isCollapsed)
    }

    func testScrollingDownPastTheSlackClosesIt() {
        var scroll = PageBarScroll()
        XCTAssertTrue(scroll.page(movedTo: slack * 3))
        XCTAssertTrue(scroll.isCollapsed)
    }

    /// The reason the rule is not "collapsed whenever the page is not at the
    /// top": once it is out of the way, reaching for the address must not mean
    /// scrolling all the way back up.
    func testScrollingBackUpOpensItWithoutReturningToTheTop() {
        var scroll = PageBarScroll()
        scroll.page(movedTo: slack * 10)
        XCTAssertTrue(scroll.isCollapsed)
        XCTAssertTrue(scroll.page(movedTo: slack * 8))
        XCTAssertFalse(scroll.isCollapsed)
    }

    /// The whole reason there is an anchor. A page that answers a scroll by
    /// nudging itself — an anchor jump, a sticky header settling, momentum
    /// unwinding — used to flip the bar while the user was holding still.
    func testAWobbleSmallerThanTheSlackChangesNothing() {
        var scroll = PageBarScroll()
        scroll.page(movedTo: slack * 10)
        for offset in stride(from: slack * 10, to: slack * 10 + slack, by: 1) {
            XCTAssertFalse(scroll.page(movedTo: offset), "\(offset) moved the bar")
        }
        XCTAssertTrue(scroll.isCollapsed)
    }

    /// The anchor trails the page while it keeps going the same way, so the
    /// reversal is measured from where the user stopped rather than from where
    /// they started. Without this, a long scroll down leaves the bar needing a
    /// scroll *back to the start* before it will reopen.
    func testTheReversalIsMeasuredFromWhereTheScrollStopped() {
        var scroll = PageBarScroll()
        for step in 1...50 { scroll.page(movedTo: Double(step) * slack) }
        XCTAssertTrue(scroll.isCollapsed)
        XCTAssertTrue(scroll.page(movedTo: 50 * slack - slack * 2))
        XCTAssertFalse(scroll.isCollapsed)
    }

    func testTheTopOfThePageAlwaysShowsTheBar() {
        var scroll = PageBarScroll()
        scroll.page(movedTo: slack * 10)
        XCTAssertTrue(scroll.isCollapsed)
        // A jump rather than a drag — `scrollTo(0)`, a fragment link, a reload.
        XCTAssertTrue(scroll.page(movedTo: 0))
        XCTAssertFalse(scroll.isCollapsed)
    }

    func testANewPageOpensItAgain() {
        var scroll = PageBarScroll()
        scroll.page(movedTo: slack * 10)
        scroll.reset()
        XCTAssertFalse(scroll.isCollapsed)
        // And the anchor went with it: the next page's own offsets are measured
        // from its top, not from where the last page happened to be left.
        XCTAssertFalse(scroll.page(movedTo: slack / 2))
    }

    func testTheStateOnlyChangesWhenItReallyChanges() {
        var scroll = PageBarScroll()
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

    /// The bug this property exists to prevent: §4 has one place for an address
    /// and the tab strip is built around it, so a placement left at "on the
    /// page" must not make the top bar's pill disappear into a bar that layout
    /// never shows.
    func testTheTopBarIgnoresThePlacementEntirely() {
        Settings.searchBarPlacement = .page
        Settings.chromeLayout = .topBar
        XCTAssertFalse(Settings.searchBarIsOnPage)
    }

    func testBothPlacementsSurviveARoundTripThroughDefaults() {
        for placement in SearchBarPlacement.allCases {
            Settings.searchBarPlacement = placement
            XCTAssertEqual(Settings.searchBarPlacement, placement)
            XCTAssertFalse(placement.title.isEmpty)
        }
    }
}

/// §3.2b's bar stands **above** the page, so the page starts below it — in both
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
