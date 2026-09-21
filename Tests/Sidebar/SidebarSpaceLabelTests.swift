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

    /// A name that fits is drawn whole and costs no mask — see `applyFade`.
    func testANameShorterThanTheCapIsDrawnWhole() {
        let view = caption("Personal")
        XCTAssertEqual(clip(of: view).frame.width, ceil(width(ofText: "Personal")), accuracy: 1)
        XCTAssertNil(clip(of: view).layer?.mask)
    }

    /// And one that does not stops at the cap rather than at the column edge.
    func testALongNameStopsAtTheCapAndCarriesTheFade() {
        let view = caption(long)
        XCTAssertEqual(
            clip(of: view).frame.width,
            SidebarSpaceLabel.shownWidth(of: long),
            accuracy: 1
        )
        XCTAssertNotNil(clip(of: view).layer?.mask)
    }

    /// The promise the number is about: the ramp starts after the tenth
    /// character, so all ten of them are solid ink.
    func testTenCharactersAreSolidBeforeTheRampStarts() {
        let view = caption(long)
        guard let mask = clip(of: view).layer?.mask as? CAGradientLayer,
              let stop = mask.locations?[1] else {
            return XCTFail("§3.5's caption is not masked at \(long.count) characters")
        }
        let solid = mask.frame.width * CGFloat(truncating: stop)
        let ten = width(ofText: String(long.prefix(SidebarSpaceLabel.visibleCharacters)))
        XCTAssertGreaterThanOrEqual(solid, ten - 1)
    }

    // MARK: - The cap itself

    /// Characters, not points: the eleventh onwards costs nothing, and ten
    /// wide letters are allowed more room than ten narrow ones.
    func testTheCapCountsCharactersRatherThanWidth() {
        XCTAssertEqual(
            SidebarSpaceLabel.shownWidth(of: long),
            SidebarSpaceLabel.shownWidth(of: String(long.prefix(SidebarSpaceLabel.visibleCharacters)))
        )
        XCTAssertGreaterThan(
            SidebarSpaceLabel.shownWidth(of: "WWWWWWWWWW"),
            SidebarSpaceLabel.shownWidth(of: "iiiiiiiiii")
        )
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
