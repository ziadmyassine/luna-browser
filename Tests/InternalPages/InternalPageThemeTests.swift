//
//  InternalPageThemeTests.swift
//  LunaTests
//
//  The app's half of the token→CSS contract (§4.4, §8.1). `BrowserKit`'s
//  `InternalPagesTests` checks that the stylesheet reads only variables the
//  generator promises; this checks that the generator delivers them, and that
//  the values really come from `Design/Tokens.swift` rather than from a
//  snapshot somebody pasted in.
//
//  The failure this exists to catch is silent: a token changes in `Design/`,
//  the chrome follows it, and Luna's own pages keep the old colour forever
//  because nothing ever compared them.
//

import AppKit
import BrowserKit
import XCTest
@testable import Luna

@MainActor
final class InternalPageThemeTests: XCTestCase {

    /// Both halves of the contract: every promised variable is defined, and
    /// nothing else is. A variable the generator invents is a value the
    /// stylesheet cannot use; one it forgets is a page that renders without it.
    func testDefinesExactlyThePromisedVariables() {
        let css = InternalPageTheme.css()
        let defined = Set(
            css.components(separatedBy: "--")
                .dropFirst()
                .map { "--" + $0.prefix { $0 != ":" } }
        )
        XCTAssertEqual(defined, Set(InternalPages.paletteVariables))
    }

    /// §8.8: every colour resolves for light and dark, and the page picks
    /// with `prefers-color-scheme` — so both blocks have to be there.
    /// §21.2's Increase Contrast is `prefers-contrast`, for the reason
    /// `Design/Tokens.swift` records: on macOS 26.5 it is not an `NSAppearance`,
    /// so no Swift-side branch can see it.
    func testShipsAllFourVariants() {
        let css = InternalPageTheme.css()
        XCTAssertTrue(css.hasPrefix(":root{"), "the rest block must come first or the media queries cannot override it")
        XCTAssertTrue(css.contains("@media (prefers-color-scheme: dark){"))
        XCTAssertTrue(css.contains("@media (prefers-contrast: more){"))
        XCTAssertTrue(css.contains("@media (prefers-color-scheme: dark) and (prefers-contrast: more){"))
    }

    /// The bridge is live, not a snapshot: a dynamic token must come out
    /// differently in the two themes.
    func testResolvesTheTokensPerTheme() {
        let css = InternalPageTheme.css()
        XCTAssertNotEqual(
            value(of: "--luna-surface-base", in: css, after: ":root{"),
            value(of: "--luna-surface-base", in: css, after: "@media (prefers-color-scheme: dark){"),
            "light and dark resolve to the same surface — the palette is not reading Tokens"
        )
    }

    /// §2's Increase Contrast promotion, end to end: the ink tokens must come
    /// out at `Tokens.Ink`'s contrast alphas, not their resting ones.
    func testIncreaseContrastPromotesTheInkTokens() {
        let css = InternalPageTheme.css()
        for name in ["--luna-text-secondary", "--luna-text-tertiary", "--luna-line-border", "--luna-line-hairline"] {
            XCTAssertNotEqual(
                value(of: name, in: css, after: ":root{"),
                value(of: name, in: css, after: "@media (prefers-contrast: more){"),
                "\(name) is not promoted under Increase Contrast"
            )
        }
    }

    /// Lengths come from `Design/Metrics.swift`, not from a second set of
    /// numbers that happens to agree today (§1).
    func testLengthsTrackTheMetricTokens() {
        let css = InternalPageTheme.css()
        XCTAssertEqual(
            value(of: "--luna-row-height", in: css, after: ":root{"),
            "\(Int(Tokens.Metric.rowHeight))px"
        )
        XCTAssertEqual(
            value(of: "--luna-tile-w", in: css, after: ":root{"),
            "\(Int(Tokens.Metric.essentialsTile.width))px"
        )
        XCTAssertEqual(
            value(of: "--luna-size-row", in: css, after: ":root{"),
            "\(Int(Tokens.TypeScale.sidebarRow.pointSize))px"
        )
    }

    /// The first value of `name` declared at or after `marker`.
    private func value(of name: String, in css: String, after marker: String) -> String? {
        guard let start = css.range(of: marker),
              let declaration = css.range(of: "\(name):", range: start.upperBound..<css.endIndex)
        else { return nil }
        let rest = css[declaration.upperBound...]
        return String(rest.prefix { $0 != ";" && $0 != "}" })
    }
}
