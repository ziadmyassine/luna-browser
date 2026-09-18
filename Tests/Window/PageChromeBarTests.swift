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

    /// The bar's own band is chrome and takes its clicks; the page keeps the
    /// rest. The frame stays the open height in both states, so while the bar
    /// is collapsed its lower 22 pt is live page and a link there has to work.
    func testOnlyTheBandTakesClicks() throws {
        let wide = bar(width: 1600)
        let parts = try XCTUnwrap(controls(of: wide))
        let lastButton = try XCTUnwrap(parts.buttons.map(\.frame.maxX).max())
        let gap = NSPoint(x: (lastButton + parts.pill.frame.minX) / 2, y: wide.bounds.midY)
        XCTAssertNotNil(wide.hitTest(gap), "the open bar spans its whole frame")
        XCTAssertNotNil(wide.hitTest(NSPoint(x: parts.pill.frame.midX, y: parts.pill.frame.midY)))

        wide.setCollapsed(true, animated: false)
        wide.layoutSubtreeIfNeeded()
        let belowTheStrip = NSPoint(x: gap.x, y: wide.bounds.maxY - Tokens.Metric.pageBar + 1)
        XCTAssertNil(wide.hitTest(belowTheStrip), "a collapsed bar gives the page back its room")
    }

    /// The bar is a plane in the page's colour, so what is drawn on it has to
    /// be inked for *that* colour rather than for the app's. One appearance on
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

    private func backing(of view: NSView) -> NSView? {
        view.subviews.first { NSStringFromClass(type(of: $0)).contains("GlassBacking") }
    }

    /// The three surfaces a pill can be, and what each one is made of. §3.2's
    /// well is lit only while it is being used; §3.2b's open pill is lit at
    /// rest with no plate under it; its collapsed pill is nothing at all,
    /// because the bar's own plane is the surface it would be drawn on.
    func testEachSurfaceIsMadeOfWhatItSaysItIs() {
        let well = pill(centred: false)
        well.displayIfNeeded()
        XCTAssertNil(backing(of: well), "a resting well has no material yet")
        XCTAssertNotNil(well.layer?.backgroundColor)
        XCTAssertEqual(well.layer?.borderWidth, Tokens.Metric.hairline)

        let glassy = pill(centred: true)
        glassy.surface = .glass
        glassy.displayIfNeeded()
        XCTAssertNotNil(backing(of: glassy))
        XCTAssertNil(glassy.layer?.backgroundColor)
        XCTAssertEqual(glassy.layer?.borderWidth, 0)

        let bare = pill(centred: true)
        bare.surface = .bare
        bare.displayIfNeeded()
        XCTAssertNil(bare.layer?.backgroundColor)
        XCTAssertEqual(bare.layer?.borderWidth, 0)
        XCTAssertEqual(backing(of: bare)?.alphaValue ?? 0, 0, "a bare pill shows no material")
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

/// §3.4's completions under §3.2b's pill. The list is a value-ish object — it
/// holds phrases and an index — so the keyboard rule can be written down rather
/// than discovered by arrowing through a live one.
@MainActor
final class PageBarSuggestionsTests: XCTestCase {

    private func list(_ phrases: [String] = ["swift", "swift concurrency", "swiftui"]) -> PageBarSuggestions {
        let list = PageBarSuggestions()
        list.show(phrases)
        return list
    }

    /// Nothing is selected until the user moves: the first keystroke after a
    /// pause must not change what Return does under their hands.
    func testItOpensOnWhatWasTypedRatherThanOnASuggestion() {
        XCTAssertNil(list().selectedPhrase)
    }

    func testDownWalksTheListAndUpComesBackOut() {
        let list = list()
        XCTAssertTrue(list.move(1))
        XCTAssertEqual(list.selectedPhrase, "swift")
        XCTAssertTrue(list.move(1))
        XCTAssertEqual(list.selectedPhrase, "swift concurrency")
        XCTAssertTrue(list.move(-1))
        XCTAssertEqual(list.selectedPhrase, "swift")
        XCTAssertTrue(list.move(-1))
        XCTAssertNil(list.selectedPhrase, "the typed text is an entry and has to be reachable")
    }

    /// Off the bottom is the typed text again, not the top — the same way out
    /// at either end.
    func testFallingOffTheEndReturnsToWhatWasTyped() {
        let list = list()
        for _ in 0..<3 { _ = list.move(1) }
        XCTAssertEqual(list.selectedPhrase, "swiftui")
        XCTAssertTrue(list.move(1))
        XCTAssertNil(list.selectedPhrase)
    }

    func testUpFromTheTypedTextLandsOnTheLastRow() {
        let list = list()
        XCTAssertTrue(list.move(-1))
        XCTAssertEqual(list.selectedPhrase, "swiftui")
    }

    /// With nothing to walk through the field keeps the key, so the caret moves
    /// as it would in any other text field.
    func testAnEmptyListLeavesTheArrowKeysAlone() {
        let empty = list([])
        XCTAssertFalse(empty.move(1))
        XCTAssertFalse(empty.move(-1))
        XCTAssertTrue(empty.isHidden)
    }

    func testANewSetOfAnswersForgetsTheOldSelection() {
        let list = list()
        _ = list.move(1)
        list.show(["something else"])
        XCTAssertNil(list.selectedPhrase)
    }

    func testDismissingLeavesNothingToCommit() {
        let list = list()
        _ = list.move(1)
        list.dismiss()
        XCTAssertNil(list.selectedPhrase)
        XCTAssertTrue(list.isHidden)
        XCTAssertEqual(list.fittingHeight, 0)
    }
}
