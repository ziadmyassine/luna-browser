//
//  URLPillLayoutTests.swift
//  LunaTests
//
//  §3.2's pill on both surfaces — a row of a column and a capsule on a bar —
//  and the list of completions that hangs off the second one.
//
//  Split out of `PageChromeBarTests.swift`, which is about the *bar*: what it
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

    /// **13 in a column, 16 on a bar.** `glyphSize` is the size of a glyph that
    /// is its own button, which is what these two are among four controls on
    /// §3.2b's bar. In a 200 pt column beside 13 pt text, 16 was the loudest
    /// thing in the pill.
    func testTheGlyphsAreSizedToThePillTheyAreIn() {
        XCTAssertEqual(pill(centred: false).glyphInk, Tokens.Metric.pillGlyphSize)
        XCTAssertEqual(pill(centred: true).glyphInk, Tokens.Metric.glyphSize)
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

    /// **A pill that hands off never opens.** There is nowhere in a 200 pt
    /// column to put a list of completions, and §9.1 already has the field, the
    /// history and the ranking — so the click and the `⌘L` go there instead.
    func testAPillThatHandsOffDoesNotOpenForEditing() throws {
        let column = pill(centred: false)
        var handOffs = 0
        column.onHandOff = { handOffs += 1 }

        column.beginEditing()
        XCTAssertEqual(handOffs, 1)
        XCTAssertFalse(column.isEditing, "the pill opened as well as handing off")
        XCTAssertFalse(column.field.isEditable)
    }

    /// And §3.2b's still does, because it has a list of its own hanging off it.
    func testThePageBarsPillStillEditsInPlace() {
        let capsule = pill(centred: true)
        capsule.beginEditing()
        XCTAssertTrue(capsule.isEditing)
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

    /// §3.2's column pill is barely 200 pt wide and the long line truncates in
    /// it, which says less than the short one does.
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

/// §3.4's completions under §3.2b's pill, as geometry.
///
/// They are the same rows §9.1 shows for the same query, so they have to be
/// drawn the same way. These were laid out on §3.4's tab-row numbers —
/// `rowFaviconInset` and `rowTitleInset`, derived from the tab pill's height
/// and carrying §3.4's own 9 pt icon gap — and the two lists sat a point and a
/// half apart from each other on screen.
@MainActor
final class PageBarSuggestionRowTests: XCTestCase {

    private func row() -> PageBarSuggestionRow {
        let row = PageBarSuggestionRow(phrase: "what is my ip")
        row.frame = NSRect(x: 0, y: 0, width: 420, height: Tokens.Metric.rowHeight)
        row.layoutSubtreeIfNeeded()
        return row
    }

    private func parts(_ row: PageBarSuggestionRow) -> (glyph: NSView, label: NSView)? {
        let views = row.subviews
        guard views.count == 2 else { return nil }
        return (views[0], views[1])
    }

    func testTheIconStartsWhereTheCommandBarsDoes() throws {
        let parts = try XCTUnwrap(parts(row()))
        XCTAssertEqual(parts.glyph.frame.minX, Tokens.Metric.rowInset + Tokens.Metric.panelInset)
        XCTAssertEqual(parts.glyph.frame.width, Tokens.Metric.faviconSize)
    }

    /// One `panelInset` after the icon — the spacing `CommandBarResultRow`'s
    /// stack view uses, and not §3.4's tighter tab-row gap.
    func testTheTextClearsTheIconByTheCommandBarsGap() throws {
        let parts = try XCTUnwrap(parts(row()))
        XCTAssertEqual(parts.label.frame.minX - parts.glyph.frame.maxX, Tokens.Metric.panelInset)
    }
}
