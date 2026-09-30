//
//  PageChromeBarTests.swift
//  LunaTests
//
//  §3.2b's bar, as geometry. Three things can go wrong here without anyone
//  noticing until a narrow window or a particular chrome state finds them: the
//  pill overlapping the buttons beside it, the bar eating clicks meant for the
//  page, and the two controls that live inside the capsule drifting off its
//  ends or out from under the address's margins.
//

import XCTest
@testable import BrowserKit
@testable import Luna

@MainActor
final class PageChromeBarTests: XCTestCase {

    private func bar(width: CGFloat) -> PageChromeBar {
        let bar = PageChromeBar()
        bar.frame = NSRect(x: 0, y: 0, width: width, height: Tokens.Metric.pageBar)
        bar.show(url: URL(string: "https://www.apple.com/iphone"))
        bar.layoutSubtreeIfNeeded()
        return bar
    }

    /// The bar's own two controls, the pill, and the two glyphs inside it —
    /// which are the pill's on both surfaces, not the bar's.
    private struct Controls {
        let leading: [NSView]
        let inPill: [NSView]
        let buttons: [NSView]
        let pill: URLPillView
    }

    private func controls(of bar: PageChromeBar) -> Controls? {
        let pill = bar.subviews.compactMap { $0 as? URLPillView }.first
        let leading = bar.subviews.filter { $0 is NavCluster || $0 === bar.toggle }
        guard let pill, leading.count == 2 else { return nil }
        let inPill = [pill.sliders, pill.reload] as [NSView]
        return Controls(leading: leading, inPill: inPill, buttons: leading + inPill, pill: pill)
    }

    /// The glyphs' frames in the bar's own coordinates, so they can be compared
    /// with the pill's.
    private func inBar(_ view: NSView, _ bar: PageChromeBar) -> NSRect {
        view.superview.map { bar.convert(view.frame, from: $0) } ?? view.frame
    }

    private func press(_ view: NSView) throws {
        let click = try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        ))
        view.mouseDown(with: click)
    }

    /// The toggle and the history cluster, in that order, and clear of the
    /// pill: reload is not beside them any more — it is inside the capsule.
    func testTheBarsOwnControlsLeadItAndStayClearOfThePill() throws {
        let parts = try XCTUnwrap(controls(of: bar(width: 1200)))
        let order = parts.leading.map(\.frame.minX)
        XCTAssertEqual(order, order.sorted())
        let last = try XCTUnwrap(parts.leading.map(\.frame.maxX).max())
        XCTAssertLessThanOrEqual(last, parts.pill.frame.minX)
    }

    /// Site settings leads the capsule and reload trails it, both inside
    /// it, both the same distance from the end they are on. A lone control on
    /// one side is what made the address read as pushed rather than placed.
    func testTheCapsuleCarriesAControlAtEachEnd() throws {
        let wide = bar(width: 1600)
        let parts = try XCTUnwrap(controls(of: wide))
        parts.pill.layoutSubtreeIfNeeded()
        let pill = parts.pill.frame
        let reach = Tokens.Metric.pillTextInset + Tokens.Metric.glyphSize / 2
        XCTAssertEqual(inBar(parts.inPill[0], wide).midX, pill.minX + reach, accuracy: 1)
        XCTAssertEqual(inBar(parts.inPill[1], wide).midX, pill.maxX - reach, accuracy: 1)
        for view in parts.inPill {
            XCTAssertEqual(inBar(view, wide).midY, pill.midY, accuracy: 1)
        }
    }

    /// And the address keeps clear of both of them, symmetrically — an
    /// off-centre domain in a centred capsule is worse than no centring at all.
    func testTheAddressIsCentredInWhatTheTwoControlsLeave() throws {
        let parts = try XCTUnwrap(controls(of: bar(width: 1600)))
        let pill = parts.pill
        pill.layoutSubtreeIfNeeded()
        XCTAssertEqual(
            pill.field.frame.midX, pill.bounds.midX, accuracy: 1,
            "the address is not centred in the capsule"
        )
        XCTAssertGreaterThan(pill.field.frame.minX, pill.sliders.frame.midX)
        XCTAssertLessThan(pill.field.frame.maxX, pill.reload.frame.midX)
    }

    /// No favicon up there, in either form. The pill wore a leading mark
    /// for a while — magnifier, globe, or the site's own icon — and an address
    /// bar is not where it belongs: a favicon at the head of the one line
    /// saying what page you are on is a second thing to read. §9.1's field
    /// keeps it, where it answers a question as it is being typed.
    func testTheCapsuleWearsNoLeadingMark() throws {
        let wide = bar(width: 1600)
        let pill = try XCTUnwrap(controls(of: wide)?.pill)
        pill.layoutSubtreeIfNeeded()
        let drawn = Set(pill.subviews.compactMap { $0 as? NSImageView }.filter { !$0.isHidden })
        XCTAssertEqual(drawn, [pill.sliders, pill.reload], "something other than the two glyphs is drawn in the pill")
    }

    /// Four controls on one line, one of them a different height, is the thing
    /// the eye finds first. The two tokens are equal today — `sidebarCircle` is
    /// a circle of `urlPill.height` — and this is what stops them drifting.
    func testThePillIsExactlyAsTallAsTheButtons() throws {
        let parts = try XCTUnwrap(controls(of: bar(width: 1600)))
        for button in parts.leading {
            XCTAssertEqual(parts.pill.frame.height, button.frame.height)
            XCTAssertEqual(parts.pill.frame.midY, button.frame.midY, accuracy: 1)
        }
    }

    /// The pill is centred on the pane when there is room for it to be.
    func testTheAddressIsCentredOnAWindowWideEnoughToCentreIt() throws {
        let wide = bar(width: 1600)
        let parts = try XCTUnwrap(controls(of: wide))
        XCTAssertEqual(parts.pill.frame.midX, wide.bounds.midX, accuracy: 1)
        XCTAssertEqual(parts.pill.frame.width, Tokens.Metric.pageBarPillWidth, accuracy: 1)
    }

    /// And pushed off centre rather than under the buttons when there is not.
    /// A 640 pt window with a 280 pt sidebar leaves the pane about 360 pt, and
    /// a pill centred in that overlaps all three circles.
    func testANarrowPaneMovesThePillRatherThanOverlappingTheButtons() throws {
        let narrow = bar(width: 360)
        let parts = try XCTUnwrap(controls(of: narrow))
        let lastButton = try XCTUnwrap(parts.leading.map(\.frame.maxX).max())
        XCTAssertGreaterThanOrEqual(parts.pill.frame.minX, lastButton)
        XCTAssertLessThanOrEqual(parts.pill.frame.maxX, narrow.bounds.maxX)
    }

    /// The pill hands the address to §9.1 rather than opening a field. The
    /// anchor it sends is the pill itself, which is what lets the bar grow out
    /// of the capsule that was pressed.
    func testPressingTheAddressHandsItToTheCommandBarStandingOnThePill() throws {
        let wide = bar(width: 1600)
        let pill = try XCTUnwrap(controls(of: wide)?.pill as? URLPillView)
        var anchors: [CommandBarAnchor] = []
        wide.onHandOff = { anchors.append($0) }

        try press(pill)
        XCTAssertEqual(anchors.count, 1)
        XCTAssertIdentical(anchors.first?.view, pill)
    }

    /// The bar's own band is chrome and takes its clicks.
    func testOnlyTheBandTakesClicks() throws {
        let wide = bar(width: 1600)
        let parts = try XCTUnwrap(controls(of: wide))
        let lastButton = try XCTUnwrap(parts.leading.map(\.frame.maxX).max())
        let gap = NSPoint(x: (lastButton + parts.pill.frame.minX) / 2, y: wide.bounds.midY)
        XCTAssertNotNil(wide.hitTest(gap), "the open bar spans its whole frame")
        XCTAssertNotNil(wide.hitTest(NSPoint(x: parts.pill.frame.midX, y: parts.pill.frame.midY)))
    }

    // MARK: - Fullscreen

    private func windowed(_ bar: PageChromeBar) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView?.addSubview(bar)
        bar.frame = NSRect(x: 0, y: 0, width: 1200, height: Tokens.Metric.pageBar)
        bar.layoutSubtreeIfNeeded()
        return window
    }

    /// Fullscreen takes the traffic lights out of the window and hands them
    /// back, and neither edge resizes this bar. `placeControls` measures
    /// against them, so without this the bar keeps a placement made when they
    /// were somewhere else — which is §3.2b's dissolve turning into a move, in
    /// fullscreen only. §3.1's control row is fixed the same way, but that pass
    /// walks the chrome host's subviews and this bar is an overlay on the card.
    func testTheLightsMovingMarksTheBarForAFreshLayout() {
        let bar = bar(width: 1200)
        let window = windowed(bar)
        XCTAssertFalse(bar.needsLayout)

        NotificationCenter.default.post(name: NSWindow.didEnterFullScreenNotification, object: window)
        XCTAssertTrue(bar.needsLayout, "entering fullscreen left the bar measured against the old lights")

        bar.layoutSubtreeIfNeeded()
        NotificationCenter.default.post(name: NSWindow.didExitFullScreenNotification, object: window)
        XCTAssertTrue(bar.needsLayout, "coming back out left the bar measured against the old lights")
    }

    /// The notification is posted for every window in the app, and another
    /// window's fullscreen moved nothing this bar can see.
    func testAnotherWindowsFullscreenIsNotThisBarsBusiness() {
        let bar = bar(width: 1200)
        _ = windowed(bar)
        let other = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 400),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        NotificationCenter.default.post(name: NSWindow.didEnterFullScreenNotification, object: other)
        XCTAssertFalse(bar.needsLayout)
    }

    /// The bar is a plane in the page's colour, so what is drawn on it has to
    /// be inked for that colour rather than for the app's. One appearance on
    /// the subtree is how every token on it — text, glyph ink, glass fallback —
    /// gets that answer at once.
    func testTheBarTakesTheAppearanceThePageCallsFor() {
        let light = bar(width: 1200)
        light.setPageColour(RGBA(r: 1, g: 1, b: 1, a: 1))
        XCTAssertEqual(light.appearance?.name, .aqua)

        let dark = bar(width: 1200)
        dark.setPageColour(RGBA(r: 0.07, g: 0.07, b: 0.07, a: 1))
        XCTAssertEqual(dark.appearance?.name, .darkAqua)
    }

    /// The plane follows the page down: a document's own background is one
    /// answer for the whole site, and the strip actually under the bar is a
    /// better one wherever the page has it. Nil is the page saying it has no
    /// single colour up there — two columns, a card over a tint — and the
    /// document's background is what is left, not black and not the last
    /// section's colour.
    func testTheStripUnderTheBarBeatsTheDocumentsOwnColour() {
        let page = bar(width: 1200)
        page.setPageColour(RGBA(r: 1, g: 1, b: 1, a: 1))
        XCTAssertEqual(page.appearance?.name, .aqua)

        page.setTopColour(RGBA(r: 0.05, g: 0.05, b: 0.05, a: 1))
        XCTAssertEqual(page.appearance?.name, .darkAqua, "scrolled onto a black section")

        page.setTopColour(nil)
        XCTAssertEqual(page.appearance?.name, .aqua, "back to the document's own colour")
    }
}

/// §30.1, and the report behind it: one window has one handle.
///
/// The sidebar's plane is what moves the window in this layout. §3.2b's bar is
/// over the page, inside the card, and dragging it used to move the window as
/// well — two handles, one of them on the band the user is aiming at for the
/// pill and the toggle. The exception is a hidden sidebar, where this bar is
/// the only chrome left above the page.
@MainActor
final class PageChromeBarDragTests: XCTestCase {

    private func bar(in state: ChromeState) throws -> PageChromeBar {
        let controller = BrowserWindowController()
        controller.setChromeStateWithoutAnimation(state)
        let bar = PageChromeBar()
        controller.setPageOverlay(bar)
        _ = try XCTUnwrap(controller.window?.contentView)
        return bar
    }

    func testTheBarDoesNotMoveTheWindowWhileTheSidebarIsOnScreen() throws {
        let bar = try bar(in: .sidebar(width: Tokens.Metric.sidebarWidth.default, edge: .leading))
        XCTAssertFalse(bar.mouseDownCanMoveWindow)
    }

    func testItDoesWhenTheSidebarHasBeenPutAway() throws {
        let bar = try bar(in: .sidebarCollapsed(edge: .leading))
        XCTAssertTrue(bar.mouseDownCanMoveWindow, "with the column gone there is nothing else left to drag by")
    }
}

/// §7.2's peek brings the lights back over a hidden sidebar. They stand on the
/// sidebar that has slid out over this bar, so the bar's buttons stay where
/// they were rather than stepping aside under it.
@MainActor
final class PageChromeBarPeekTests: XCTestCase {

    private func firstButtonX(in state: ChromeState) throws -> CGFloat {
        let controller = BrowserWindowController()
        controller.setChromeStateWithoutAnimation(state)
        let window = try XCTUnwrap(controller.window)
        let bar = PageChromeBar()
        controller.setPageOverlay(bar)
        window.contentView?.layoutSubtreeIfNeeded()
        let lights = [.closeButton, .miniaturizeButton, .zoomButton].compactMap { window.standardWindowButton($0) }
        try XCTSkipIf(lights.count < 3, "this macOS gave the window fewer than three window buttons")
        controller.trafficLights?.isPeeking = true
        XCTAssertFalse(try XCTUnwrap(lights.last).isHidden, "the peek did not bring the lights back")
        bar.placeControls()
        return try XCTUnwrap(bar.buttons.first).frame.minX
    }

    func testALeadingPeeksLightsLeaveTheBarsButtonsWhereTheyAre() throws {
        let x = try firstButtonX(in: .sidebarCollapsed(edge: .leading))
        XCTAssertEqual(x, Tokens.Metric.pageBarInset, accuracy: 0.5, "the buttons stepped aside under the sidebar")
    }

    /// A trailing sidebar peeks on the far side, and the lights are over the
    /// page beside the buttons, so those are still cleared.
    func testATrailingPeeksLightsAreStillCleared() throws {
        let x = try firstButtonX(in: .sidebarCollapsed(edge: .trailing))
        XCTAssertGreaterThan(x, Tokens.Metric.pageBarInset + 1, "the buttons stand under the lights")
    }
}
