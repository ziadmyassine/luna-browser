//
//  SpaceGradientTests.swift
//  LunaTests
//
//  Goals 14 and 15 of the Spaces wave, proved rather than asserted.
//
//  Every ratio below is re-derived from the live SDK: `NSColor` resolved inside
//  a real `NSAppearance`, composited, put through WCAG 2.1's formula. Nothing
//  trusts a number written in a comment — §13.6's failure in other browsers is
//  not a missing feature, it is a palette never measured against its own ink.
//
//  Increase Contrast is not exercised as an appearance — it cannot be, on
//  macOS 26.5 `NSAppearance(named: .accessibilityHighContrastAqua)` is the
//  identical object as `.aqua`. It needs no exercising here either: the ink
//  `foreground` falls back to is opaque white or opaque black, which is already
//  the strongest ink there is.
//

import AppKit
import BrowserKit
@testable import Luna
import XCTest

final class SpaceGradientTests: XCTestCase {
    private var appearances: [(String, NSAppearance)] {
        [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)]
            .compactMap { name, id in NSAppearance(named: id).map { (name, $0) } }
    }

    // MARK: - Neutral is the absence of a colour, not a thirteenth one

    /// A Space nobody has coloured must look exactly like the sidebar did
    /// before Spaces had colours.
    ///
    /// `washStops` cannot give that on its own: neutral is a real desaturated
    /// grey pair, so it hands back grey at `washAlpha` and the sidebar came up
    /// a visibly greyer column. `SpaceWashView.washColors` is where the
    /// absence is decided, and this is the test that says so — without it,
    /// "No Colour" is just the thirteenth colour in the palette.
    @MainActor
    func testANeutralSpacePaintsNoWashAtAll() throws {
        for (name, appearance) in appearances {
            let colors = SpaceWashView.washColors(for: Tokens.Gradient.neutral, in: appearance)
            for stop in colors {
                XCTAssertEqual(
                    stop.alphaComponent, 0, accuracy: 0.001,
                    "in \(name): a neutral Space still laid a film over the glass"
                )
            }
        }
    }

    /// The other half: a colour the user did pick still reaches the sidebar,
    /// so the guard above cannot be widened into "the wash never paints".
    @MainActor
    func testAChosenGradientStillWashesTheSidebar() throws {
        for (name, appearance) in appearances {
            for gradient in Tokens.Gradient.spacePalette {
                let colors = SpaceWashView.washColors(for: gradient, in: appearance)
                for stop in colors {
                    XCTAssertGreaterThan(
                        stop.alphaComponent, 0,
                        "in \(name): a Space the user coloured washed to nothing"
                    )
                }
            }
        }
    }

    // MARK: - Goal 14: twelve gradients, and new Spaces differ

    func testPaletteHasTwelveDistinctPairs() {
        XCTAssertEqual(Tokens.Gradient.spacePalette.count, 12)
        XCTAssertEqual(Set(Tokens.Gradient.spacePalette).count, 12, "A duplicated pair is two Spaces that look the same.")
        XCTAssertEqual(Tokens.Gradient.spacePaletteNames.count, Tokens.Gradient.spacePalette.count)
    }

    /// Neutral is reachable and is not something `next(after:)` can hand out
    /// — §13.6: leaving a theme is a thing the user does, never a thing that
    /// happens to them.
    func testNeutralIsOutsideThePalette() {
        XCTAssertFalse(Tokens.Gradient.spacePalette.contains(Tokens.Gradient.neutral))
        XCTAssertTrue(Tokens.Gradient.isNeutral(Tokens.Gradient.neutral))
        XCTAssertFalse(Tokens.Gradient.isNeutral(Tokens.Gradient.spacePalette[0]))
    }

    /// Goal 14's proof, at the level agent D owns: three Spaces created in a row
    /// take three different pairs, all from the palette.
    func testThreeNewSpacesTakeThreeDistinctPalettePairs() {
        var used: [GradientPair] = []
        for _ in 0 ..< 3 {
            used.append(Tokens.Gradient.next(after: used))
        }
        XCTAssertEqual(Set(used).count, 3)
        for gradient in used {
            XCTAssertTrue(Tokens.Gradient.spacePalette.contains(gradient))
        }
    }

    func testTwelveSpacesExhaustThePaletteAndTheThirteenthWraps() {
        var used: [GradientPair] = []
        for _ in 0 ..< 12 {
            used.append(Tokens.Gradient.next(after: used))
        }
        XCTAssertEqual(Set(used), Set(Tokens.Gradient.spacePalette))
        XCTAssertEqual(used, Tokens.Gradient.spacePalette, "Assignment order is the palette's own order.")
        XCTAssertEqual(Tokens.Gradient.next(after: used), Tokens.Gradient.spacePalette[0])
    }

    /// A Space on a custom colour, on neutral, or still on the legacy
    /// `GradientPair.defaultSpace` must not push the next Space off by one.
    func testPairsOutsideThePaletteDoNotConsumeASlot() {
        let used: [GradientPair] = [.defaultSpace, Tokens.Gradient.neutral]
        XCTAssertEqual(Tokens.Gradient.next(after: used), Tokens.Gradient.spacePalette[0])
    }

    /// Freeing a pair by deleting its Space makes it the next one out.
    func testDeletingASpaceReturnsItsPairToTheFront() {
        let palette = Tokens.Gradient.spacePalette
        var used = Array(palette)
        used.remove(at: 4)
        XCTAssertEqual(Tokens.Gradient.next(after: used), palette[4])
    }

    // MARK: - Goal 15: gradient text is always legible

    /// The proof. All twelve pairs × both themes × both stops, at full
    /// intensity — the Space badge and the §3.5 dots, where the gradient is at
    /// its strongest and text sits directly on it.
    func testEveryPairClearsTheTextFloorAtFullIntensityInBothThemes() {
        for (theme, appearance) in appearances {
            for (index, gradient) in Tokens.Gradient.spacePalette.enumerated() {
                let name = Tokens.Gradient.spacePaletteNames[index]
                let ink = foreground(on: gradient, appearance: appearance)
                let stops = Tokens.Gradient.planes(gradient, at: .full, in: appearance)
                let measured = Tokens.Gradient.ratio(ink, on: stops, in: appearance)
                XCTAssertGreaterThanOrEqual(
                    measured, Tokens.Gradient.textFloor,
                    "\(name) (\(theme)) measures \(String(format: "%.2f", measured)):1 — §21.4 wants 4.5:1."
                )
            }
        }
    }

    /// The same, at §8.2a's edge glow. Nothing is drawn on it today, but the
    /// intensity is published, so it is measured.
    func testEveryPairClearsTheTextFloorAtEdgeIntensity() {
        for (_, appearance) in appearances {
            for gradient in Tokens.Gradient.spacePalette {
                let ink = Tokens.Gradient.foreground(on: gradient, at: .edge, in: appearance)
                let stops = Tokens.Gradient.planes(gradient, at: .edge, in: appearance)
                XCTAssertGreaterThanOrEqual(
                    Tokens.Gradient.ratio(ink, on: stops, in: appearance), Tokens.Gradient.textFloor
                )
            }
        }
    }

    /// The sidebar wash (§8.2a's 12–18 %). `Text.primary` and `Text.secondary`
    /// must survive every pair untouched, or the whole chrome would have to
    /// re-ink itself on a Space switch.
    func testChromeInkSurvivesTheSidebarWash() {
        let tiers: [(String, NSColor)] = [("primary", Tokens.Text.primary), ("secondary", Tokens.Text.secondary)]
        for (theme, appearance) in appearances {
            for (index, gradient) in Tokens.Gradient.spacePalette.enumerated() {
                let name = Tokens.Gradient.spacePaletteNames[index]
                let stops = Tokens.Gradient.planes(gradient, at: .wash, in: appearance)
                for (tier, ink) in tiers {
                    let measured = Tokens.Gradient.ratio(ink, on: stops, in: appearance)
                    XCTAssertGreaterThanOrEqual(
                        measured, Tokens.Gradient.textFloor,
                        "Text.\(tier) on \(name)'s wash (\(theme)): \(String(format: "%.2f", measured)):1."
                    )
                }
            }
        }
    }

    /// §8.2a's range, and the reason `washAlpha` may not be nudged upward.
    func testWashAlphaStaysInsideTheSpecRange() {
        XCTAssertGreaterThanOrEqual(Tokens.Gradient.washAlpha, 0.12)
        XCTAssertLessThanOrEqual(Tokens.Gradient.washAlpha, 0.18)
    }

    /// Zen's bug, as a test. On a light pair the ink must go dark in dark
    /// mode — the one case a fixed `Text.primary` gets wrong, and the one Zen
    /// ships: "the workspace title becomes very hard to read".
    func testLightPairsGetDarkInkInDarkMode() throws {
        let dark = try XCTUnwrap(NSAppearance(named: .darkAqua))
        // "Mint", "Sand", "Blush" and "Frost" — the light band.
        for index in [2, 5, 8, 11] {
            let gradient = Tokens.Gradient.spacePalette[index]
            let ink = foreground(on: gradient, appearance: dark)
            let luminance = ink.srgbComponents(for: dark).relativeLuminance
            XCTAssertLessThan(
                luminance, 0.5,
                "\(Tokens.Gradient.spacePaletteNames[index]) is a light gradient; its ink must not be white in dark mode."
            )
        }
    }

    /// …and the mirror: a deep pair takes light ink in light mode.
    func testDeepPairsGetLightInkInLightMode() throws {
        let light = try XCTUnwrap(NSAppearance(named: .aqua))
        // "Indigo", "Mulberry", "Moss", "Rust" — the deep band.
        for index in [0, 3, 6, 9] {
            let gradient = Tokens.Gradient.spacePalette[index]
            let ink = foreground(on: gradient, appearance: light)
            let luminance = ink.srgbComponents(for: light).relativeLuminance
            XCTAssertGreaterThan(luminance, 0.5, "A deep gradient needs light ink, whatever the theme is.")
        }
    }

    /// The legacy seed pair straddles the ink threshold — its stops sit at
    /// L 0.179 and L 0.341 — so it is the worst case the palette deliberately
    /// avoids. `foreground` must still answer legibly for it, because Spaces
    /// created before this file existed are still on it.
    func testTheLegacySeedGradientIsStillLegible() {
        for (theme, appearance) in appearances {
            let ink = foreground(on: .defaultSpace, appearance: appearance)
            let stops = Tokens.Gradient.planes(.defaultSpace, at: .full, in: appearance)
            let measured = Tokens.Gradient.ratio(ink, on: stops, in: appearance)
            XCTAssertGreaterThanOrEqual(measured, Tokens.Gradient.textFloor, "defaultSpace (\(theme))")
        }
    }

    /// Neutral is a surface like any other and carries readable ink too.
    func testNeutralCarriesReadableInk() {
        for (_, appearance) in appearances {
            let ink = foreground(on: Tokens.Gradient.neutral, appearance: appearance)
            let stops = Tokens.Gradient.planes(Tokens.Gradient.neutral, at: .full, in: appearance)
            XCTAssertGreaterThanOrEqual(
                Tokens.Gradient.ratio(ink, on: stops, in: appearance), Tokens.Gradient.textFloor
            )
        }
    }

    /// Prints the full table the report quotes. Not an assertion — the
    /// assertions above are the gate; this is how the numbers are read off.
    func testMeasuredTableForTheRecord() {
        for (theme, appearance) in appearances {
            for (index, gradient) in Tokens.Gradient.spacePalette.enumerated() {
                let ink = foreground(on: gradient, appearance: appearance)
                let full = Tokens.Gradient.ratio(ink, on: Tokens.Gradient.planes(gradient, at: .full, in: appearance),
                                                 in: appearance)
                let washed = Tokens.Gradient.planes(gradient, at: .wash, in: appearance)
                let wash = Tokens.Gradient.ratio(Tokens.Text.primary, on: washed, in: appearance)
                let washSecondary = Tokens.Gradient.ratio(Tokens.Text.secondary, on: washed, in: appearance)
                let isWhite = ink.srgbComponents(for: appearance).relativeLuminance > 0.5
                print(String(
                    format: "GRADIENT %-8@ %-5@ ink=%-5@ full=%5.2f wash/primary=%5.2f wash/secondary=%5.2f",
                    Tokens.Gradient.spacePaletteNames[index] as NSString, theme as NSString,
                    (isWhite ? "white" : "black") as NSString, full, wash, washSecondary
                ))
            }
        }
    }
}
