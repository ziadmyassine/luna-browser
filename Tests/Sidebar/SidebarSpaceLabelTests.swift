//
//  SidebarSpaceLabelTests.swift
//  LunaTests
//
//  §3.5's caption reads the head of a name and fades the rest, which is two
//  promises: ten characters are legible, and the line never runs into the
//  column's insets however long the name is.
//
//  The name it was reported on is in here verbatim — 32 characters of one
//  repeated pair, which is the worst case the §6.2 cap allows and the case
//  that made the line run edge to edge.
//

import AppKit
import XCTest
@testable import Luna

@MainActor
final class SidebarSpaceLabelTests: XCTestCase {

    /// The reported name: `spaceNameCap` characters, no word to break on.
    private let long = "yoyooyoyoyoyyoyooyoyoyoyooyoyoyo"

    private func caption(_ name: String?, width: CGFloat = 280) -> SidebarSpaceLabel {
        let view = SidebarSpaceLabel()
        view.frame = NSRect(x: 0, y: 0, width: width, height: Tokens.Metric.sidebarSpaceNameRow)
        view.show(spaceName: name)
        view.layoutSubtreeIfNeeded()
        return view
    }

    /// The clipping box, which is the only subview.
    private func clip(of view: SidebarSpaceLabel) -> NSView {
        view.subviews[0]
    }

    private func width(ofText text: String) -> CGFloat {
        NSAttributedString(string: text, attributes: [.font: Tokens.TypeScale.settingsCaption]).size().width
    }

    // MARK: - What is drawn

    /// The one that got away: a box cut to what the field reports is 4 pt
    /// short of what the field draws, because the cell keeps 2 pt either side
    /// and counts neither. "Personal" fitted the column twice over and still
    /// came out "Persona".
    func testAShortNameKeepsItsLastLetterOutOfTheCellsPadding() {
        let view = caption("Personal")
        let pad = SidebarSpaceLabel.padding(of: view.label)
        XCTAssertGreaterThan(pad, 0, "the cell has stopped padding — the offset in placeContents is now a shift")
        // Leading glyph on the box's leading edge, trailing glyph inside its
        // trailing one. Both are measured against the text, not the field.
        XCTAssertEqual(view.label.frame.minX + pad, 0, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(
            view.label.frame.maxX - pad,
            clip(of: view).frame.width - 0.5,
            "the last letter is drawn outside the box that keeps it"
        )
    }

    /// A name that fits is drawn whole and costs no mask — see `applyFade`.
    func testANameShorterThanTheCapIsDrawnWhole() {
        let view = caption("Personal")
        XCTAssertEqual(clip(of: view).frame.width, ceil(width(ofText: "Personal")), accuracy: 1)
        XCTAssertNil(clip(of: view).layer?.mask)
    }

    /// And one that does not stops at the cap rather than at the column edge.
    func testALongNameStopsAtTheCapAndCarriesTheFade() {
        let view = caption(long, width: 280)
        XCTAssertEqual(
            clip(of: view).frame.width,
            SidebarSpaceLabel.shownWidth(inColumnOfWidth: 280),
            accuracy: 1
        )
        XCTAssertNotNil(clip(of: view).layer?.mask)
    }

    /// The dissolve begins inside the cap rather than after it. At a ramp the
    /// width of a row's, the last glyph read as a letter that had been cut;
    /// `sidebarSpaceNameFade` starts it about two characters early so the tail
    /// thins instead of stopping.
    func testTheRampStartsBeforeTheCapRatherThanAfterIt() {
        let view = caption(long)
        guard let mask = clip(of: view).layer?.mask as? CAGradientLayer,
              let stop = mask.locations?[1] else {
            return XCTFail("§3.5's caption is not masked at \(long.count) characters")
        }
        let solid = mask.frame.width * CGFloat(truncating: stop)
        let cap = SidebarSpaceLabel.allowance(inColumnOfWidth: 280)
        XCTAssertLessThan(solid, cap, "the ramp starts at the cap or past it")
        // And not so early that the cap stops meaning anything: most of what
        // the column allows is still solid ink.
        XCTAssertGreaterThan(solid, cap / 2)
    }

    // MARK: - The cap itself

    /// The floor the whole rule is set from: in the narrowest column Luna can
    /// be dragged to, the name it ships with fits and nothing longer does.
    func testAtTheFloorTheCapIsTheNameLunaShipsWith() {
        let floor = Tokens.Metric.sidebarFootFloor
        XCTAssertEqual(
            SidebarSpaceLabel.allowance(inColumnOfWidth: floor),
            ceil(width(ofText: SidebarSpaceLabel.narrowestName)),
            accuracy: 0.5
        )
        let view = caption(SidebarSpaceLabel.narrowestName, width: floor)
        XCTAssertNil(clip(of: view).layer?.mask, "the name Luna ships with does not fit its own column")
    }

    /// And a point of column buys a point of name, all the way out to §1's
    /// ceiling. A fixed cap showed as much in a 420 pt column as in a 220 pt
    /// one, with the rest of the line empty either side of it.
    func testTheCapGrowsPointForPointWithTheColumn() {
        let floor = Tokens.Metric.sidebarFootFloor
        let base = SidebarSpaceLabel.allowance(inColumnOfWidth: floor)
        for wider in [floor + 30, floor + 60, Tokens.Metric.sidebarWidth.max] {
            XCTAssertEqual(
                SidebarSpaceLabel.allowance(inColumnOfWidth: wider),
                base + (wider - floor),
                accuracy: 0.5,
                "\(wider)"
            )
        }
    }

    /// A column narrower than the floor cannot buy negative name. §1 does not
    /// allow one, and arithmetic that goes backwards there would hand the box
    /// a width smaller than the ramp drawn in it.
    func testANarrowerColumnThanTheFloorNeverShrinksTheCapBelowIt() {
        let floor = Tokens.Metric.sidebarFootFloor
        XCTAssertEqual(
            SidebarSpaceLabel.allowance(inColumnOfWidth: floor - 40),
            SidebarSpaceLabel.allowance(inColumnOfWidth: floor)
        )
    }

    /// The line grows on screen, not only in the arithmetic.
    func testAWiderColumnDrawsMoreOfTheName() {
        let narrow = clip(of: caption(long, width: Tokens.Metric.sidebarFootFloor)).frame.width
        let wide = clip(of: caption(long, width: Tokens.Metric.sidebarFootFloor + 90)).frame.width
        XCTAssertGreaterThan(wide, narrow)
    }

    // MARK: - Where it sits

    /// Clipped or whole, the box is centred over the strip it captions.
    func testTheNameStaysCentredEitherWay() {
        for name in ["Personal", long] {
            let view = caption(name)
            XCTAssertEqual(clip(of: view).frame.midX, view.bounds.midX, accuracy: 1, name)
        }
    }

    /// The cap is what usually ends the line, but a column narrow enough that
    /// ten characters do not fit in it still keeps §3's inset.
    func testTheNameNeverCrossesTheColumnsInset() {
        let inset = Tokens.Metric.rowInset
        for width in [Tokens.Metric.sidebarFootFloor, 120, 60] as [CGFloat] {
            let view = caption(long, width: width)
            XCTAssertGreaterThanOrEqual(clip(of: view).frame.minX, inset - 1, "\(width)")
            XCTAssertLessThanOrEqual(clip(of: view).frame.maxX, width - inset + 1, "\(width)")
        }
    }

    /// No name, no line — the strip below keeps the air the row would take.
    func testTheLineDisappearsWithoutAName() {
        XCTAssertTrue(caption(nil).isHidden)
        XCTAssertTrue(caption("").isHidden)
        XCTAssertFalse(caption("Personal").isHidden)
    }
}
