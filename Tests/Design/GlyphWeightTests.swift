//
//  GlyphWeightTests.swift
//  LunaTests
//
//  `TypeScale.glyphWeight(for:)` is one line, and it is the kind of line that
//  gets "simplified" back to `.regular` by someone who reads it as a stray
//  special case — or flipped the wrong way by someone measuring how much ink a
//  glyph has rather than how thick its line is, which is how it came to say
//  `.semibold` for a while. The measurements are in its doc comment; what is
//  asserted here is the direction and the one shape of mark it applies to.
//

import AppKit
import XCTest
@testable import Luna

final class GlyphWeightTests: XCTestCase {

    /// A chevron is small for its cap height, and SF Symbols pays for that in
    /// stroke: at `.regular` it draws a 2.00 pt line where `arrow.clockwise`
    /// beside it in §3.1 and §3.2b draws 1.62 and the sidebar toggle draws
    /// 1.25. `.light` puts it at 1.50, in among them.
    ///
    /// The assertion is `.light` and not `.semibold` on purpose. It was
    /// semibold, from measuring total ink instead of stroke — the chevron has
    /// the least ink in the chrome because it is the smallest mark in it, which
    /// is not the same thing as being the lightest.
    func testAChevronIsSetLighterWhereverItIsDrawn() {
        XCTAssertEqual(Tokens.TypeScale.glyphWeight(for: "chevron.backward"), .light)
        XCTAssertEqual(Tokens.TypeScale.glyphWeight(for: "chevron.left"), .light)
        XCTAssertEqual(Tokens.TypeScale.glyphWeight(for: "chevron.right"), .light)
    }

    /// Everything else in the chrome is drawn at the size it was designed for
    /// and needs no correction. Touching those would only move the mismatch.
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
