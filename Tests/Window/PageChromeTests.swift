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

@testable import BrowserKit
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

    /// WebKit's inspector docked beside the page stands on the chrome beside
    /// it. The bar follows the page instead of running across the
    /// inspector's top, so the inspector starts at the top; only the traffic
    /// lights, over the card's corner when the sidebar is hidden, push it down.
    func testADockedInspectorBesideThePageKeepsTheBarOverThePage() {
        let card = ContentCardView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        let page = WKWebView(frame: .zero)
        card.setContent(page)
        let bar = NSView()
        card.setOverlay(bar)
        card.setContentTopInset(Tokens.Metric.pageBar, animated: false)
        card.layoutSubtreeIfNeeded()
        let inspector = FakeInspectorWebView(frame: NSRect(x: 500, y: 0, width: 300, height: 600))
        card.addSubview(inspector)
        page.frame = NSRect(x: 0, y: 0, width: 500, height: 600)
        XCTAssertEqual(bar.frame, page.frame, "the bar ran across the inspector")
        XCTAssertEqual(inspector.obscuredContentInsets.top, 0, "the inspector beside started below a bar not over it")
        XCTAssertEqual(page.layer?.cornerRadius, WindowCorner.radius, "the page beside the inspector stayed square")

        card.insetEdge = nil
        inspector.frame = NSRect(x: 0, y: 0, width: 300, height: 600)
        page.frame = NSRect(x: 300, y: 0, width: 500, height: 600)
        XCTAssertEqual(inspector.obscuredContentInsets.top, Tokens.Metric.pageBar, "the lights sat over the inspector")

        inspector.frame = NSRect(x: 0, y: 0, width: 800, height: 250)
        page.frame = NSRect(x: 0, y: 250, width: 800, height: 350)
        XCTAssertEqual(inspector.obscuredContentInsets.top, 0, "the inspector below the page was pushed down")

        inspector.removeFromSuperview()
        card.layoutSubtreeIfNeeded()
        XCTAssertFalse(page.translatesAutoresizingMaskIntoConstraints, "the page did not get its edges back")
        XCTAssertEqual(bar.frame, card.bounds, "the bar did not get the card's edges back")
        XCTAssertEqual(page.layer?.cornerRadius, 0, "the page kept the inspector's corners")
    }

    /// The page rounds every corner that meets the inspector or the chrome,
    /// and leaves square only those where two window edges meet — the
    /// window's own mask rounds those, and in fullscreen they are square.
    func testThePageRoundsTheCornersThatMeetAnInspector() {
        let card = NSRect(x: 0, y: 0, width: 800, height: 600)
        let all: CACornerMask = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner, .layerMinXMinYCorner, .layerMaxXMinYCorner]
        let below = NSRect(x: 0, y: 250, width: 800, height: 350)
        XCTAssertEqual(
            ContentCardView.roundedCorners(of: below, in: card, chrome: [.leading]),
            [.layerMinXMaxYCorner, .layerMinXMinYCorner, .layerMaxXMinYCorner],
            "below the page, the window's own top right corner was rounded again"
        )
        XCTAssertEqual(ContentCardView.roundedCorners(of: below, in: card, chrome: [.top]), all)
        let leftOfInspector = NSRect(x: 0, y: 0, width: 500, height: 600)
        XCTAssertEqual(ContentCardView.roundedCorners(of: leftOfInspector, in: card, chrome: [.leading]), all)
        let rightOfInspector = NSRect(x: 300, y: 0, width: 500, height: 600)
        XCTAssertEqual(
            ContentCardView.roundedCorners(of: rightOfInspector, in: card, chrome: []),
            [.layerMinXMaxYCorner, .layerMinXMinYCorner],
            "with the sidebar hidden, the page rounded the window's own corners"
        )
    }

    /// A flipped layer has its top at `minY`, and a web view is flipped.
    func testAFlippedPageIsRoundedAtTheSameCorners() {
        let page = WKWebView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        page.wantsLayer = true
        ContentCardView.round(page, corners: [.layerMinXMaxYCorner], edged: true)
        XCTAssertEqual(page.layer?.maskedCorners, [.layerMinXMinYCorner])
        XCTAssertTrue(page.layer?.isGeometryFlipped == true, "the web view's layer is no longer flipped")
        XCTAssertEqual(page.layer?.borderWidth, Tokens.Metric.hairline)
    }

    /// The inspector is held back until it wears the stylesheet. Closed, the
    /// page takes its whole size at once and is uncovered from where it
    /// stood, the bar over it with it, while the card stays clear behind.
    func testAClosedInspectorsPlaceIsUncoveredFromWhereThePageStood() throws {
        let card = ContentCardView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        let page = WKWebView(frame: .zero)
        card.setContent(page)
        let bar = NSView()
        card.setOverlay(bar)
        card.layoutSubtreeIfNeeded()
        let inspector = FakeInspectorWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 250))
        card.addSubview(inspector)
        XCTAssertEqual(inspector.alphaValue, 0, "the inspector showed before it wore the stylesheet")
        inspector.removeFromSuperview()
        XCTAssertEqual(inspector.alphaValue, 1, "undocked into a window of its own, the inspector stayed invisible")

        let above = NSRect(x: 0, y: 250, width: 800, height: 350)
        card.revealPage(from: above, corners: [.layerMinXMinYCorner, .layerMaxXMinYCorner])
        XCTAssertEqual(page.frame, card.bounds, "the page did not take its whole size at once")
        let mask = try XCTUnwrap(page.layer?.mask, "the page was not masked")
        XCTAssertEqual(mask.frame, page.bounds)
        XCTAssertEqual(mask.maskedCorners, [.layerMinXMaxYCorner, .layerMaxXMaxYCorner], "the flipped page's mask rounded its top")
        XCTAssertEqual(Self.start(of: mask), NSPoint(x: 400, y: 175), "the flipped page was uncovered from somewhere else")
        let barMask = try XCTUnwrap(bar.layer?.mask, "the bar was not masked with the page")
        XCTAssertEqual(Self.start(of: barMask), NSPoint(x: 400, y: 425))
        card.updateLayer()
        XCTAssertEqual(card.layer?.backgroundColor?.alpha, 0, "the card's grey showed beside the growing page")

        card.endPageReveal()
        XCTAssertNil(page.layer?.mask)
        XCTAssertNil(bar.layer?.mask)
        card.updateLayer()
        XCTAssertEqual(card.layer?.backgroundColor?.alpha, 1, "the card stayed clear after the page had it all")
    }

    private static func start(of mask: CALayer) -> NSPoint? {
        ((mask.animation(forKey: "position") as? CABasicAnimation)?.fromValue as? NSValue)?.pointValue
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

/// §3.2b: the bar hears the colour under it from whichever tab is showing, even
/// when that tab's page was made without anything else in the session changing.
@MainActor
final class PageBarColourTests: XCTestCase {

    private let directory = URL.temporaryDirectory.appending(path: "luna-tests-\(UUID().uuidString)")

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    /// Launch, as it happens: the bar comes up while the selected tab has no
    /// controller, and the window then asks for the tab's web view, which builds
    /// one without a session change. The bar used to wait for a change that
    /// never came, and wore the document's grey under Netflix's black header
    /// until the selection moved.
    func testATabWhosePageIsMadeAfterTheBarStillReportsItsColour() async throws {
        let session = try await BrowserSession.restored(store: BrowserStore(path: directory.appending(path: "luna.sqlite")))
        let id = session.newTab(url: URL(string: "about:blank"))
        session.discardController(id)
        let page = PageChromeController(session: session, windowID: session.keyWindowID)
        page.setActive(true, animated: false)

        _ = session.webView(for: id)
        let controller = try XCTUnwrap(session.controller(for: id))
        controller.setTopColour(RGBA(r: 0, g: 0, b: 0, a: 1))

        let bar = try XCTUnwrap(page.view as? PageChromeBar)
        let plane = try XCTUnwrap(bar.plane.layer?.backgroundColor.flatMap(NSColor.init(cgColor:))?.usingColorSpace(.sRGB))
        XCTAssertEqual(plane.redComponent, 0, accuracy: 0.01, "the bar never heard the page's colour")
        XCTAssertEqual(plane.greenComponent, 0, accuracy: 0.01)
        XCTAssertEqual(plane.blueComponent, 0, accuracy: 0.01)
    }
}

/// Stands in for WebKit's docked inspector, which the card finds by its class
/// name.
private final class FakeInspectorWebView: WKWebView {}
