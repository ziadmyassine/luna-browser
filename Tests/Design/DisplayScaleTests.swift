//
//  DisplayScaleTests.swift
//  LunaTests
//
//  §7's 1× glass adaptation. Three things are worth a test and the rest is not:
//
//    1. `isOptimised(for:)` reads the **window's** scale factor and obeys the
//       override in both directions. The bug this guards against is the one
//       §7 names by hand — asking `NSScreen.main` instead, which gets the
//       right answer on a single-display machine and the wrong one the moment
//       a window is dragged.
//    2. Setting `Glass.optimisation` re-skins glass that is **already on
//       screen**, because the alternative is a setting that needs a relaunch.
//    3. `previewTile` is *pinned*: the Settings window shows both columns of
//       §7's table at once, on one display, so its tiles must not follow the
//       live setting the way every other glass view does.
//
//  All three are checked by reading `NSGlassEffectView.style` and `.tintColor`
//  back off the real view, not by trusting a mirror of the table.
//

import AppKit
import XCTest
@testable import Luna

@MainActor
final class DisplayScaleTests: XCTestCase {

    private var saved: GlassOptimisation = .auto

    override func setUp() {
        super.setUp()
        saved = Glass.optimisation
    }

    override func tearDown() {
        Glass.optimisation = saved
        super.tearDown()
    }

    // MARK: - Reading the glass back

    /// Every `NSGlassEffectView` under `view`, in tree order.
    private func glassViews(in view: NSView) -> [NSGlassEffectView] {
        (view as? NSGlassEffectView).map { [$0] } ?? view.subviews.flatMap(glassViews(in:))
    }

    private func firstGlass(in view: NSView, _ message: String = "") throws -> NSGlassEffectView {
        try XCTUnwrap(glassViews(in: view).first, "no NSGlassEffectView found \(message)")
    }

    private func makeWindow() -> NSWindow {
        NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 120),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
    }

    // MARK: - Detection

    func testOverridesIgnoreTheDisplayEntirely() {
        let window = makeWindow()
        Glass.optimisation = .on
        XCTAssertTrue(Glass.isOptimised(for: window))
        XCTAssertTrue(Glass.isOptimised(for: nil))
        Glass.optimisation = .off
        XCTAssertFalse(Glass.isOptimised(for: window))
        XCTAssertFalse(Glass.isOptimised(for: nil))
    }

    /// The whole point of §7's detection: the answer comes from the window's
    /// own screen, so it has to agree with that window's `backingScaleFactor`
    /// and not with anything app-wide.
    func testAutoFollowsTheWindowsOwnScaleFactor() {
        Glass.optimisation = .auto
        let window = makeWindow()
        XCTAssertEqual(Glass.isOptimised(for: window), window.backingScaleFactor < 2)
    }

    /// A view that has no window has no screen and therefore no scale. The
    /// conservative answer is the Retina one — a 2× user must never see the
    /// adaptation flicker past on the way to a window.
    func testAutoWithNoWindowIsNotOptimised() {
        Glass.optimisation = .auto
        XCTAssertFalse(Glass.isOptimised(for: nil))
    }

    func testSettingPersistsUnderTheSpecKey() {
        Glass.optimisation = .on
        XCTAssertEqual(UserDefaults.standard.string(forKey: "appearance.glassOptimisation"), "on")
        Glass.optimisation = .off
        XCTAssertEqual(UserDefaults.standard.string(forKey: "appearance.glassOptimisation"), "off")
    }

    // MARK: - The live re-skin

    /// §7's headline promise: flipping the setting re-skins the chrome that is
    /// already on screen. Checked on `.control`, which is the style the table
    /// changes most — `.clear` with no tint becomes `.regular` with one.
    func testFlippingTheSettingReSkinsGlassThatIsAlreadyOnScreen() throws {
        let window = makeWindow()
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 120))
        window.contentView = root
        let control = Glass.backing(.control, cornerRadius: Tokens.Metric.urlPill.cornerRadius)
        control.frame = root.bounds
        root.addSubview(control)
        window.orderFront(nil)
        defer { window.orderOut(nil) }

        Glass.optimisation = .off
        var glass = try firstGlass(in: control, "in the .off control")
        XCTAssertEqual(glass.style, .clear)
        XCTAssertNil(glass.tintColor)

        Glass.optimisation = .on
        glass = try firstGlass(in: control, "in the .on control")
        XCTAssertEqual(glass.style, .regular)
        XCTAssertNotNil(glass.tintColor, "§7 gives the 1× control the tint it does without at 2×")

        Glass.optimisation = .off
        glass = try firstGlass(in: control, "back at .off")
        XCTAssertEqual(glass.style, .clear, "the 2× rendering must come back exactly as it was")
        XCTAssertNil(glass.tintColor)
    }

    /// The chrome planes keep `.regular` in both columns — §7 changes only
    /// their tint, and a style change here would be a visible regression for
    /// every Retina user.
    func testSidebarKeepsItsStyleAndOnlyChangesTint() throws {
        let window = makeWindow()
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 120))
        window.contentView = root
        let bar = NSView(frame: root.bounds)
        Glass.apply(.sidebar, to: bar)
        root.addSubview(bar)
        window.orderFront(nil)
        defer { window.orderOut(nil) }

        Glass.optimisation = .off
        let plain = try firstGlass(in: bar).tintColor?.usingColorSpace(.sRGB)?.alphaComponent
        XCTAssertEqual(try firstGlass(in: bar).style, .regular)

        Glass.optimisation = .on
        let dense = try firstGlass(in: bar).tintColor?.usingColorSpace(.sRGB)?.alphaComponent
        XCTAssertEqual(try firstGlass(in: bar).style, .regular)

        let before = try XCTUnwrap(plain), after = try XCTUnwrap(dense)
        XCTAssertGreaterThan(after, before, "§7 thickens the 1× bar rather than thinning it")
    }

    // MARK: - The preview tile

    func testPreviewTileIsTheRequestedSizeAndDecorative() {
        let size = Tokens.Metric.glassPreviewTile.size
        let tile = Glass.previewTile(size: size, optimised: false)
        XCTAssertEqual(tile.frame.size, size)
        XCTAssertFalse(tile.isAccessibilityElement(), "§8: the tile is decorative")
    }

    /// It has to show the real difference, so the two tiles must actually
    /// differ — and in §7's terms, not merely somewhere.
    func testTheTwoPreviewTilesRenderDifferentMaterial() throws {
        let size = Tokens.Metric.glassPreviewTile.size
        let plain = glassViews(in: Glass.previewTile(size: size, optimised: false))
        let optimised = glassViews(in: Glass.previewTile(size: size, optimised: true))
        XCTAssertEqual(plain.count, 2, "a plane and a control")
        XCTAssertEqual(optimised.count, 2)

        XCTAssertEqual(plain[1].style, .clear)
        XCTAssertNil(plain[1].tintColor)
        XCTAssertEqual(optimised[1].style, .regular)
        XCTAssertNotNil(optimised[1].tintColor)

        let planeAlpha = try XCTUnwrap(plain[0].tintColor?.usingColorSpace(.sRGB)?.alphaComponent)
        let denseAlpha = try XCTUnwrap(optimised[0].tintColor?.usingColorSpace(.sRGB)?.alphaComponent)
        XCTAssertGreaterThan(denseAlpha, planeAlpha)
    }

    /// Pinned: the Settings window shows both columns side by side on one
    /// display, so the tiles must not follow the live setting.
    func testPreviewTilesDoNotFollowTheLiveSetting() throws {
        let size = Tokens.Metric.glassPreviewTile.size
        Glass.optimisation = .off
        let tile = Glass.previewTile(size: size, optimised: true)
        let window = makeWindow()
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 120))
        window.contentView = root
        root.addSubview(tile)
        window.orderFront(nil)
        defer { window.orderOut(nil) }

        Glass.optimisation = .on
        Glass.optimisation = .off
        let control = try XCTUnwrap(glassViews(in: tile).last)
        XCTAssertEqual(control.style, .regular, "a pinned tile ignores the live setting")
        XCTAssertNotNil(control.tintColor)
    }

    // MARK: - Tokens

    /// §7's ordering, the one claim the table makes about magnitude. The full
    /// derivation is re-run by `TokenCheck`; this is the version that fails a
    /// test run rather than a debug assertion.
    func testGlassTintOrdering() {
        for contrast in [false, true] {
            for isDark in [false, true] {
                let plain = Tokens.Ink.glassTint.alpha(contrast: contrast, dark: isDark)
                let dense = Tokens.Ink.glassTintDense.alpha(contrast: contrast, dark: isDark)
                let control = Tokens.Ink.glassTintControl.alpha(contrast: contrast, dark: isDark)
                XCTAssertLessThan(control, plain)
                XCTAssertGreaterThan(dense, plain)
                XCTAssertLessThan(dense, 1, "a tint that reaches opacity is a plane, not glass")
            }
        }
    }

    func testTokenCheckStillPasses() {
        XCTAssertEqual(TokenCheck.failures(), [])
    }
}
