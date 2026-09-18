//
//  PageChromeBarTests.swift
//  LunaTests
//
//  §3.2b's bar, as geometry. Three things can go wrong here without anyone
//  noticing until a narrow window or a particular chrome state finds them: the
//  pill overlapping the buttons, the bar eating clicks meant for the page, and
//  the pill's two layouts disagreeing about which edge the sliders glyph is on.
//

import XCTest
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

    private func controls(of bar: PageChromeBar) -> (buttons: [NSView], pill: NSView)? {
        let pill = bar.subviews.first { $0 is URLPillView }
        let buttons = bar.subviews.filter { $0 is GlassButton }
        guard let pill, buttons.count == 3 else { return nil }
        return (buttons, pill)
    }

    /// The reference's three: the sidebar toggle, back and reload, in that
    /// order, because that is where §3.1 left them.
    func testItCarriesTheThreeControlsTheSidebarGaveUp() throws {
        let parts = try XCTUnwrap(controls(of: bar(width: 1200)))
        let order = parts.buttons.map(\.frame.minX)
        XCTAssertEqual(order, order.sorted())
    }

    /// Four controls on one line, one of them a different height, is the thing
    /// the eye finds first. The two tokens are equal today — `sidebarCircle` is
    /// a circle of `urlPill.height` — and this is what stops them drifting.
    func testThePillIsExactlyAsTallAsTheButtons() throws {
        let parts = try XCTUnwrap(controls(of: bar(width: 1600)))
        for button in parts.buttons {
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
        let lastButton = try XCTUnwrap(parts.buttons.map(\.frame.maxX).max())
        XCTAssertGreaterThanOrEqual(parts.pill.frame.minX, lastButton)
        XCTAssertLessThanOrEqual(parts.pill.frame.maxX, narrow.bounds.maxX)
    }

    /// Collapsed, the pill shrinks to the address it is showing instead of
    /// holding a 420 pt capsule open over the page.
    func testCollapsingShrinksThePillToItsDomain() throws {
        let wide = bar(width: 1600)
        let open = try XCTUnwrap(controls(of: wide)).pill.frame
        wide.setCollapsed(true, animated: false)
        wide.layoutSubtreeIfNeeded()
        let shut = try XCTUnwrap(controls(of: wide)).pill.frame
        XCTAssertLessThan(shut.width, open.width)
        XCTAssertLessThan(shut.height, open.height)
        XCTAssertEqual(shut.midX, wide.bounds.midX, accuracy: 1)
    }

    func testCollapsingTakesTheButtonsAwayRatherThanMovingThem() throws {
        let wide = bar(width: 1600)
        wide.setCollapsed(true, animated: false)
        wide.layoutSubtreeIfNeeded()
        let parts = try XCTUnwrap(controls(of: wide))
        XCTAssertTrue(parts.buttons.allSatisfy(\.isHidden))
    }

    /// The bar covers the top of a live web page. Everything it does not draw
    /// on belongs to the page — a link under the gap between the buttons and
    /// the pill has to stay clickable.
    func testTheGapsBetweenTheControlsBelongToThePage() throws {
        let wide = bar(width: 1600)
        let parts = try XCTUnwrap(controls(of: wide))
        let lastButton = try XCTUnwrap(parts.buttons.map(\.frame.maxX).max())
        let gap = NSPoint(x: (lastButton + parts.pill.frame.minX) / 2, y: wide.bounds.midY)
        XCTAssertNil(wide.hitTest(gap))
        XCTAssertNotNil(wide.hitTest(NSPoint(x: parts.pill.frame.midX, y: parts.pill.frame.midY)))
    }
}

@MainActor
final class URLPillLayoutTests: XCTestCase {

    private func pill(centred: Bool) -> URLPillView {
        let pill = URLPillView()
        pill.centresText = centred
        pill.show(url: URL(string: "https://www.apple.com"))
        pill.frame = NSRect(x: 0, y: 0, width: 400, height: Tokens.Metric.urlPill.height)
        pill.layoutSubtreeIfNeeded()
        return pill
    }

    /// Over a page there is no plane for a well to be cut into, so the pill
    /// carries the material its neighbours carry — and drops the plate and the
    /// hairline that go with being a recess, exactly as `GlassButton` does at
    /// `.always`.
    func testThePageBarsPillWearsItsMaterialAtRest() {
        let plain = pill(centred: true)
        XCTAssertNil(plain.subviews.first { NSStringFromClass(type(of: $0)).contains("GlassBacking") })
        let glassy = pill(centred: true)
        glassy.alwaysGlass = true
        glassy.layoutSubtreeIfNeeded()
        glassy.displayIfNeeded()
        XCTAssertNotNil(glassy.subviews.first { NSStringFromClass(type(of: $0)).contains("GlassBacking") })
        XCTAssertNil(glassy.layer?.backgroundColor)
        XCTAssertEqual(glassy.layer?.borderWidth, 0)
    }

    /// A 17 pt radius on a 22 pt capsule is a rectangle with dents in it, and
    /// §3.2b's pill is 22 pt for as long as the page is scrolled.
    func testACollapsedPillIsStillACapsule() {
        let short = pill(centred: true)
        short.frame = NSRect(x: 0, y: 0, width: 160, height: Tokens.Metric.pageBarCollapsedPillHeight)
        short.layoutSubtreeIfNeeded()
        short.displayIfNeeded()
        XCTAssertEqual(short.layer?.cornerRadius, short.frame.height / 2)
    }

    /// §3.2's pill puts the glyph on the trailing edge; §3.2b's puts it on the
    /// leading one, which is the only difference between them.
    func testTheGlyphSwapsEndsWithTheLayout() {
        XCTAssertGreaterThan(pill(centred: false).siteMenuAnchor.frame.midX, 200)
        XCTAssertLessThan(pill(centred: true).siteMenuAnchor.frame.midX, 200)
    }

    /// §3.2b's collapsed capsule is sized to this, so it has to be a width the
    /// domain actually fits in — and narrower than the open pill, or collapsing
    /// would make the bar bigger.
    func testTheFittingWidthHoldsTheDomainAndNoMore() {
        let pill = pill(centred: true)
        XCTAssertGreaterThan(pill.fittingWidth, pill.siteMenuAnchor.frame.width)
        XCTAssertLessThan(pill.fittingWidth, Tokens.Metric.pageBarPillWidth)
    }
}
