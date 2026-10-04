//
//  EmptyPaneViewTests.swift
//  LunaTests
//
//  The empty pane's painting: shipped in both appearances, placed the way an
//  error page places its own, and the sky the page bar wears over it.
//

import AppKit
import XCTest
@testable import Luna

@MainActor
final class EmptyPaneViewTests: XCTestCase {

    /// The bar over an empty pane wears these, so both have to be there and
    /// be the day's pale sky and the night's dark one.
    func testBothPaintingsShipWithTheirSky() throws {
        let day = try XCTUnwrap(EmptyPaneView.sky(dark: false))
        let night = try XCTUnwrap(EmptyPaneView.sky(dark: true))
        XCTAssertGreaterThan((day.r + day.g + day.b) / 3, 0.75)
        XCTAssertLessThan((night.r + night.g + night.b) / 3, 0.25)
    }

    /// Covering the pane, on its bottom edge, and cropped a quarter from the
    /// left: the error pages' `cover`, `25% bottom`.
    func testThePaintingCoversThePaneFromItsBottomEdge() throws {
        let pane = EmptyPaneView(frame: NSRect(x: 0, y: 0, width: 600, height: 900))
        pane.appearance = NSAppearance(named: .aqua)
        pane.layoutSubtreeIfNeeded()
        pane.layout()
        let frame = pane.painting.frame
        XCTAssertNotNil(pane.painting.contents)
        XCTAssertEqual(frame.minY, 0)
        XCTAssertEqual(frame.height, 900, accuracy: 0.5)
        XCTAssertGreaterThan(frame.width, 600)
        XCTAssertEqual(frame.minX, (600 - frame.width) * EmptyPaneView.horizontalAnchor, accuracy: 0.5)
    }

    /// The line under the headline names New Tab's shortcut as it is bound
    /// now, and the headline is not cut short at a laptop's width.
    func testTheWordsNameTheNewTabShortcutAndFit() throws {
        let pane = EmptyPaneView(frame: NSRect(x: 0, y: 0, width: 1280, height: 800))
        pane.layoutSubtreeIfNeeded()
        pane.layout()
        let shortcut = try XCTUnwrap(KeyBindings.primary(for: .newTab)?.display)
        XCTAssertTrue(pane.hint.stringValue.contains(shortcut), pane.hint.stringValue)
        let headline = pane.headline
        let needed = headline.cell?.cellSize(forBounds: CGRect(x: 0, y: 0, width: 10_000, height: 10_000)).width ?? 0
        XCTAssertGreaterThanOrEqual(headline.frame.width + 0.5, needed)
    }
}
