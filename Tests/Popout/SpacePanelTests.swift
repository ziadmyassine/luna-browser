//
//  SpacePanelTests.swift
//  LunaTests
//
//  §3.5's and §4's Space pop-out: its Spaces go where they say, the one the
//  window is in is ticked, and its colours are the palette and No Colour.
//

import AppKit
import BrowserKit
import XCTest
@testable import Luna

@MainActor
final class SpacePanelTests: XCTestCase {

    private let spaces = [
        Space(name: "Personal", symbolName: "person", gradient: Tokens.Gradient.spacePalette[0]),
        Space(name: "Work", symbolName: "briefcase", gradient: Tokens.Gradient.spacePalette[1])
    ]

    func testItListsTheSpacesTicksTheActiveOneAndGoesWhereItSays() {
        var went: UUID?
        var closed = false
        let panel = SpacePanel(frame: NSRect(x: 0, y: 0, width: 1000, height: 900), edge: .above, content: SpacePanelContent(
            spaces: spaces, activeID: spaces[0].id, switchTo: { went = $0 }, setGradient: { _, _ in }, edit: {}, new: {}
        ))
        panel.onDone = { closed = true }
        panel.layoutSubtreeIfNeeded()
        XCTAssertEqual(panel.rows.filter(\.isChecked).map { $0.accessibilityLabel() }, ["Personal"])
        panel.rows[1].choose()
        XCTAssertEqual(went, spaces[1].id)
        XCTAssertTrue(closed, "the pop-out stayed up after the switch")
        XCTAssertEqual(panel.body.frame.height, SpacePanelMetrics.height(spaces: 2, swatches: panel.swatches.count), accuracy: 0.5)
    }

    func testItsColoursAreThePaletteAndNoColourWithTheSpacesOwnRinged() {
        var set: GradientPair?
        let panel = SpacePanel(frame: NSRect(x: 0, y: 0, width: 1000, height: 900), edge: .above, content: SpacePanelContent(
            spaces: spaces, activeID: spaces[1].id, switchTo: { _ in }, setGradient: { _, gradient in set = gradient }, edit: {}, new: {}
        ))
        XCTAssertEqual(panel.swatches.count, Tokens.Gradient.spacePalette.count + 1)
        XCTAssertEqual(panel.swatches.filter(\.isChosen).count, 1)
        panel.swatches[3].onActivate?()
        XCTAssertEqual(set, Tokens.Gradient.spacePalette[3])
        XCTAssertTrue(panel.swatches[3].isChosen)
        XCTAssertEqual(panel.swatches.filter(\.isChosen).count, 1, "two swatches ringed at once")
    }

    /// In the sidebar the pop-out lines its leading edge up with the control
    /// it came out of — the Space pill, the search bar — instead of centring
    /// on it, and it never leaves the window.
    func testALinedUpPopoutSharesItsControlsLeadingEdge() {
        let panel = SpacePanel(frame: NSRect(x: 0, y: 0, width: 1000, height: 900), edge: .above, content: SpacePanelContent(
            spaces: spaces, activeID: spaces[0].id, switchTo: { _ in }, setGradient: { _, _ in }, edit: {}, new: {}
        ))
        panel.anchorRect = { NSRect(x: 60, y: 20, width: 90, height: 34) }
        panel.leadingEdge = { 60 }
        panel.layoutSubtreeIfNeeded()
        XCTAssertEqual(panel.body.frame.minX, 60)

        // The sidebar's controls stand nearer the window's side than the
        // pop-out's own clamp; the edge is still the control's.
        panel.leadingEdge = { Tokens.Metric.chromeGap }
        panel.needsLayout = true
        panel.layoutSubtreeIfNeeded()
        XCTAssertEqual(panel.body.frame.minX, Tokens.Metric.chromeGap, "the window clamp pushed it off the control's edge")

        panel.leadingEdge = { -40 }
        panel.needsLayout = true
        panel.layoutSubtreeIfNeeded()
        XCTAssertEqual(panel.body.frame.minX, 0, "it left the window")
    }

    /// A pop-out standing over the sidebar's divider takes the resize cursor
    /// away with it: the window's cursor rects ignore what is drawn on top.
    func testAPopoutOverTheDividerHidesTheResizeCursor() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 900),
            styleMask: [.borderless],
            backing: .buffered,
            defer: true
        )
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 1000, height: 900))
        window.contentView = root
        let handle = SidebarResizeHandle(frame: NSRect(x: 276, y: 0, width: 8, height: 900))
        root.addSubview(handle)
        XCTAssertFalse(handle.isCovered)

        let panel = SpacePanel(frame: root.bounds, edge: .above, content: SpacePanelContent(
            spaces: spaces, activeID: spaces[0].id, switchTo: { _ in }, setGradient: { _, _ in }, edit: {}, new: {}
        ))
        root.addSubview(panel)
        XCTAssertTrue(handle.isCovered)
        panel.removeFromSuperview()
        XCTAssertFalse(handle.isCovered)
    }
}
