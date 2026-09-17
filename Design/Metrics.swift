//
//  Metrics.swift
//  Luna
//
//  Every number in `docs/UI-SPEC.md` §1, under the names §1 gives them, plus
//  the §1 type scale. Split out of `Tokens.swift` only to keep that file under
//  SwiftLint's length limits — `Metric` and `TypeScale` are still `Tokens.*`.
//
//  §1 derives these as ratios against a 280 pt sidebar. **The ratios are not
//  here on purpose**: §1 says chrome metrics do not rescale when the sidebar is
//  resized, so shipping them as code would only invite someone to multiply by
//  them. They fixed the proportions once; these are the result.
//
//  §3 numbers live here too, under §3's names, wherever §1's table has no row
//  for them — the row insets, the chrome gaps, §5's tail, §7's blur.
//  `ShadowMetric` is the one type here that carries a colour, and it carries a
//  *token*, never a value: the value stays in `Tokens.Shadow`.
//

import AppKit

/// A user-resizable span (§3.7: drag to resize, double-click resets).
struct SpanMetric: Sendable {
    var `default`: CGFloat
    var min: CGFloat
    var max: CGFloat

    /// Clamps a live drag into range.
    func clamp(_ value: CGFloat) -> CGFloat { Swift.min(Swift.max(value, min), max) }
}

/// A sized, rounded chrome element. A `cornerRadius` of exactly `height / 2`
/// is §1's "radius (full)" — a pill.
struct RoundedMetric: Sendable {
    var width: CGFloat
    var height: CGFloat
    var cornerRadius: CGFloat

    var size: CGSize { CGSize(width: width, height: height) }

    /// A circle: §1 quotes these as a single diameter.
    static func circle(_ diameter: CGFloat) -> RoundedMetric {
        RoundedMetric(width: diameter, height: diameter, cornerRadius: diameter / 2)
    }
}

/// A drop shadow (§5). The colour carries its own alpha, so `shadowOpacity`
/// stays at 1 and there is one number to tune instead of two fighting.
struct ShadowMetric: Sendable {
    var radius: CGFloat
    /// **CALayer coordinates**, which AppKit does not flip: a shadow that
    /// falls *downward* therefore has a negative height.
    var offset: CGSize
    /// Dynamic, like every other colour token — resolve it, do not store it.
    var color: NSColor

    /// Applies the shadow with `color` resolved for `appearance`.
    ///
    /// Resolving here rather than at the call site is the whole point: a
    /// dynamic `NSColor`'s `cgColor` freezes whichever appearance happens to be
    /// current, so a shadow assigned once in `init` keeps its light-mode alpha
    /// for the life of the window. Call this from `updateLayer` (where the
    /// view's appearance is already current) or from an appearance observer.
    func apply(to layer: CALayer, in appearance: NSAppearance) {
        appearance.performAsCurrentDrawingAppearance {
            layer.shadowColor = color.cgColor
        }
        layer.shadowRadius = radius
        layer.shadowOffset = offset
        layer.shadowOpacity = 1
    }
}

extension Tokens {

    /// Non-colour constants. Sendable values, no isolation needed.
    enum Metric {

        // MARK: Sidebar (§1, §3)

        /// 280 / 180 / 420 pt. Everything else in §1 is proportioned to the default.
        static let sidebarWidth = SpanMetric(default: 280, min: 180, max: 420)
        /// 40 pt — tabs, `Archive` and `+ Add Tab` alike (§3.4, §30.6).
        static let rowHeight: CGFloat = 40
        /// 8 pt inset of the row pill from each sidebar edge (§3.4).
        static let rowInset: CGFloat = 8
        static let faviconSize: CGFloat = 18
        static let rowCornerRadius: CGFloat = 10
        /// The vertical breathing space between two row pills (§3.4).
        ///
        /// §3.4 gives no number — it sizes the pill only horizontally
        /// ("sidebar width minus 8 pt each side"). 4 pt is what keeps two
        /// adjacent *selected* pills from fusing into one 80 pt slab at
        /// `rowHeight` 40 and `rowCornerRadius` 10, which is the failure the
        /// reference clearly does not have. Half `chromeGap`, so it moves with
        /// the rest of the chrome rather than on its own.
        static let rowGap: CGFloat = 4

        /// 15 pt to the favicon's leading edge (§3.4).
        ///
        /// **Measured correction.** §3.4 says the favicon sits 12 pt from the
        /// pill's left edge and the title 40 pt in. In
        /// `inspiration/main-tab-bar-and-ui.png` they measure ~15 pt and
        /// ~41 pt, because the reference is not using flat insets at all: the
        /// favicon is **centred in the row's leading `rowHeight`-wide zone**,
        /// inside the `rowInset` the pill already carries —
        /// 8 + (40 − 8 − 18) / 2 = 15 — and the title clears the favicon by
        /// another `rowInset`: 15 + 18 + 8 = 41. Derived rather than written
        /// down so both follow `rowHeight` and `faviconSize` if either moves.
        static let rowFaviconInset = rowInset + (rowHeight - rowInset - faviconSize) / 2
        /// 41 pt to the title's leading edge (§3.4). See `rowFaviconInset`.
        static let rowTitleInset = rowFaviconInset + faviconSize + rowInset

        // MARK: URL pill (§3.2)

        /// 266 × 32, full radius.
        static let urlPill = RoundedMetric(width: 266, height: 32, cornerRadius: 16)
        /// §3.2: the domain starts 12 pt from the pill's leading edge.
        static let pillTextInset: CGFloat = 12
        /// §3.2: the sliders glyph sits 10 pt from the pill's trailing edge.
        /// Tighter than `pillTextInset` on purpose — a glyph is optically
        /// smaller than its box, and the reference reads as even.
        static let pillGlyphInset: CGFloat = 10

        // MARK: Essentials (§3.3)

        /// 128 × 42, radius 12. Icon only — no label (§30.5).
        static let essentialsTile = RoundedMetric(width: 128, height: 42, cornerRadius: 12)
        static let essentialsTileGap: CGFloat = 10
        static let essentialsIcon: CGFloat = 22

        // MARK: Controls (§3.1, §3.5)

        /// Back and reload: 35 pt circles.
        static let controlCircle = RoundedMetric.circle(35)
        /// Sidebar toggle: 28 pt, radius 9.
        static let controlSquircle = RoundedMetric(width: 28, height: 28, cornerRadius: 9)
        /// Profile avatar and archive: 34 pt circles.
        static let bottomCircle = RoundedMetric.circle(34)
        /// The Space switcher (§3.5): 56 × 22, radius 11, widening 8 pt per
        /// Space beyond three.
        static let spaceDotsPill = RoundedMetric(width: 56, height: 22, cornerRadius: 11)
        /// Widening per Space past the third (§3.5).
        static let spaceDotsPillGrowth: CGFloat = 8
        static let spaceDot: CGFloat = 6
        /// SF Symbol point size for every chrome glyph (§3.1, §3.5, §4).
        ///
        /// The same 18 pt as `faviconSize`, and still its own token: a symbol's
        /// point size and a favicon image's edge are different measurements
        /// that happen to agree today, and the views were reaching for
        /// `faviconSize` to size glyphs for want of anything better.
        static let glyphSize: CGFloat = 18

        // MARK: Chrome gaps (§3.1, §3.2, §4)

        /// 8 pt — the gap between tight neighbours: the two §3.1 control
        /// buttons, the items inside §4's action capsule, a bar's own leading
        /// and trailing inset.
        ///
        /// Numerically `rowInset`, conceptually not: that one is a row pill's
        /// horizontal inset from the sidebar edge, and the two would part
        /// company the moment either is retuned. §4 has no gap table of its
        /// own and borrows these.
        static let chromeGap: CGFloat = 8
        /// 16 pt — the gap between *clusters*: §4's toggle ↔ back, and the tab
        /// strip ↔ the action capsule.
        static let chromeGapWide: CGFloat = 16
        /// 12 pt — §3.2's "12 pt below the control row": the vertical gap
        /// between the §3.1 control row and the URL pill beneath it. The one
        /// gap in §3 that is neither 8 nor 16.
        static let controlRowGap: CGFloat = 12
        /// 36 pt — §4's action capsule, **taller than the 32 pt `urlPill` it
        /// sits beside**, which is easy to read past in §4. Measured in
        /// `inspiration/non-side-bar-tab-ui.png`: the capsule wraps circular
        /// items with padding around them, the pill only has to contain text,
        /// so they were never the same height.
        static let capsuleHeight: CGFloat = 36

        // MARK: Window and content card (§1, §3.6, §4)

        static let windowCornerRadius: CGFloat = 18
        static let contentCardRadius: CGFloat = 16
        /// The 8 pt gap that shows the window's glass and makes the card float (§30.11).
        static let contentCardGap: CGFloat = 8
        /// Both the top-bar layout's bar and the sidebar's control / utility rows (§3.1, §3.5, §4).
        static let topBarHeight: CGFloat = 52
        /// 1 pt. The *colour* is `Tokens.Line.hairline`.
        static let hairline: CGFloat = 1
        /// §3.7: 8 pt hit area, 20 × 32 drawn handle.
        static let resizeHandleHitWidth: CGFloat = 8
        static let resizeHandle = RoundedMetric(width: 20, height: 32, cornerRadius: 10)

        // MARK: Downloads popover (§5)

        /// ~330 × 58, radius 14.
        static let downloadsPopover = RoundedMetric(width: 330, height: 58, cornerRadius: 14)
        static let downloadsFileIcon: CGFloat = 34
        static let downloadsConfirm = RoundedMetric(width: 30, height: 30, cornerRadius: 9)
        /// The side of §5's pointer tail — the square that is rotated 45° and
        /// half-buried in the popover's bottom edge, so the tip reaches
        /// `tail × √2 / 2` below the body.
        ///
        /// §5 draws the tail and gives it no number. Deriving it from the
        /// popover's own corner radius is what keeps it proportioned to the
        /// surface it grows out of instead of to a number nobody measured.
        static let downloadsPopoverTail = downloadsPopover.cornerRadius

        // MARK: Reload bloom (§7)

        /// §7's "**light (8 pt), not illegible**" blur on the frozen snapshot.
        /// Points, not pixels: the snapshot comes back at the display's backing
        /// scale, so the caller scales this into snapshot space or the blur is
        /// half as strong on 1x and twice as strong on a future 3x.
        static let reloadBlurRadius: CGFloat = 8
        /// §7's Reduce Motion path: a 2 pt progress line across the top of the
        /// content card, and no blur and no arc at all.
        static let reloadProgressLine: CGFloat = 2

        // MARK: Window (M0 — consumed by `BrowserWindowController`)

        static let windowMinWidth: CGFloat = 640
        static let windowMinHeight: CGFloat = 480
        static let windowDefaultWidth: CGFloat = 1200
        static let windowDefaultHeight: CGFloat = 800
    }

    /// §1's type scale. System font throughout (§8.6/§8.7).
    ///
    /// Every face here is the **monospaced-digit** system font: §1 asks for
    /// tabular digits "wherever a number is shown", and a badge, a download
    /// size and a row title are all drawn with these four. The letterforms are
    /// identical to the plain system font, so this costs nothing and removes
    /// the chance of someone forgetting it on the one label that jitters.
    ///
    /// `var`, not the `let` the contract sketched: `NSFont` is **not**
    /// `NS_SWIFT_SENDABLE` in the macOS 26.5 SDK (verified in `NSFont.h`), so a
    /// `static let NSFont` is a Swift 6 strict-concurrency error. Computed
    /// statics have no storage and are safe.
    enum TypeScale {
        /// 15 pt — sidebar rows (§1; deliberately roomier than §8.6's 13 pt).
        static var sidebarRow: NSFont { .monospacedDigitSystemFont(ofSize: 15, weight: .regular) }
        /// 17 pt — the sidebar URL pill.
        static var urlPill: NSFont { .monospacedDigitSystemFont(ofSize: 17, weight: .regular) }
        /// 15 pt — the same pill in top-bar layout, where it shares the bar.
        static var topBarURL: NSFont { .monospacedDigitSystemFont(ofSize: 15, weight: .regular) }
        /// 12 pt semibold — section labels.
        static var sectionLabel: NSFont { .monospacedDigitSystemFont(ofSize: 12, weight: .semibold) }
        /// 14 pt — the §5 downloads filename.
        static var downloadFilename: NSFont { .monospacedDigitSystemFont(ofSize: 14, weight: .regular) }
    }
}
