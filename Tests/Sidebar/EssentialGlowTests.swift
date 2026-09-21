//
//  EssentialGlowTests.swift
//  LunaTests
//
//  §3.3's selection glow, in the two halves that can be wrong without anyone
//  noticing on screen.
//
//  The colour, because it fails quietly: a weighting that let the black in
//  X's mark outvote the red dot would still produce a glow, just the wrong one,
//  and "the light is a slightly different grey than it should be" is not
//  something a person reports. The pictures below are the reference's cases
//  written down — a mark with one saturated patch, a mark with none, and a mark
//  too dark to emit.
//
//  The wiring, because the glow lies over the tiles and only one of them
//  at a time: over is what lets the colour reach the glass, and it is also the
//  arrangement in which a missing `hitTest` override swallows every click on
//  the pinned tab you are on.
//

import BrowserKit
import XCTest
@testable import Luna

@MainActor
final class FaviconTintTests: XCTestCase {

    /// A 32 pt icon painted by `body`, which is what a favicon arrives as.
    private func icon(_ body: @escaping (NSRect) -> Void) -> NSImage {
        NSImage(size: NSSize(width: 32, height: 32), flipped: false) { rect in
            body(rect)
            return true
        }
    }

    private func components(_ colour: NSColor) -> (
        hue: CGFloat, saturation: CGFloat, brightness: CGFloat
    ) {
        let srgb = colour.usingColorSpace(.sRGB) ?? colour
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 1
        srgb.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return (hue, saturation, brightness)
    }

    /// The reference case. X's mark is black and white with one red
    /// notification dot on it, and the glow it has to produce is red. A plain
    /// average of those pixels is a grey; only weighting by chroma gets the
    /// answer the eye gives.
    func testOneSaturatedPatchDecidesTheColour() {
        let mark = icon { rect in
            NSColor.black.setFill()
            rect.fill()
            NSColor(srgbRed: 0.9, green: 0.1, blue: 0.1, alpha: 1).setFill()
            NSRect(x: 22, y: 22, width: 8, height: 8).fill()
        }
        let glow = FaviconTint.glow(of: mark).usingColorSpace(.sRGB)!
        XCTAssertGreaterThan(glow.redComponent, glow.greenComponent)
        XCTAssertGreaterThan(glow.redComponent, glow.blueComponent)
        XCTAssertGreaterThanOrEqual(components(glow).saturation, 0.55, "the glow came out washed out")
    }

    /// An icon with no colour in it has none to lend, and the answer is the
    /// chrome's own ink rather than a hue invented from a grey.
    func testAColourlessIconGlowsInTheChromesInk() {
        let mark = icon { rect in
            NSColor(white: 0.2, alpha: 1).setFill()
            rect.fill()
            NSColor(white: 0.9, alpha: 1).setFill()
            rect.insetBy(dx: 8, dy: 8).fill()
        }
        XCTAssertEqual(FaviconTint.glow(of: mark), FaviconTint.neutral)
    }

    /// Two opposite colours average to a grey, and a grey is not a hue this
    /// file is entitled to saturate into one.
    func testColoursThatCancelFallBackToTheInkAsWell() {
        let mark = icon { rect in
            NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1).setFill()
            NSRect(x: 0, y: 0, width: rect.width / 2, height: rect.height).fill()
            NSColor(srgbRed: 0, green: 1, blue: 1, alpha: 1).setFill()
            NSRect(x: rect.width / 2, y: 0, width: rect.width / 2, height: rect.height).fill()
        }
        XCTAssertEqual(FaviconTint.glow(of: mark), FaviconTint.neutral)
    }

    /// A navy mark is a colour, and a colour has to be able to emit: left at
    /// the brightness it is drawn at, it glows as a dark smudge on a dark
    /// sidebar. The hue survives the lift, which is the half that matters.
    func testADarkMarkIsLiftedUntilItCanBeSeenAsLight() {
        let navy = NSColor(srgbRed: 0.04, green: 0.06, blue: 0.22, alpha: 1)
        let mark = icon { rect in
            navy.setFill()
            rect.fill()
        }
        let glow = components(FaviconTint.glow(of: mark))
        XCTAssertGreaterThanOrEqual(glow.brightness, 0.70)
        XCTAssertEqual(glow.hue, components(navy).hue, accuracy: 0.03, "the lift moved the hue")
    }

    /// The tile is wearing the icon the user chose, so the site's colours are
    /// nowhere on screen and taking one would be describing a picture that is
    /// not there.
    func testATabWithAChosenIconGlowsInTheInk() {
        var tab = Tab(
            spaceID: UUID(), kind: .essential,
            url: URL(string: "https://example.com")!, order: 0
        )
        tab.customSymbolName = "star"
        XCTAssertEqual(FaviconTint.glow(for: tab), FaviconTint.neutral)
    }
}

/// The glow as the grid wires it up.
@MainActor
final class EssentialGlowTests: XCTestCase {

    private func grid() -> EssentialsGridView {
        let grid = EssentialsGridView()
        grid.frame = NSRect(x: 0, y: 0, width: 280, height: 120)
        return grid
    }

    private func tabs(_ count: Int) -> [Tab] {
        (0..<count).map { index in
            Tab(
                spaceID: UUID(), kind: .essential,
                url: URL(string: "https://example.com/\(index)")!, order: index
            )
        }
    }

    private func glow(in grid: EssentialsGridView) -> EssentialGlowView? {
        grid.subviews.compactMap { $0 as? EssentialGlowView }.first
    }

    /// One glow for the grid, on the tile that is the tab you are on, standing
    /// exactly where that tile stands.
    func testTheLightIsOnTheTileYouAreOn() {
        let grid = grid()
        let pinned = tabs(3)
        grid.show(pinned, activeTabID: pinned[1].id)
        grid.layoutSubtreeIfNeeded()

        let lit = glow(in: grid)
        XCTAssertEqual(grid.subviews.compactMap { $0 as? EssentialGlowView }.count, 1)
        XCTAssertEqual(lit?.isLit, true)
        XCTAssertEqual(lit?.frame, grid.slotRect(at: 1))
    }

    /// Click a third tile and the light is there instead — not on both, and not
    /// left behind on the one you came from.
    func testTheLightMovesWithTheSelection() {
        let grid = grid()
        let pinned = tabs(3)
        grid.show(pinned, activeTabID: pinned[0].id)
        grid.layoutSubtreeIfNeeded()
        grid.show(pinned, activeTabID: pinned[2].id)
        grid.layoutSubtreeIfNeeded()

        XCTAssertEqual(glow(in: grid)?.frame, grid.slotRect(at: 2))
    }

    /// The light does not slide from the tile you left, and it is standing
    /// on the new one before it lights.
    ///
    /// Both halves were the same bug seen from different ends. The glow is one
    /// view moved between tiles, so a frame set inside the grid's animated pass
    /// — which a pin, an unpin or the reload a click brings with it all run —
    /// carried it across the grid; and a frame left to the layout pass that
    /// follows meant the appear played at the tile you came from and the light
    /// teleported afterwards. There is no layout pass here on purpose: the
    /// frame has to be right the moment `show` returns.
    func testTheLightDoesNotTravelToTheTileYouPressed() {
        let grid = grid()
        var pinned = tabs(3)
        grid.show(pinned, activeTabID: pinned[0].id)
        grid.layoutSubtreeIfNeeded()
        // A changed tab, which is what clicking a pinned tile really delivers:
        // the page wakes, and the whole grid rebuilds on `tabInsert`.
        pinned[2].title = "Woken"
        grid.show(pinned, activeTabID: pinned[2].id)

        let lit = glow(in: grid)
        XCTAssertEqual(lit?.frame, grid.slotRect(at: 2))
        XCTAssertNil(lit?.layer?.animation(forKey: "position"), "the light slid to its new tile")
        XCTAssertNil(lit?.layer?.animation(forKey: "bounds"))
    }

    /// The tab you are on is one of §3.4's rows, not a tile: there is nothing
    /// up here to light, and a glow left burning round the last pinned tab you
    /// visited would say you were still on it.
    func testTheLightGoesOutWhenYouLeaveTheGrid() {
        let grid = grid()
        let pinned = tabs(2)
        grid.show(pinned, activeTabID: pinned[0].id)
        grid.layoutSubtreeIfNeeded()
        grid.show(pinned, activeTabID: UUID())
        grid.layoutSubtreeIfNeeded()

        XCTAssertEqual(glow(in: grid)?.isLit, false)
    }

    /// Over every tile, and clickable by none of them. The glow has to be
    /// in front for its colour to reach the glass at all (`EssentialGlowView`'s
    /// header), which is exactly the arrangement where a view that answered a
    /// hit test would eat every click on the pinned tab you are on.
    func testTheLightIsInFrontOfTheTilesAndTakesNoClicks() {
        let grid = grid()
        let pinned = tabs(2)
        grid.show(pinned, activeTabID: pinned[0].id)
        grid.layoutSubtreeIfNeeded()

        guard let lit = glow(in: grid), let index = grid.subviews.firstIndex(of: lit) else {
            return XCTFail("the grid has no glow")
        }
        let tiles = grid.subviews.enumerated()
            .filter { $0.element is GlassButton }
            .map(\.offset)
        XCTAssertFalse(tiles.isEmpty)
        XCTAssertTrue(tiles.allSatisfy { $0 < index }, "a tile is drawn over the glow")
        XCTAssertNil(lit.hitTest(NSPoint(x: lit.bounds.midX, y: lit.bounds.midY)))
    }

    /// The lit line never leaves the grid's own margin, so the tile above the
    /// list cannot draw a bright edge into the row under it.
    func testTheRingStaysInsideTheGridsMargin() {
        XCTAssertLessThanOrEqual(
            Tokens.Metric.essentialsGlowRim,
            Tokens.Metric.essentialsVerticalInset
        )
    }
}
