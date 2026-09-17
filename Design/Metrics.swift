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

extension NSRect {

    /// Snaps the **origin** to whole points and leaves the size alone.
    ///
    /// **`.integral` is the wrong tool for a control.** It rounds the origin
    /// *down* and the far edge *up*, so a 28 × 28 circle placed at a fractional
    /// y — which is what centring on the traffic lights' midpoint gives — comes
    /// out 28 × 29 and draws as an egg. Every "circle" in the chrome was one
    /// point taller than it was wide, which is exactly what it looked like.
    ///
    /// A size from `Tokens.Metric` is already a whole number and is not the
    /// layout's to round; only where it lands is.
    var pixelAligned: NSRect {
        NSRect(x: origin.x.rounded(), y: origin.y.rounded(), width: size.width, height: size.height)
    }
}

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

        /// 280 / 160 / 420 pt. Everything else in §1 is proportioned to the default.
        static let sidebarWidth = SpanMetric(default: 280, min: 160, max: 420)
        /// 38 pt of row **pitch** — tabs, `Archive` and `+ Add Tab` alike
        /// (§3.4, §30.6). The drawn pill is `rowPillHeight`, which is this less
        /// `rowGap`; the reference measures 109 px of pitch around a 100 px
        /// pill at its 2.848 px/pt capture scale.
        static let rowHeight: CGFloat = 38
        /// 8 pt inset of the row pill from each sidebar edge (§3.4).
        static let rowInset: CGFloat = 8
        /// 16 pt. Measured at 44 px in `inspiration/main-tab-bar-and-ui.png`,
        /// for both a list row's favicon and an Essentials tile's icon.
        static let faviconSize: CGFloat = 16
        static let rowCornerRadius: CGFloat = 12
        /// The vertical breathing space between two row pills (§3.4).
        ///
        /// Measured: 109 px of pitch minus a 100 px pill is 9 px, which is
        /// 3 pt at the reference's capture scale. The pill is inset half of
        /// this at the top and half at the bottom — see `rowPillInset`.
        static let rowGap: CGFloat = 3
        /// Half `rowGap`: what the selection pill is inset by, vertically,
        /// inside its row.
        static let rowPillInset = rowGap / 2
        /// The drawn height of a row's pill — 35 pt, the 100 px the reference
        /// measures. `rowHeight` is the pitch, this is the paint.
        static let rowPillHeight = rowHeight - rowGap
        /// 12 pt between the favicon and the title. Measured: the title's ink
        /// starts 12 pt past the favicon's trailing edge.
        static let rowIconGap: CGFloat = 12
        /// The rule between `Archive` and `+ Add Tab` gets its own short row
        /// (§3.4). 12 pt: the reference puts 6 pt of clear space either side of
        /// the hairline, which is what separates the two command rows without
        /// opening a gap the size of a tab.
        static let separatorRowHeight: CGFloat = 12

        /// 17.5 pt to the favicon's leading edge (§3.4).
        ///
        /// **Measured correction, twice over.** §3.4 says the favicon sits
        /// 12 pt from the pill's left edge and the title 40 pt in; M1 read
        /// ~15 / ~41 off the reference. Re-measured against the capture's real
        /// scale (the system traffic lights are 23 pt apart and 65.5 px apart
        /// in the file, so 2.848 px/pt) they are **17.2 / 44.9**, and the rule
        /// behind them is simpler than the one M1 inferred: the favicon is
        /// **square-inset inside the pill** — the same 9.5 pt of padding on its
        /// leading edge as above and below it — and the title clears it by
        /// `rowIconGap`. Derived, so both follow the pill if it is retuned.
        static let rowFaviconInset = rowInset + (rowPillHeight - faviconSize) / 2
        /// 45.5 pt to the title's leading edge (§3.4). See `rowFaviconInset`.
        static let rowTitleInset = rowFaviconInset + faviconSize + rowIconGap
        /// The row's trailing affordance (§3.4): close on hover, speaker when a
        /// tab is making noise.
        ///
        /// **It is a chip, not a bare glyph.** Measured off Martin's close-button
        /// reference: a ~18 pt rounded square carrying its own translucent fill,
        /// with an 11 pt `xmark` inside it — a bare 16 pt glyph floating in the
        /// pill, which is what this was, reads as part of the title rather than
        /// as something to click.
        static let rowTrailingChip = RoundedMetric(width: 18, height: 18, cornerRadius: 6)
        /// The glyph inside `rowTrailingChip`. Deliberately well short of the
        /// chip: the padding is what makes the chip read as a button.
        static let rowTrailingGlyph: CGFloat = 11
        /// How far the title's ink stops short of the pill's trailing edge, and
        /// the width of the §3.4 fade that hides the cut. A title that does not
        /// fit is **faded out, never ellipsised** — the reference lets the last
        /// glyph dissolve rather than spending three characters on an `…`.
        static let rowTitleFade: CGFloat = 24

        // MARK: URL pill (§3.2)

        /// 266 × 34, full radius. The height is measured (98 px); the width is
        /// only the top bar's — in the sidebar the pill spans the width it is
        /// given, less `rowInset` each side.
        static let urlPill = RoundedMetric(width: 266, height: 34, cornerRadius: 17)
        /// §3.2: the domain starts 12 pt from the pill's leading edge.
        static let pillTextInset: CGFloat = 12
        /// §3.2: the sliders glyph sits 10 pt from the pill's trailing edge.
        /// Tighter than `pillTextInset` on purpose — a glyph is optically
        /// smaller than its box, and the reference reads as even.
        static let pillGlyphInset: CGFloat = 10

        // MARK: Essentials (§3.3)

        /// 128 × 42, radius 12. Icon only — no label (§30.5).
        static let essentialsTile = RoundedMetric(width: 128, height: 42, cornerRadius: 12)
        static let essentialsTileGap: CGFloat = 12
        /// The grid's own inset from the sidebar's edges — wider than
        /// `rowInset`, measured at 10 pt, because a tile is a box and a row is
        /// not.
        static let essentialsInset: CGFloat = 10
        /// A pinned tile's icon is the same 16 pt favicon a row draws; the tile
        /// is roomy, the icon is not (measured 43 px).
        static let essentialsIcon = faviconSize

        // MARK: Controls (§3.1, §3.5)

        /// Sidebar toggle, back and reload: 28 pt circles. All three.
        ///
        /// **Retuned down from 35.** 35 is what the reference measures, but the
        /// reference's sidebar is 268 pt of a 2146 px capture and Luna's rows,
        /// type and favicons all landed smaller than that arithmetic predicted;
        /// a 35 pt circle beside a 35 pt row pill is a control the same height
        /// as the content it sits above, which is why it read as heavy. 28 is
        /// the top bar's capsule item — the one control in the app Martin
        /// called the right size — so the two layouts now agree on one number
        /// instead of disagreeing on two.
        static let controlCircle = RoundedMetric.circle(28)
        /// The top bar's icon-only tab tile: 28 pt, radius 9. §3.1's sidebar
        /// toggle used to borrow this; it does not any more.
        static let controlSquircle = RoundedMetric(width: 28, height: 28, cornerRadius: 9)
        /// 5 pt between back and reload — measured at 14 px. Tighter than
        /// `chromeGap`: the pair reads as one control, not two.
        static let controlPairGap: CGFloat = 5
        /// 18 pt from the window's leading **and** top edges to the traffic
        /// lights (§3.1). One number for both axes on purpose: the reference
        /// insets them equally (52 px left, 51.5 px top) and unequal padding
        /// into a corner is the first thing the eye catches.
        static let trafficLightInset: CGFloat = 18
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
        /// The same 16 pt as `faviconSize`, and still its own token: a symbol's
        /// point size and a favicon image's edge are different measurements
        /// that happen to agree today, and the views were reaching for
        /// `faviconSize` to size glyphs for want of anything better.
        ///
        /// Down from 17 with `controlCircle`: a 17 pt glyph in a 28 pt circle
        /// leaves 5.5 pt of padding and reads as a glyph that outgrew its
        /// button. 16 is what the top bar has always drawn.
        static let glyphSize: CGFloat = 16

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

        /// 25 pt. Measured off the reference's own window corner (72 px), which
        /// is a macOS 26 window rather than a shape Luna invented.
        static let windowCornerRadius: CGFloat = 25
        /// The content pane's corners **match the window's**, because the pane
        /// is flush against three of the window's edges: a smaller radius would
        /// leave a crescent of glass showing inside each window corner. Only
        /// the two leading corners are actually drawn — see `ContentCardView`.
        static let contentCardRadius = windowCornerRadius
        /// A generic 8 pt inset for the panels that are not the content pane —
        /// the Command Bar and the downloads list. **There is no content-card
        /// gap any more:** the reference runs the page flush to the window's
        /// top, bottom and trailing edges (§3.6).
        static let panelInset: CGFloat = 8
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
        /// 13 pt — sidebar rows.
        ///
        /// **Re-measured, and it overturns §1's 15 pt.** In
        /// `inspiration/main-tab-bar-and-ui.png` the row titles have a 20 px
        /// x-height and a 25 px cap height, which at the capture's 2.848 px/pt
        /// scale is a 13 pt system font — §8.6's original number. 15 pt was
        /// inferred from a scale that assumed the reference's sidebar was
        /// 280 pt; the sidebar is 268 pt and the type is 13.
        ///
        /// **Plain, not `monospacedDigit`.** §1 asks for tabular digits
        /// "wherever a number is shown"; a page title is not a number, and
        /// monospaced digits visibly widen a title like "iPhone 18 Pro". The
        /// numeric faces below keep them.
        static var sidebarRow: NSFont { .systemFont(ofSize: 13, weight: .regular) }
        /// 13 pt — the sidebar URL pill, measured at the **same** x-height as
        /// the rows. §1's 17 pt came from the same bad scale as the 15 pt above.
        static var urlPill: NSFont { .systemFont(ofSize: 13, weight: .regular) }
        /// 13 pt — the same pill in top-bar layout, where it shares the bar.
        static var topBarURL: NSFont { .systemFont(ofSize: 13, weight: .regular) }
        /// 12 pt semibold — section labels.
        static var sectionLabel: NSFont { .monospacedDigitSystemFont(ofSize: 12, weight: .semibold) }
        /// 14 pt — the §5 downloads filename.
        static var downloadFilename: NSFont { .monospacedDigitSystemFont(ofSize: 14, weight: .regular) }
    }
}
