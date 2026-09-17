//
//  InternalPageTheme.swift
//  Luna
//
//  The token→CSS bridge (§4.4, §8.1). `BrowserKit` serves Luna's internal
//  pages but cannot see `Design/` — it must not import AppKit — so the palette
//  is *generated* here, from the same `Tokens` every view reads, and handed
//  over as a block of CSS custom properties. A second hand-written palette in
//  the page templates would be worse than none: it would look right on the day
//  it was written and drift silently forever after.
//
//  **Why this lives in `Features/` and not `Design/`:** it is a consumer of the
//  tokens, not one of them. Nothing here names a colour, and
//  `InternalPageThemeTests` fails if the emitted variables ever stop matching
//  `InternalPages.paletteVariables`.
//
//  **Four variants, because the page picks, not Swift.** Light and dark (§8.8)
//  and Increase Contrast (§21.2) are both `prefers-*` media queries inside the
//  page. That is not a shortcut, it is the only hook that works: on macOS 26.5
//  Increase Contrast is not an `NSAppearance` (see `Design/Tokens.swift`), so a
//  Swift-side branch has nothing to observe and no way to invalidate a page
//  that is already on screen. The contrast values come from `Tokens.Ink`, which
//  is exactly how `TokenCheck` reaches the same branch.
//

import AppKit
import BrowserKit

@MainActor
enum InternalPageTheme {

    /// The palette block prepended to every internal page's stylesheet.
    static func css() -> String {
        let blocks = [
            (query: nil as String?, contrast: false, dark: false),
            (query: "(prefers-color-scheme: dark)", contrast: false, dark: true),
            (query: "(prefers-contrast: more)", contrast: true, dark: false),
            (query: "(prefers-color-scheme: dark) and (prefers-contrast: more)", contrast: true, dark: true)
        ]
        // Every block restates every swatch. Emitting only the differences would
        // be smaller and is a trap: the blocks overlap — dark **and** dark+contrast
        // both apply in dark+contrast — so "same as the rest value" is not the
        // same question as "same as what is already in force". A kilobyte of
        // repetition on a page that is built in-process is not a cost.
        return blocks.map { block in
            var declarations = swatches.map { swatch in
                "\(swatch.name):\(rgba(swatch.colour(block.contrast, block.dark), dark: block.dark))"
            }
            // Lengths and durations are theme-independent, so they are declared once.
            if block.query == nil { declarations += lengths }
            let rule = ":root{\(declarations.joined(separator: ";"))}"
            return block.query.map { "@media \($0){\(rule)}" } ?? rule
        }
        .joined()
    }

    // MARK: - Colour

    private struct Swatch {
        let name: String
        /// `(increaseContrast, isDark) -> NSColor`. Ink tokens branch on both;
        /// system-backed and opaque tokens ignore the first, because their
        /// contrast variant is AppKit's to decide and is not readable from here.
        let colour: (Bool, Bool) -> NSColor
    }

    private static let swatches: [Swatch] = [
        Swatch(name: "--luna-surface-base") { _, _ in Tokens.Surface.base },
        Swatch(name: "--luna-surface-raised") { _, _ in Tokens.Surface.raised },
        Swatch(name: "--luna-surface-hover") { Tokens.Ink.hover.color(contrast: $0, dark: $1) },
        Swatch(name: "--luna-text-primary") { _, _ in Tokens.Text.primary },
        Swatch(name: "--luna-text-secondary") { Tokens.Ink.secondary.color(contrast: $0, dark: $1) },
        Swatch(name: "--luna-text-tertiary") { Tokens.Ink.tertiary.color(contrast: $0, dark: $1) },
        // §2's hairline promotion is done by hand everywhere in Luna, for the
        // reason `Tokens.Line.hairline` records: the high-contrast appearances
        // are not distinct objects, so `.separatorColor` cannot be resolved
        // "under Increase Contrast" at all.
        Swatch(name: "--luna-line-hairline") { contrast, dark in
            contrast ? NSColor(white: dark ? 1 : 0, alpha: Tokens.Ink.hairlineContrast) : .separatorColor
        },
        Swatch(name: "--luna-line-border") { Tokens.Ink.border.color(contrast: $0, dark: $1) },
        Swatch(name: "--luna-accent") { _, _ in Tokens.Accent.tint },
        Swatch(name: "--luna-danger") { _, _ in Tokens.Accent.danger }
    ]

    /// `rgb(r g b / a)` — CSS Color 4's space-separated form, which keeps the
    /// alpha the ink tokens are built on instead of flattening it onto a guess
    /// about what is behind the text.
    private static func rgba(_ colour: NSColor, dark: Bool) -> String {
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua) ?? NSAppearance.currentDrawing()
        let srgb = colour.srgbComponents(for: appearance)
        let channel = { (value: Double) in String(Int((value * 255).rounded())) }
        let alpha = (srgb.alpha * 1000).rounded() / 1000
        return "rgb(\(channel(srgb.red)) \(channel(srgb.green)) \(channel(srgb.blue)) / \(alpha))"
    }

    // MARK: - Lengths, type and motion
    //
    // Theme-independent, so they are declared once in the rest block. Straight
    // from `Design/Metrics.swift` and `Design/Motion.swift`: an internal page is
    // still Luna's UI, and §1's ratios do not get a second set of numbers just
    // because they are being spelled in CSS.

    private static var lengths: [String] {
        let metric = Tokens.Metric.self
        return [
            px("--luna-hairline", metric.hairline),
            px("--luna-gap", metric.chromeGap),
            px("--luna-gap-wide", metric.chromeGapWide),
            px("--luna-row-height", metric.rowHeight),
            px("--luna-row-radius", metric.rowCornerRadius),
            px("--luna-row-inset", metric.rowInset),
            px("--luna-favicon", metric.faviconSize),
            px("--luna-tile-w", metric.essentialsTile.width),
            px("--luna-tile-h", metric.essentialsTile.height),
            px("--luna-tile-radius", metric.essentialsTile.cornerRadius),
            px("--luna-tile-gap", metric.essentialsTileGap),
            px("--luna-tile-icon", metric.essentialsIcon),
            px("--luna-pill-h", metric.urlPill.height),
            px("--luna-pill-inset", metric.pillTextInset),
            px("--luna-card-radius", metric.contentCardRadius),
            px("--luna-size-row", Tokens.TypeScale.sidebarRow.pointSize),
            px("--luna-size-pill", Tokens.TypeScale.urlPill.pointSize),
            px("--luna-size-label", Tokens.TypeScale.sectionLabel.pointSize),
            // Reduce Motion is `prefers-reduced-motion` in the page, so this
            // stays the resting duration rather than being zeroed here.
            "--luna-motion-hover:\(Tokens.Motion.rowHover.duration)s"
        ]
    }

    /// A WebKit CSS pixel is one point of the view's coordinate space, so a
    /// 40 pt row is `40px` and no conversion is wanted.
    private static func px(_ name: String, _ value: CGFloat) -> String {
        "\(name):\(Int(value.rounded()))px"
    }
}
