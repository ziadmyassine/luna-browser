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

    /// Collapsed, the pill keeps its place and its width and loses its height.
    /// It can: with no surface under it there is nothing to see but the centred
    /// domain, so a 420 pt capsule collapsed is 420 pt of nothing with a word in
    /// the middle — and the word is on the line the open pill put it on.
    func testCollapsingChangesTheHeightAndNothingElse() throws {
        let wide = bar(width: 1600)
        let open = try XCTUnwrap(controls(of: wide)).pill.frame
        wide.setCollapsed(true, animated: false)
        wide.layoutSubtreeIfNeeded()
        let shut = try XCTUnwrap(controls(of: wide)).pill.frame
        XCTAssertEqual(shut.minX, open.minX, accuracy: 1)
        XCTAssertEqual(shut.width, open.width, accuracy: 1)
        XCTAssertLessThan(shut.height, open.height)
    }

    /// **The address does not travel between the two states**, at any width.
    /// Collapsing used to work the pill's place and its width out from scratch —
    /// centred in what was left of the bar, sized to the domain — so on a pane
    /// narrow enough to push the open pill off centre the address slid in from
    /// the side, and even centred its two edges still drew inwards as the glass
    /// faded. Neither edge moves now.
    func testCollapsingLeavesTheAddressWhereItWas() throws {
        for width in [CGFloat(1600), 420] {
            let bar = bar(width: width)
            let open = try XCTUnwrap(controls(of: bar)).pill.frame
            bar.setCollapsed(true, animated: false)
            bar.layoutSubtreeIfNeeded()
            let shut = try XCTUnwrap(controls(of: bar)).pill.frame
            XCTAssertEqual(shut.minX, open.minX, accuracy: 1, "\(width) pt: the pill moved sideways")
            XCTAssertEqual(shut.maxX, open.maxX, accuracy: 1, "\(width) pt: the pill changed width")
        }
    }

    /// **And the whole domain survives the collapse.** It did not: the capsule
    /// was sized to its own text, and a width a point short does not lose a
    /// pixel off the last letter — it drops characters until an ellipsis fits,
    /// which is what turned `apple.com` into `apple.c…`. The collapsed pill is
    /// the open pill's width now, and the open one has a glyph to clear that
    /// the collapsed one does not, so it has strictly more room than it needs.
    func testTheWholeAddressStillFitsWhenTheBarCollapses() throws {
        let wide = bar(width: 1600)
        wide.setCollapsed(true, animated: false)
        wide.layoutSubtreeIfNeeded()
        let pill = try XCTUnwrap(controls(of: wide)?.pill as? URLPillView)
        pill.layoutSubtreeIfNeeded()
        XCTAssertGreaterThanOrEqual(
            pill.field.frame.width,
            pill.field.intrinsicContentSize.width,
            "the domain is truncated in the collapsed bar"
        )
    }

    func testCollapsingTakesTheButtonsAwayRatherThanMovingThem() throws {
        let wide = bar(width: 1600)
        wide.setCollapsed(true, animated: false)
        wide.layoutSubtreeIfNeeded()
        let parts = try XCTUnwrap(controls(of: wide))
        XCTAssertTrue(parts.buttons.allSatisfy(\.isHidden))
    }

    /// §3.2b: a press on the collapsed address opens the bar rather than
    /// starting a whole URL inside a 22 pt capsule. The page is told about the
    /// room it gives up in the same breath, because the bar has grown.
    func testPressingTheCollapsedAddressOpensTheBar() throws {
        let wide = bar(width: 1600)
        wide.setCollapsed(true, animated: false)
        wide.layoutSubtreeIfNeeded()
        let pill = try XCTUnwrap(controls(of: wide)?.pill as? URLPillView)
        var band: [CGFloat] = []
        var began = 0
        wide.onBandHeight = { height, _ in band.append(height) }
        wide.onEditingBegan = { began += 1 }
        try press(pill)
        XCTAssertFalse(wide.isCollapsed)
        XCTAssertEqual(band, [Tokens.Metric.pageBar])
        XCTAssertEqual(began, 1)
    }

    /// And the end of it says which end it was. Return means a navigation is on
    /// its way and arriving opens the bar anyway; Esc means the bar goes back to
    /// wherever the page had it.
    func testTheEndOfEditingSaysWhetherItWasCommitted() throws {
        let wide = bar(width: 1600)
        let pill = try XCTUnwrap(controls(of: wide)?.pill as? URLPillView)
        let editor = NSTextView()
        var ends: [Bool] = []
        wide.onEditingEnded = { ends.append($0) }

        try press(pill)
        _ = pill.control(pill.field, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:)))
        try press(pill)
        _ = pill.control(pill.field, textView: editor, doCommandBy: #selector(NSResponder.cancelOperation(_:)))
        XCTAssertEqual(ends, [true, false])
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

    /// **Fullscreen takes the traffic lights out of the window and hands them
    /// back, and neither edge resizes this bar.** `placeControls` measures
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

    /// A collapsed bar is the page's own top edge with an address in it, and a
    /// control floating in that strip is the one thing on it that is not the
    /// site. The menu comes back the moment the page scrolls up.
    ///
    /// It fades rather than blinking out — §3.2b's two states are one dissolve
    /// — and is hidden at the end of the fade, because a view at alpha 0 goes
    /// on taking clicks.
    func testTheSiteMenuFadesAwayWithTheSurface() {
        let bare = pill(centred: true)
        bare.surface = .bare
        XCTAssertEqual(bare.siteMenuAnchor.alphaValue, 0)
        bare.settleGlyph()
        XCTAssertTrue(bare.siteMenuAnchor.isHidden)
        bare.surface = .glass
        XCTAssertFalse(bare.siteMenuAnchor.isHidden, "shown before it fades back in")
        XCTAssertEqual(bare.siteMenuAnchor.alphaValue, 1)
        bare.settleGlyph()
        XCTAssertFalse(bare.siteMenuAnchor.isHidden)
    }

    /// §3.2's pill puts the glyph on the trailing edge; §3.2b's puts it on the
    /// leading one, which is the only difference between them.
    func testTheGlyphSwapsEndsWithTheLayout() {
        XCTAssertGreaterThan(pill(centred: false).siteMenuAnchor.frame.midX, 200)
        XCTAssertLessThan(pill(centred: true).siteMenuAnchor.frame.midX, 200)
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

    /// Return takes the top suggestion without the user arrowing down to it
    /// first, which is the whole reason the list opens on a row rather than on
    /// what was typed.
    func testItOpensOnTheFirstSuggestion() {
        XCTAssertEqual(list().selectedPhrase, "swift")
    }

    func testDownWalksTheListAndUpComesBackOut() {
        let list = list()
        XCTAssertTrue(list.move(1))
        XCTAssertEqual(list.selectedPhrase, "swift concurrency")
        XCTAssertTrue(list.move(1))
        XCTAssertEqual(list.selectedPhrase, "swiftui")
        XCTAssertTrue(list.move(-1))
        XCTAssertEqual(list.selectedPhrase, "swift concurrency")
    }

    /// **What was typed stays reachable.** Opening on a suggestion must not
    /// mean a query can only be searched as the engine would rather have
    /// spelled it — ↑ off the top of the list is the way back to your own text.
    func testUpOffTheTopIsTheWayBackToWhatWasTyped() {
        let list = list()
        XCTAssertTrue(list.move(-1))
        XCTAssertNil(list.selectedPhrase)
    }

    /// Off the bottom is the typed text too — the same way out at either end.
    func testFallingOffTheEndReturnsToWhatWasTyped() {
        let list = list()
        for _ in 0..<2 { _ = list.move(1) }
        XCTAssertEqual(list.selectedPhrase, "swiftui")
        XCTAssertTrue(list.move(1))
        XCTAssertNil(list.selectedPhrase)
    }

    func testDownFromTheTypedTextLandsOnTheFirstRowAgain() {
        let list = list()
        _ = list.move(-1)
        XCTAssertNil(list.selectedPhrase)
        XCTAssertTrue(list.move(1))
        XCTAssertEqual(list.selectedPhrase, "swift")
    }

    /// The pill is the whole highlight. A second grey plate that lit under the
    /// pointer and then sat there was a second selection the keyboard could not
    /// move — which is what it looked like.
    func testARowPaintsNothingOfItsOwn() {
        let list = list()
        list.layoutSubtreeIfNeeded()
        for row in list.subviews.compactMap({ $0 as? PageBarSuggestionRow }) {
            row.displayIfNeeded()
            XCTAssertNil(row.layer?.backgroundColor)
        }
    }

    /// With nothing to walk through the field keeps the key, so the caret moves
    /// as it would in any other text field.
    func testAnEmptyListLeavesTheArrowKeysAlone() {
        let empty = list([])
        XCTAssertFalse(empty.move(1))
        XCTAssertFalse(empty.move(-1))
        XCTAssertTrue(empty.isHidden)
    }

    func testANewSetOfAnswersSelectsItsOwnFirstRow() {
        let list = list()
        _ = list.move(1)
        list.show(["something else"])
        XCTAssertEqual(list.selectedPhrase, "something else")
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
