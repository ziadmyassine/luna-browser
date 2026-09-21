//
//  URLPillLayoutTests.swift
//  LunaTests
//
//  §3.2's pill on both surfaces — a row of a column and a capsule on a bar.
//
//  Split out of `PageChromeBarTests.swift`, which is about the bar: what it
//  holds, where it puts it and which part of it takes a click. What is inside
//  the pill is the pill's, on whichever surface it is standing.
//

import XCTest
@testable import BrowserKit
@testable import Luna

@MainActor
final class URLPillLayoutTests: XCTestCase {

    /// `centred` is §3.2b's capsule, which is also the one that carries a
    /// reload — the bar wires `onReload` when it builds it, and which end the
    /// sliders glyph takes depends on whether there is one.
    private func pill(centred: Bool) -> URLPillView {
        let pill = URLPillView()
        pill.centresText = centred
        if centred { pill.onReload = { _ in } }
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
        let bare = pill(centred: false)
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

    /// **One affordance goes on the trailing edge; a second one takes the
    /// other end.** That is where §3.2 has always drawn the sliders and where
    /// §3.4's rows draw theirs — so a pill with no reload keeps it there, and
    /// only a pill that carries both moves site settings to the front.
    func testTheSlidersTakesTheTrailingEdgeUntilReloadWantsIt() {
        let column = pill(centred: false)
        XCTAssertTrue(column.reload.isHidden, "a column pill has its reload on the row above")
        XCTAssertGreaterThan(column.sliders.frame.midX, column.field.frame.maxX)

        let capsule = pill(centred: true)
        XCTAssertLessThan(capsule.sliders.frame.midX, capsule.field.frame.minX)
        XCTAssertGreaterThan(capsule.reload.frame.midX, capsule.field.frame.maxX)
        XCTAssertEqual(
            capsule.sliders.frame.midX - capsule.bounds.minX,
            capsule.bounds.maxX - capsule.reload.frame.midX,
            accuracy: 1,
            "the capsule's two glyphs are not the same distance from their own ends"
        )
    }

    /// And the address keeps the line the glyph is not on: a column pill reads
    /// from its leading edge at §3.2's own inset, with only the trailing glyph
    /// to clear.
    func testTheColumnAddressStartsAtTheLeadingInset() {
        XCTAssertEqual(pill(centred: false).field.frame.minX, Tokens.Metric.pillTextInset)
    }

    /// Reload is there only for a pill that has somewhere to send it. §4's top
    /// bar has its own reload button beside the pill, and two would be two.
    func testAPillWithNowhereToSendAReloadDoesNotShowOne() {
        let bare = URLPillView()
        XCTAssertTrue(bare.reload.isHidden)
        bare.onReload = { _ in }
        XCTAssertFalse(bare.reload.isHidden)
    }

    /// 13 in a column, 14 on a bar, and 16 nowhere. `glyphSize` is the size
    /// of a glyph that is its own button, which is what the controls beside
    /// §3.2b's pill are — but a glyph inside a capsule is measured against the
    /// address it shares the capsule with, and at 16 it was the loudest mark on
    /// the bar. The column takes the step further for the same reason.
    func testTheGlyphsAreSizedToThePillTheyAreIn() {
        XCTAssertEqual(pill(centred: false).glyphInk, Tokens.Metric.pillGlyphSize)
        XCTAssertEqual(pill(centred: true).glyphInk, Tokens.Metric.barPillGlyphSize)
        XCTAssertLessThan(Tokens.Metric.barPillGlyphSize, Tokens.Metric.glyphSize)
    }

    /// And it stands as far in as the address does, on both pills.
    ///
    /// The column's glyph used to sit two points closer to its own end than the
    /// text did, on the argument that a glyph is optically smaller than its
    /// box. On §3.2b's 420 pt capsule that reads as intended; in a 240 pt
    /// column, with the capsule's corner curving away right behind it, it reads
    /// as site settings falling off the end of the pill.
    func testTheGlyphStandsAsFarInAsTheAddressDoes() {
        let column = pill(centred: false)
        XCTAssertEqual(
            column.bounds.maxX - inkEdge(of: column.sliders, in: column, leading: false),
            Tokens.Metric.pillTextInset,
            accuracy: 0.5
        )
        let capsule = pill(centred: true)
        XCTAssertEqual(
            inkEdge(of: capsule.sliders, in: capsule, leading: true) - capsule.bounds.minX,
            Tokens.Metric.pillTextInset,
            accuracy: 0.5
        )
    }

    /// Where the mark ends, not where its hit box does: the box is the ink
    /// plus a gap's worth of padding, and it is the ink the eye measures.
    private func inkEdge(of glyph: NSView, in pill: URLPillView, leading: Bool) -> CGFloat {
        let overhang = (glyph.frame.width - pill.glyphInk) / 2
        return leading ? glyph.frame.minX + overhang : glyph.frame.maxX - overhang
    }

    /// And both fit inside the pill they are in, at both sizes: a hit target
    /// hanging off the end of a capsule takes clicks meant for what is beside
    /// it.
    func testNeitherGlyphHangsOffTheEndOfThePill() {
        for centred in [false, true] {
            let pill = pill(centred: centred)
            for glyph in [pill.sliders, pill.reload] {
                XCTAssertTrue(
                    pill.bounds.contains(glyph.frame),
                    "centred: \(centred) — a glyph's box is outside the pill"
                )
            }
        }
    }

    /// Neither pill is a field. A click and a `⌘L` both go to §9.1, on both
    /// surfaces: that is where the field, the history, the ranking, the
    /// autofill and the list already are, and two address bars offering two
    /// different sets of suggestions was the thing this replaced.
    func testBothSurfacesHandTheAddressToTheCommandBar() {
        for centred in [false, true] {
            let bar = pill(centred: centred)
            var handOffs = 0
            bar.onHandOff = { handOffs += 1 }

            bar.handOff()
            XCTAssertEqual(handOffs, 1, "centred: \(centred)")
            XCTAssertFalse(bar.field.isEditable, "centred: \(centred) — the pill opened for typing")
        }
    }

    /// And a press on the pill is that same hand-off, not a selection or a
    /// caret: the whole capsule is the button.
    func testAClickOnThePillIsTheHandOff() {
        let bar = pill(centred: false)
        var handOffs = 0
        bar.onHandOff = { handOffs += 1 }
        bar.mouseDown(with: NSEvent())
        XCTAssertEqual(handOffs, 1)
    }

    /// A tab with no site in it reads as what the bar is for, not as the name
    /// of a page you are on.
    func testANewTabShowsThePlaceholderRatherThanAName() {
        let bar = URLPillView()
        bar.show(url: URL(string: "luna://newtab"))
        XCTAssertEqual(bar.field.stringValue, "")
        bar.centresText = true
        XCTAssertEqual(bar.field.placeholderString, "Search or enter website name")
    }

    /// §3.2's column pill starts at 244 pt of glass and the long line truncates
    /// in it, which says less than the short one does.
    func testTheColumnPillSaysTheShortVersion() {
        XCTAssertEqual(URLPillView().field.placeholderString, "Search the web")
    }

    /// Luna's other internal pages are somewhere you actually are, so they keep
    /// their names.
    func testLunasOtherPagesKeepTheirNames() {
        let bar = URLPillView()
        bar.show(url: URL(string: "luna://archive"))
        XCTAssertEqual(bar.field.stringValue, "History")
    }
}
