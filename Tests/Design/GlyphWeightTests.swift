//
//  GlyphWeightTests.swift
//  LunaTests
//
//  `TypeScale.glyphWeight(for:)` is one line, and it is the kind of line that
//  gets "simplified" back to `.regular` by someone who reads it as a stray
//  special case. The measurements it exists for are in its doc comment; what is
//  asserted here is that it still applies to exactly one shape of mark.
//

import AppKit
import XCTest
@testable import Luna

final class GlyphWeightTests: XCTestCase {

    /// A chevron is two thin diagonals: at §3's 16 pt it covers 28 pt² of ink
    /// in a box 7.5 pt wide, against `sidebar.leading` — its neighbour in
    /// §3.1's control row and in §3.2b's page bar — at 101 in a box 18.5 wide.
    /// Semibold is what closes that.
    func testAChevronIsSetHeavierWhereverItIsDrawn() {
        XCTAssertEqual(Tokens.TypeScale.glyphWeight(for: "chevron.backward"), .semibold)
        XCTAssertEqual(Tokens.TypeScale.glyphWeight(for: "chevron.left"), .semibold)
        XCTAssertEqual(Tokens.TypeScale.glyphWeight(for: "chevron.right"), .semibold)
    }

    /// Everything else in the chrome is a closed shape and already carries its
    /// weight. Correcting those too would only move the mismatch.
    func testEveryOtherChromeGlyphIsLeftAlone() {
        let names = [
            "sidebar.leading", "arrow.clockwise", "xmark", "plus",
            "clock.arrow.circlepath", "arrow.down.to.line", "person.crop.circle",
            "globe", "magnifyingglass", "speaker.wave.2.fill"
        ]
        for name in names {
            XCTAssertEqual(Tokens.TypeScale.glyphWeight(for: name), .regular, name)
        }
    }
}
