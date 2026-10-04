//
//  Metrics.swift
//  Luna
//
//  Every number in docs/UI-SPEC.md §1, under the names §1 gives them, plus the
//  §1 type scale. Split out of Tokens.swift for that file's length limit;
//  `Metric` and `TypeScale` are still `Tokens.*`.
//
//  §1 derives these as ratios against a 280 pt sidebar. The ratios are not here
//  on purpose: §1 says chrome metrics do not rescale when the sidebar is
//  resized, so shipping them would only invite someone to multiply by them.
//
//  §3 numbers live here too, under §3's names, wherever §1's table has no row
//  for them. `ShadowMetric` is the one type here that carries a colour, and it
//  carries a token, never a value.
//

import AppKit

extension NSRect {

    /// Snaps the origin to whole points and leaves the size alone.
    ///
    /// `.integral` is the wrong tool for a control: it rounds the origin down
    /// and the far edge up, so a 28 × 28 circle at a fractional y — which is
    /// what centring on the traffic lights' midpoint gives — comes out 28 × 29
    /// and draws as an egg. A size from `Tokens.Metric` is already whole and is
    /// not the layout's to round; only where it lands is.
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
struct RoundedMetric: Sendable, Equatable {
    var width: CGFloat
    var height: CGFloat
    var cornerRadius: CGFloat

    var size: CGSize { CGSize(width: width, height: height) }

    /// A circle: §1 quotes these as a single diameter.
    static func circle(_ diameter: CGFloat) -> RoundedMetric {
        RoundedMetric(width: diameter, height: diameter, cornerRadius: diameter / 2)
    }

    /// The corner curve this shape wants.
    ///
    /// A continuous curve at `radius == height / 2` is a squircle, not a
    /// circle, and the difference is the "still a bit longer than wide" in
    /// §3.1's three buttons: a superellipse has straight flanks, so a 34 × 34
    /// one reads as a stretched rounded square. Apple's continuous curve is
    /// defined for radii below half the side; at or above it there is nothing
    /// left to be continuous with.
    ///
    /// Everything squircular — the §3.3 tiles, the §3.6 card, the window —
    /// still gets `.continuous`.
    var cornerCurve: CALayerCornerCurve {
        cornerRadius * 2 >= Swift.min(width, height) ? .circular : .continuous
    }
}

/// A drop shadow (§5). The colour carries its own alpha, so `shadowOpacity`
/// stays at 1 and there is one number to tune instead of two fighting.
struct ShadowMetric: Sendable {
    var radius: CGFloat
    /// CALayer coordinates, which AppKit does not flip: a shadow that falls
    /// downward has a negative height.
    var offset: CGSize
    /// Dynamic, like every other colour token — resolve it, do not store it.
    var color: NSColor

    /// Applies the shadow with `color` resolved for `appearance`.
    ///
    /// Resolving here rather than at the call site is the point: a dynamic
    /// `NSColor`'s `cgColor` freezes whichever appearance is current, so a
    /// shadow assigned once in `init` keeps its light-mode alpha for the life
    /// of the window. Call this from `updateLayer`, where the view's appearance
    /// is already current, or from an appearance observer.
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

        /// 280 / 250 / 420 pt. Everything else in §1 is proportioned to the
        /// default.
        ///
        /// The minimum is arithmetic. The sidebar's two 52 pt rows are the
        /// widest things in it, and both stop fitting well before the list does:
        ///
        ///     §3.5, foot   inset 8 + Space pill 34 + gap 8 + dots 56 + gap 8
        ///                  + the 68 pt Downloads/History cylinder + inset 8 = 190
        ///     §3.1, head   lights 18+60 + gap 16 + toggle 34 = 128, and the
        ///                  history cluster starts at W − (8 + 34 + 5 + 68);
        ///                  measured clear of the toggle from            ≈ 243
        ///
        /// The head is the tighter because §3.1's history control is a capsule
        /// that grows a second 34 pt half as soon as there is a forward to go to
        /// (`NavCluster`), and every point it grows travels towards the toggle;
        /// arithmetic for a one-circle back button (220) lets the two overlap.
        ///
        /// 250, not the 260 that keeps a full `chromeGap` between them: the
        /// minimum is the smallest that does not overlap, and at 250 they are
        /// 7 pt apart, plainly two controls. 250 applies only where §3.1's head
        /// is in the column at full width, one of the four cases the two chrome
        /// settings make; `Settings.sidebarWidth` resolves it, and
        /// `sidebarFootFloor` is the other answer.
        static let sidebarWidth = SpanMetric(default: 280, min: 250, max: 420)
        /// What §3.5's foot occupies, which is the width no column gets
        /// under: the head can empty out — §3.2b takes its buttons onto the
        /// page — and this cannot. 190, and derived rather than written down
        /// because every part of it is already a token; the first line above
        /// is the same sum in prose, with the Space pill at its one-circle
        /// minimum. At exactly this the Space pill, the Space
        /// strip and the Downloads/History cylinder touch their gaps, and the
        /// strip stops being centred in the bar (`dotsOriginX`).
        static let sidebarFootWidth = 2 * rowInset + bottomCircle.width
            + 2 * chromeGap + spaceDotsPill.width + 2 * bottomCircle.width

        /// The minimum where §3.1's head is not in the column.
        ///
        /// 220, not the 190 the foot touches at, for the reason 250 is not
        /// 243: a column dragged to the width where three clusters meet is a
        /// bar with no air in it. The 30 pt is also the Essentials grid, which
        /// is the one thing here that keeps shrinking rather than stopping —
        /// it divides the width across up to four columns, so a tile is 47 pt
        /// wide at 220 against 40 at 190.
        static let sidebarFootFloor: CGFloat = 220
        /// 38 pt of row pitch — tabs, `Archive` and `+ Add Tab` alike (§3.4,
        /// §30.6). The drawn pill is `rowPillHeight`, this less `rowGap`; the
        /// reference measures 109 px of pitch around a 100 px pill at its
        /// 2.848 px/pt capture scale.
        static let rowHeight: CGFloat = 38
        /// 8 pt inset of the row pill from each sidebar edge (§3.4).
        static let rowInset: CGFloat = 8
        /// 16 pt. Measured at 44 px in `inspiration/main-tab-bar-and-ui.png`,
        /// for both a list row's favicon and an Essentials tile's icon.
        static let faviconSize: CGFloat = 16
        static let rowCornerRadius: CGFloat = 12
        /// The vertical breathing space between two row pills (§3.4). Measured:
        /// 109 px of pitch minus a 100 px pill is 9 px, or 3 pt at the
        /// reference's scale. The pill is inset half of this top and bottom.
        static let rowGap: CGFloat = 3
        /// Half `rowGap`: what the selection pill is inset by, vertically,
        /// inside its row.
        static let rowPillInset = rowGap / 2
        /// The drawn height of a row's pill — 35 pt, the 100 px the reference
        /// measures. `rowHeight` is the pitch, this is the paint.
        static let rowPillHeight = rowHeight - rowGap
        /// The sidebar's tab list: `rowHeight` and 1 pt more, the pill kept at
        /// `rowPillHeight`, so a tab stands 4 pt clear of the next rather than
        /// 3. A requested nudge rather than a measurement. Settings' section
        /// list follows it, being the same list; History, the Command Bar and
        /// the pop-outs keep §3.4's measured 38.
        static let tabRowHeight = rowHeight + 1
        /// What the tab list insets a pill by, top and bottom: half the room
        /// `tabRowHeight` leaves round `rowPillHeight`.
        static let tabRowPillInset = (tabRowHeight - rowPillHeight) / 2
        /// 12 pt between an icon and its label — the site menu, History,
        /// Downloads. A sidebar tab row uses `rowTitleGap`.
        static let rowIconGap: CGFloat = 12
        /// The same gap in a tab row, 3 pt tighter. Its own number
        /// so the other three lists are not dragged along, and the reason
        /// `rowTitleInset` measures 42.5 rather than §3.4's 45.5.
        static let rowTitleGap: CGFloat = 9
        /// The rule under §3.4b's saved tier gets its own short row. 12 pt: the
        /// reference puts 6 pt of clear space either side of the hairline, which
        /// separates the tiers without opening a gap the size of a tab.
        static let separatorRowHeight: CGFloat = 12
        /// The slot the chevron that folds a §3.4b group stands in, one
        /// `rowTitleGap` after the group's own name.
        ///
        /// 16 square, which is a slot the width of a favicon standing in a place
        /// no favicon ever does. The glyph inside is 9 — it introduces the
        /// group's icon rather than competing with it, and `rowTrailingChip`'s
        /// 18 would be two chips of the same weight on one row.
        static let groupChevronSlot = RoundedMetric(width: 16, height: 16, cornerRadius: 5)
        /// A §3.4b folder's own icon, against a favicon's 16.
        ///
        /// A favicon is a picture and fills its square; an SF Symbol drawn at
        /// the same point size puts about two thirds of that on the row, so a
        /// folder measured the same as the tabs under it does not look it.
        /// The box is centred on the favicon's own column rather than starting
        /// at its edge, so every icon in the list still shares one centre line
        /// and the title inset does not move.
        static let groupIconSize: CGFloat = 20
        static let groupChevron: CGFloat = 9
        /// What stands between a folder's name and the chevron after it —
        /// tighter than `rowTitleGap`, which is the gap between two different
        /// things. The chevron belongs to the name, so it sits closer to it
        /// than the name sits to the icon.
        static let groupChevronGap: CGFloat = 6
        /// How far a group's tabs step in from its header — 16, the favicon's
        /// own width, so a member's icon clears its folder's by exactly one
        /// icon and the two read as a heading with a column under it. Derived
        /// from the chevron's slot, which is that same width.
        static let groupIndent = groupChevronSlot.width
        /// How much of a §3.4b folder's header still means "beside this folder"
        /// rather than "in it", for §6.6's lift.
        ///
        /// 10 of the header row's 43. Every other row in the list is split at its
        /// middle, because its two halves mean the same kind of thing — before
        /// this row, after this row. A folder's header does not: the lower part
        /// is the one gesture that puts a tab inside the folder and the upper
        /// part only puts it above, which the row overhead has already offered.
        /// So the target that means something gets three quarters of the row,
        /// and 10 pt is still twice `dragThreshold` for the boundary above it.
        static let groupDropEdge: CGFloat = 10
        /// How much sooner a tab inside a §3.4b folder ends its pill, and so
        /// its trailing glyphs, than a loose tab: `groupPlateFoot`, so a
        /// folder's tab stands as far off the plate's side as its last tab
        /// stands off the plate's foot. It was the column's own 8, which with
        /// the plate's foot left the side several times the bottom. The leading side
        /// already stands `groupIndent` in.
        ///
        /// The plate itself stands no further out than the pills it holds: a
        /// folded folder's plate is a tab's hover pill. Grown past them by
        /// this much on every side, it reads as a heavier, taller block than
        /// the row it is lighting.
        static let groupMemberTrailingInset = groupPlateFoot
        /// A §3.4b folder's own row, folded: a tab's pitch, so a column of
        /// folders steps exactly as a column of tabs does. It was 4 pt taller,
        /// to give the folder's larger icon room in its plate, and a run of
        /// folded folders in Pinned read as spaced wider than the tabs under
        /// it.
        static let groupHeaderRowHeight = tabRowHeight
        /// An open folder's own row, 6 pt shorter than folded: the name keeps
        /// its place and the first tab comes up under it, the name's centre
        /// 13.5 pt above the row's foot. At a full row's pitch the name stood
        /// 39 pt from its first tab against about 20 from the plate's edges,
        /// and read as a heading floating over the folder rather than leading
        /// it. The name never moves on a fold; only the rows under it do, and
        /// they slide anyway.
        static let groupHeaderOpenRowHeight = tabRowHeight - 6
        /// An open folder's plate corner: the tab pill's corner plus the room
        /// round it, so the pill inside nests in the plate. The same radius a
        /// `groupPlateFoot` inside looked pinched at the corners.
        static let groupPlateCornerRadius = rowCornerRadius + groupPlateFoot
        /// How far the plate reaches below the last tab's pill, and beside a
        /// folder's tabs (`groupMemberTrailingInset`). With the favicon's own
        /// 9.5 it leaves 11.5 under the last tab's icon, against the 10 a
        /// header at a tab's pitch leaves over the folder's: the same room at
        /// both ends, give or take the icons' sizes. It was 8, then 4 under a
        /// header 4 pt taller; each time the foot outgrew the head.
        static let groupPlateFoot: CGFloat = 2
        /// The room an open, non-empty §3.4b folder leaves under its last tab.
        ///
        /// The plate reaches `groupPlateFoot` below that tab's pill, which is
        /// `groupPlateFoot − tabRowPillInset` below its row; a gap of the whole
        /// foot leaves the next pill as far below the plate as one tab's pill is
        /// below another's. The plate's reach alone ends the plate where the
        /// next row begins and leaves 1.5 pt under an open folder against 3
        /// between two tabs, so two open folders read as one block.
        static let groupEndGap = groupPlateFoot

        /// What a §3.4b row that has been closed once draws its icon at. The
        /// title drops to `Text.tertiary` beside it; a favicon has no ink tier,
        /// so it fades instead.
        static let dormantIconOpacity: CGFloat = 0.45

        /// 17.5 pt to the favicon's leading edge (§3.4).
        ///
        /// Measured, and not §3.4's 12 / 40. Against the capture's real scale
        /// (the traffic lights are 23 pt and 65.5 px apart, so 2.848 px/pt) the
        /// reference's favicon and title sit at 17.2 / 44.9: the favicon is
        /// square-inset inside the pill, the same 9.5 pt of padding leading as
        /// above and below, and the title clears it by `rowIconGap`. Derived,
        /// so both follow the pill.
        static let rowFaviconInset = rowInset + (rowPillHeight - faviconSize) / 2
        /// 42.5 pt to the title's leading edge: §3.4's 45.5, less `rowTitleGap`.
        static let rowTitleInset = rowFaviconInset + faviconSize + rowTitleGap
        /// The row's trailing affordance (§3.4): close on hover, speaker when a
        /// tab is making noise.
        ///
        /// A chip, not a bare glyph. Measured off the close-button reference: an
        /// ~18 pt rounded square with its own translucent fill and an 11 pt
        /// `xmark` inside. A bare glyph floating in the pill reads as part of
        /// the title.
        static let rowTrailingChip = RoundedMetric(width: 18, height: 18, cornerRadius: 6)
        /// The glyph inside `rowTrailingChip`. Well short of the chip: the
        /// padding is what makes the chip read as a button.
        static let rowTrailingGlyph: CGFloat = 11
        /// The width of the §3.4 fade that ends an over-long title, which is
        /// faded out, never ellipsised — the reference lets the last glyph
        /// dissolve rather than spending three characters on an `…`.
        ///
        /// 12, not 24. The fade is spent inside the title's own box, on top of
        /// the slot reserved for the close chip, so at 24 the ink reads as solid
        /// only to 50 pt short of the pill's edge.
        static let rowTitleFade: CGFloat = 12

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
        /// §3.2's sliders glyph, and not `glyphSize`. 16 pt is the size of a
        /// glyph that is its own button — the three §3.1 circles, the §3.5 bar
        /// — and this one sits inside a control that is already a landmark,
        /// next to text at 13. At 16 it is the loudest thing in a pill whose
        /// job is to be quiet. It takes the §3.4 close button's chip on hover,
        /// so it is sized to sit in one the way that glyph does.
        static let pillGlyphSize: CGFloat = 13
        /// The same two glyphs on §3.2b's bar — 14, and its own number.
        ///
        /// Not `glyphSize`, though the bar's pill stands in a row of controls
        /// that are their own buttons: at 16 the glyphs read a step louder than
        /// the address between them, because a glyph inside a capsule is
        /// measured against what shares the capsule. 14 is that step down, and
        /// not the column's 13: this pill is 420 pt wide with the ink at arm's
        /// length from the text, where the column's is 244 with the two nearly
        /// touching.
        static let barPillGlyphSize: CGFloat = 14

        // MARK: Load line (§3.2c)

        /// §3.2c's load line: 2 pt, the thickness §7 wrote down for the progress
        /// line it never shipped, and what the reference measures (4 px in a 2x
        /// capture).
        static let loadLineHeight: CGFloat = 2
        /// How far the line sits above the pill's bottom edge: the pill's own
        /// border, and nothing more.
        ///
        /// The line lies on the bottom of the well, inside the hairline, which
        /// is what the reference measures to the pixel: the blue run ends where
        /// the capsule's bottom stroke begins, with no gap. A line standing
        /// clear of the edge reads as a second rule floating inside the pill
        /// rather than as the pill's own bottom filling up.
        ///
        /// `hairline` rather than 0 so the geometry does not move when the pill
        /// swaps surface: §3.2's well is bordered on the sidebar's plane and
        /// borderless as glass, and the line stays on the same inner edge.
        static let loadLineFloor: CGFloat = hairline

        // MARK: Essentials (§3.3)

        /// 128 × 42, radius 12. Icon only — no label (§30.5).
        static let essentialsTile = RoundedMetric(width: 128, height: 42, cornerRadius: 12)
        /// The grid's inset above the first row of tiles and below the last.
        ///
        /// 6, tuned by eye against the URL pill. The sides are an alignment —
        /// the tiles agree with the pill above and the rows below at
        /// `rowInset`. Top and bottom are a gap, and a gap is a judgement:
        /// `rowInset` pushes the grid a visible step away from the pill it
        /// belongs under, and the tiles' own gutter closes it up too far.
        static let essentialsVerticalInset: CGFloat = 6
        /// The gutter between two tiles side by side.
        ///
        /// 5, not `rowInset`. Two tiles a full row-inset apart read as separate
        /// controls; the grid is one block of pinned sites.
        static let essentialsTileGap: CGFloat = 5
        /// The gap between one row of tiles and the next.
        ///
        /// Its own number, and the same one as the margin above the grid: a
        /// tile's horizontal neighbour is a hand's width away and its vertical
        /// one is directly under it, so the two gaps are not the same distance
        /// even at the same length. This is the vertical rhythm the URL pill
        /// sets, carried down through the grid.
        static let essentialsRowGap = essentialsVerticalInset
        /// The grid's inset from the sidebar's leading and trailing edges.
        ///
        /// `rowInset`, so the tiles line up with everything else. Two points off
        /// the URL pill's and the row pills' 8 is invisible one element at a
        /// time and obvious down the length of the sidebar.
        static let essentialsInset = rowInset
        /// A pinned tile's icon is the same 16 pt favicon a row draws; the tile
        /// is roomy, the icon is not (measured 43 px).
        static let essentialsIcon = faviconSize

        // MARK: Controls (§3.1, §3.5)

        /// Sidebar toggle, back and reload: 28 pt circles. All three.
        ///
        /// Not the reference's 35: its sidebar is 268 pt of a 2146 px capture,
        /// and Luna's rows, type and favicons all land smaller than that
        /// arithmetic predicts. A 35 pt circle beside a 35 pt row pill is a
        /// control the same height as the content above it, and reads as heavy.
        /// 28 is the top bar's capsule item, the one control agreed to be the
        /// right size.
        static let controlCircle = RoundedMetric.circle(28)
        /// §3.1's three sidebar circles — toggle, back, reload.
        ///
        /// The URL pill's own height, so the sidebar's head is one stack of
        /// equal-height controls. 28 pt beside a 34 pt pill reads as small
        /// buttons floating above a bigger one. The top bar keeps
        /// `controlCircle`: its capsule items are 28 and the back button has to
        /// match those.
        ///
        /// Derived rather than written down again, so it follows the pill.
        static let sidebarCircle = RoundedMetric.circle(urlPill.height)
        /// The top bar's icon-only tab tile: 28 pt, radius 9.
        static let controlSquircle = RoundedMetric(width: 28, height: 28, cornerRadius: 9)
        /// 5 pt between back and reload — measured at 14 px. Tighter than
        /// `chromeGap`: the pair reads as one control, not two.
        static let controlPairGap: CGFloat = 5
        /// 18 pt from the window's leading and top edges to the traffic lights
        /// (§3.1). One number for both axes: the reference insets them equally
        /// (52 px left, 51.5 px top) and unequal padding into a corner is the
        /// first thing the eye catches.
        static let trafficLightInset: CGFloat = 18
        /// §3.5's foot: the Space pill's height, and the Downloads and History circles.
        static let bottomCircle = RoundedMetric.circle(34)
        /// The Space switcher (§3.5): 22 tall, radius 11.
        ///
        /// Only the height and the radius are laid out with. The strip sizes
        /// the pill to the dots it holds — `SpaceDotsView.width(forDots:)` over
        /// `Metric.spaceDotPitch`, with the radius as the end inset — because a
        /// fixed 56 pt holding two dots has to push them 28 pt apart to fill
        /// itself, which is four dot diameters of empty glass between two marks
        /// that mean "these are next to each other". The width is §1's quoted
        /// resting size, and what `TokenCheck` measures the radius against.
        static let spaceDotsPill = RoundedMetric(width: 56, height: 22, cornerRadius: 11)
        static let spaceDot: CGFloat = 6
        /// The chip a hovered or pressed Space dot wears (§3.4's washes), and
        /// the dot's own slot: `spaceDotPitch`, so the run reads as a row of
        /// places the pointer moves between rather than as marks with gaps. At
        /// a 22 pt pill that leaves 4 pt of glass above and below, and the end
        /// inset is the pill's radius, so the first and last chips keep the
        /// same 4 pt off the cap. Only ever one is lit, so two touching at the
        /// seam is not a state that exists.
        static let spaceDotChip = spaceDotPitch
        /// SF Symbol point size for every chrome glyph (§3.1, §3.5, §4).
        ///
        /// The same 16 pt as `faviconSize`, and still its own token: a symbol's
        /// point size and a favicon image's edge are different measurements
        /// that happen to agree today.
        ///
        /// Not 17: a 17 pt glyph in a 28 pt `controlCircle` leaves 5.5 pt of
        /// padding and reads as a glyph that outgrew its button.
        static let glyphSize: CGFloat = 16

        // MARK: Chrome gaps (§3.1, §3.2, §4)

        /// 8 pt — the gap between tight neighbours: the two §3.1 control
        /// buttons, the items inside §4's action capsule, a bar's own leading
        /// and trailing inset.
        ///
        /// Numerically `rowInset`, conceptually not: that one is a row pill's
        /// inset from the sidebar edge, and the two would part company the
        /// moment either is retuned. §4 has no gap table of its own.
        static let chromeGap: CGFloat = 8
        /// 16 pt — the gap between clusters: §4's toggle ↔ back, and the tab
        /// strip ↔ the action capsule.
        static let chromeGapWide: CGFloat = 16
        /// 12 pt — §3.2's "12 pt below the control row": the vertical gap
        /// between the §3.1 control row and the URL pill beneath it. The one
        /// gap in §3 that is neither 8 nor 16.
        static let controlRowGap: CGFloat = 12
        /// 36 pt — §4's action capsule, taller than the 32 pt `urlPill` beside
        /// it, which is easy to read past in §4. Measured in
        /// `inspiration/non-side-bar-tab-ui.png`: the capsule wraps circular
        /// items with padding around them, the pill only has to contain text.
        static let capsuleHeight: CGFloat = 36

        // MARK: Window and content card (§1, §3.6, §4)

        /// 25 pt, the default. Measured off the reference's own window corner
        /// (72 px), a macOS 26 window rather than a shape Luna invented.
        static let windowCornerRadius: CGFloat = 25
        /// 16 pt, the corner macOS gives Luna's window, for the Appearance
        /// setting that matches it (`Settings.macWindowCorners`). Measured on
        /// macOS 27: `NSWindow._cornerRadius` on a titled, full-size-content
        /// window, with and without a toolbar.
        static let windowCornerRadiusSystem: CGFloat = 16
        /// The Command Bar, the pop-outs, the tab switcher and the quit sheet.
        /// They float over the page rather than nesting in the window's corners,
        /// so they keep the reference's radius whichever corner the window wears.
        static let panelCornerRadius = windowCornerRadius
        /// A generic 8 pt inset for the panels that are not the content pane —
        /// the Command Bar and the downloads list. There is no content-card gap:
        /// the reference runs the page flush to the window's top, bottom and
        /// trailing edges (§3.6).
        static let panelInset: CGFloat = 8
        /// The narrowest §9.1's bar is allowed to be when it has grown out of
        /// an address pill (§3.2) rather than opening over the page.
        ///
        /// Measured off the row. A result row spends a fixed ~140 pt on things
        /// that do not shrink — two insets, the favicon, the stack's gaps, the
        /// Space dot and the Profile name §21.2 requires beside it — so a 264 pt
        /// sidebar pill leaves about 120 pt for the title, and every row reads
        /// `OpenAI | Rese…`. At 360 the titles survive, and the bar overhangs
        /// the column onto the page, which a panel floating over a page may do.
        static let commandBarMinWidth: CGFloat = 360
        /// Both the top-bar layout's bar and the sidebar's control / utility rows (§3.1, §3.5, §4).
        static let topBarHeight: CGFloat = 52

        // No scrim strength: `alphaValue` on an `NSVisualEffectView` does not
        // thin a material, it cross-fades the blurred result back over the sharp
        // original, so any value below 1.0 lays a flat grey film over a page
        // that was readable anyway.

        // MARK: Settings window

        /// The Settings window's own sidebar. Narrower than the browser's — it
        /// holds four words, not a tab list.
        static let settingsSidebarWidth: CGFloat = 196
        /// The Settings window's resting size.
        static let settingsWindow = CGSize(width: 720, height: 460)
        /// A Settings pane's inset from the window's edges. `chromeGapWide`
        /// doubled: a settings pane breathes where chrome does not.
        static let settingsPaneInset = chromeGapWide * 2
        /// 1 pt. The colour is `Tokens.Line.hairline`.
        static let hairline: CGFloat = 1
        /// §3.7: the divider's 8 pt grab strip. Nothing is drawn on it — see
        /// `SidebarResizeHandle`.
        static let resizeHandleHitWidth: CGFloat = 8
        /// §3.7's drawn handle, kept as a token because `TokenCheck` measures
        /// it. The handle itself is not painted.
        static let resizeHandle = RoundedMetric(width: 20, height: 32, cornerRadius: 10)
        /// §7.2: how close to the window's leading edge the pointer has to get
        /// before a hidden sidebar peeks out. Dia's, measured 2026-09-24 by
        /// hovering its window with the sidebar hidden: out at 3.5 pt, not at 4.
        ///
        /// A strip this thin inside a window edge has to be aimed at, since
        /// nothing stops the pointer there, and a wide one (44) slides the
        /// sidebar out over controls near the edge of the page. What makes 4
        /// work is the other half of Dia's rule: the pointer leaving the window
        /// across that edge counts too (`SidebarPeekEdgeView`), so shoving the
        /// mouse left cannot overshoot it.
        static let sidebarPeekEdge: CGFloat = 4
        /// §7.2's strip in fullscreen, where the window's leading edge is the
        /// screen's. The pointer piles up against a screen edge, so 1 pt is
        /// reached by shoving the mouse left and by nothing else.
        static let sidebarPeekEdgeFullScreen: CGFloat = 1
        /// §6.6: how far a press has to travel before it stops being a click
        /// and becomes a drag. AppKit's own threshold for a table drag is 3–4
        /// pt; 4 is far enough that selecting a tab with an unsteady hand does
        /// not lift it, and near enough that a deliberate pull is answered at
        /// once.
        static let dragThreshold: CGFloat = 4
        /// §6.6: how far clear of its column — or of the window — a lifted
        /// tab's pointer has to go before the tab leaves the list, as a window
        /// of its own or as a link for another app (`TabTearOff`). Chromium
        /// tears a tab off its strip at 15 px of travel across it
        /// (`kVerticalDetachMagnetism`). Luna's reorder is locked to the
        /// column and a tab torn off by a hand that drifted while reordering
        /// is a window nobody asked for, so it waits for a whole row's pitch
        /// outside, which no reorder ever needs to cover: the list is the
        /// column.
        static let tabTearOffDistance: CGFloat = rowHeight

    }
}
