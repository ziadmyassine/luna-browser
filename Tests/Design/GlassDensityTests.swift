//
//  GlassDensityTests.swift
//  LunaTests
//
//  §2a's Clear / Opaque setting. Three things are worth a test:
//
//    1. The table. `.sidebar` and `.topBar` change plane with the setting, the
//       popover *gains* one at `.opaque` and has none at `.clear`, and a control
//       never gets one at either — a frosted control reads as a hole rather
//       than as something raised (§2).
//    2. The setting re-skins glass that is **already on screen**, because the
//       alternative is a preference that needs a relaunch. This is the same
//       requirement §7's setting has, and the pass is a different one.
//    3. The alphas stay short of opacity. `TokenCheck` owns that rule; this
//       calls it, so a nudge to `Ink.frostOpaque` fails here rather than in a
//       debug assertion nobody is running.
//
//  The plane is read back off the real `CALayer`, not off a mirror of the table.
//

import AppKit
import XCTest
@testable import Luna

@MainActor
final class GlassDensityTests: XCTestCase {

    private var saved: GlassDensity = .clear

    override func setUp() {
        super.setUp()
        saved = Glass.density
    }

    override func tearDown() {
        Glass.density = saved
        super.tearDown()
    }

    // MARK: - The table

    func testTheChromePlanesThickenAndStayTranslucent() {
        for style in [Glass.Style.sidebar, .topBar] {
            let clear = try? XCTUnwrap(style.frost(.clear))
            let opaque = try? XCTUnwrap(style.frost(.opaque))
            guard let clear, let opaque else { return XCTFail("\(style) has no frost at one density") }
            XCTAssertGreaterThan(opaque.alphaComponent, clear.alphaComponent, "\(style)")
            XCTAssertLessThan(opaque.alphaComponent, 1, "\(style) — an opaque frost is not glass any more")
        }
    }

    /// The popover takes the material neat at `.clear`, which is what §2 has
    /// always said it does, and gains a plane only when the user asks for one.
    func testThePopoverGainsItsPlaneOnlyWhenOpaque() {
        XCTAssertNil(Glass.Style.popover.frost(.clear))
        XCTAssertNotNil(Glass.Style.popover.frost(.opaque))
    }

    func testAControlIsNeverFrosted() {
        XCTAssertNil(Glass.Style.control.frost(.clear))
        XCTAssertNil(Glass.Style.control.frost(.opaque))
    }

    // MARK: - Re-skinning what is already on screen

    func testChangingTheDensityRepaintsALiveSurface() throws {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 120),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        let host = NSView(frame: window.contentLayoutRect)
        window.contentView = host
        Glass.density = .clear
        Glass.apply(.sidebar, to: host)

        let before = try plane(under: host)
        Glass.density = .opaque
        let after = try plane(under: host)

        XCTAssertNotEqual(before, after, "the setting did not reach a surface that was already up")
        XCTAssertGreaterThan(after.alphaComponent, before.alphaComponent)
    }

    /// The whole reason the setting is worth having a key: it survives the
    /// launch that reads it back.
    func testTheSettingPersists() {
        Glass.density = .opaque
        XCTAssertEqual(UserDefaults.standard.string(forKey: GlassDefaults.densityKey), GlassDensity.opaque.rawValue)
        Glass.density = .clear
        XCTAssertEqual(UserDefaults.standard.string(forKey: GlassDefaults.densityKey), GlassDensity.clear.rawValue)
    }

    // MARK: - The alphas

    func testTheDesignSystemStillHolds() {
        XCTAssertEqual(TokenCheck.checkGlassDensity(), [])
    }

    // MARK: - Helpers

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
