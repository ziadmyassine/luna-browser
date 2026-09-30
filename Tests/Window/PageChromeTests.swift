//
//  PageChromeTests.swift
//  LunaTests
//
//  §3.2b: the address bar on the page instead of in the sidebar.
//
//  The setting resolves two keys into one answer, which is what stops the
//  sidebar dropping its pill in a layout that has no page bar to put it in;
//  and the page starts below the bar, which is a real height it answers to.
//

import WebKit
import XCTest
@testable import Luna

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

    /// §4's bar has no page bar under it whatever the placement says — the
    /// placement is a sidebar question, and the bar's address is edited from
    /// the tab on screen.
    func testTheTopBarNeverHasThePageBar() {
        Settings.chromeLayout = .topBar
        for placement in SearchBarPlacement.allCases {
            Settings.searchBarPlacement = placement
            XCTAssertFalse(Settings.searchBarIsOnPage)
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

/// §3.2b's bar stands above the page, so the page starts below it, which makes
/// the band a real height the page has to answer to.
@MainActor
final class PageBarInsetTests: XCTestCase {

    /// One height however far the page scrolls: the bar no longer shrinks.
    func testTheBandIsAlwaysTheOpenHeight() {
        XCTAssertEqual(PageChromeBar().bandHeight, Tokens.Metric.pageBar)
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

    /// A web page runs under the bar and is told how much of it is covered.
    /// Moving its frame instead resized it a frame at a time, and the pane's
    /// grey showed between the bar and a page that had not caught up.
    func testAWebPageRunsUnderTheBarInsteadOfMoving() {
        let card = ContentCardView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        let page = WKWebView(frame: .zero)
        card.setContent(page)
        card.setContentTopInset(Tokens.Metric.pageBar, animated: false)
        card.layoutSubtreeIfNeeded()
        XCTAssertEqual(page.frame.maxY, card.bounds.maxY, "the page's top moved")
        XCTAssertEqual(page.obscuredContentInsets.top, Tokens.Metric.pageBar)
        card.setContentTopInset(0, animated: true)
        card.layoutSubtreeIfNeeded()
        XCTAssertEqual(page.frame.maxY, card.bounds.maxY, "the page's top moved")
        XCTAssertEqual(page.obscuredContentInsets.top, 0)
    }

    /// A tab switched to under a bar that is already there is covered too.
    func testATabArrivingUnderTheBarIsToldAtOnce() {
        let card = ContentCardView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        card.setContentTopInset(Tokens.Metric.pageBar, animated: false)
        let page = WKWebView(frame: .zero)
        card.setContent(page)
        XCTAssertEqual(page.obscuredContentInsets.top, Tokens.Metric.pageBar)
    }

    /// The page is scrolled by the change, so it stays still on screen —
    /// except the bar opening at the top of a document, which is the page
    /// making room.
    func testTheHoldingScrollCancelsTheMoveButNotAtTheTop() {
        let collapse = ContentCardView.holdingScript(-22)
        XCTAssertTrue(collapse.contains("const change = -22.0"))
        XCTAssertTrue(collapse.contains("behavior: \"instant\""))
        XCTAssertTrue(ContentCardView.holdingScript(22).contains("change > 0 && window.scrollY <= 24.0"))
    }
}
