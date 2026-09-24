//
//  GlassFrostTests.swift
//  LunaTests
//
//  §2's frost: the plane painted behind the chrome's glass. Two things are
//  worth a test — which surfaces get it, and what stands in for the glass
//  under Reduce Transparency, which every CI runner has on.
//
//  The plane is read back off the real `CALayer`, not off a mirror of the table.
//

import AppKit
import XCTest
@testable import Luna

@MainActor
final class GlassFrostTests: XCTestCase {

    func testTheChromePlanesAreFrostedAndStayTranslucent() throws {
        for style in [Glass.Style.sidebar, .topBar] {
            let frost = try XCTUnwrap(style.frost, "\(style) has no frost")
            XCTAssertLessThan(frost.alphaComponent, 1, "\(style) — an opaque frost is not glass any more")
        }
    }

    /// A popover takes the material neat, and a frosted control reads as a
    /// hole rather than as something raised (§2).
    func testPopoversAndControlsAreNotFrosted() {
        XCTAssertNil(Glass.Style.popover.frost)
        XCTAssertNil(Glass.Style.control.frost)
    }

    func testALiveChromePlanePaintsTheFrost() throws {
        try XCTSkipIf(Tokens.A11y.reduceTransparency, "Reduce Transparency: §21.2 draws a plane, not glass")
        let plane = try plane(under: host(.sidebar))
        XCTAssertGreaterThan(plane.alphaComponent, 0)
        XCTAssertLessThan(plane.alphaComponent, 1)
    }

    /// With Reduce Transparency on there is no glass to paint behind, so
    /// §21.2's plane replaces the material, at full strength.
    func testReduceTransparencyLeavesASolidPlane() throws {
        try XCTSkipUnless(Tokens.A11y.reduceTransparency, "there is glass on this host — the test above covers it")
        let plane = try plane(under: host(.sidebar))
        XCTAssertEqual(plane.alphaComponent, 1, "§21.2's fallback is a plane, not a wash over something")
    }

    // MARK: - Helpers

    private func host(_ style: Glass.Style) -> NSView {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 120),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        let host = NSView(frame: window.contentLayoutRect)
        window.contentView = host
        Glass.apply(style, to: host)
        return host
    }

    /// The plane a backing is painting behind its glass, read off the layer
    /// after the pass that would draw it.
    private func plane(under host: NSView) throws -> NSColor {
        let backing = try XCTUnwrap(
            host.subviews.compactMap { $0 as? GlassBackingView }.first,
            "Glass.apply put no backing under the host"
        )
        backing.layer?.displayIfNeeded()
        let colour = try XCTUnwrap(backing.layer?.backgroundColor, "the backing painted no plane at all")
        return try XCTUnwrap(NSColor(cgColor: colour))
    }
}
