//
//  Metrics+Windows.swift
//  Luna
//
//  Window and panel geometry: the browser window's size floor, §6.4's history
//  panel and docs/SETTINGS-SPEC.md §1's Settings window. None of it is browser
//  chrome, which is what Metrics.swift is for — and that file was at the
//  400-line limit.
//

import Foundation

extension Tokens.Metric {

    // MARK: Settings window (§23.1 §1 — consumed by `Features/Settings/Shell`)

    /// Same four-scalar shape as the browser window below, for the same reason:
    /// the minimum is applied as two `greaterThanOrEqualToConstant` constraints,
    /// not as an `NSSize` — `NSWindow.minSize` is ignored once the content is
    /// under Auto Layout.
    static let settingsDefaultWidth: CGFloat = 720
    /// Kept 40 above the floor, as it was before the floor moved.
    static let settingsDefaultHeight: CGFloat = 600
    static let settingsMinWidth: CGFloat = 640
    /// The floor has to hold §2's twelve rows, and on the sidebar's 38 pt
    /// pitch they are 453 pt tall: 84 pt of search and its gaps above plus
    /// `chromeGapWide` below comes to 553. Below that the list runs past the
    /// bottom of the window it is constrained inside, which is a broken
    /// constraint rather than a scroll — what §1's original 420 did to ten.
    static let settingsMinHeight: CGFloat = 560

    /// The section list. Fixed, and deliberately not `sidebarWidth` — that one
    /// is a `SpanMetric` because the user drags it (§3.7); a nine-row list has
    /// nothing to drag for.
    static let settingsListWidth: CGFloat = 230
    // A section row has no metrics of its own any more: §2's list is the
    // browser sidebar with sections where the tabs are, so it reads `rowHeight`,
    // `rowPillHeight`, `rowGap` and `rowInset` directly (`SettingsMetrics`).
    // `settingsSectionRow` (34) and `settingsSectionIcon` (a 24 pt rounded
    // square behind every glyph) are gone with the design they described.
    /// A control row inside a card, and the gap from one card to the next.
    static let settingsCardRow: CGFloat = 44
    static let settingsGroupGap: CGFloat = 24
    /// Two cards that are the same kind of thing — §6.2's Spaces, §9's
    /// Profiles — rather than one group and the next.
    ///
    /// Half `settingsGroupGap`, and derived from it because the point is the
    /// ratio: a run of six cards a full group apart is six sections that
    /// happen to look alike, and the pane loses the one thing that says they
    /// are a list. Not `chromeGap`, which already means the tighter thing —
    /// a note at 8 pt reads as belonging to the card above it, and a Space's
    /// card does not belong to the Space above it.
    static let settingsListGap = settingsGroupGap / 2

    /// One height and one corner for every control in the pane — button,
    /// segment, key chip, text field. The browser's chrome does the same with
    /// `capsuleHeight` and `controlCircle`: a window where each control picked
    /// its own size read as a form, not as Luna.
    static let settingsControl: CGFloat = 28
    static let settingsControlCorner: CGFloat = 8
    /// Room either side of a button's or a segment's label.
    static let settingsControlInset: CGFloat = 12
    static let settingsSegmentGap: CGFloat = 2

    /// Appearance's Layout row: a picture of each layout. 72 tall, the glass
    /// preview tile's height (`AppearanceSection.previewTileSize`), so the
    /// section's two pictures stand the same size; 116 wide is that at a Mac
    /// window's 16:10.
    static let settingsLayoutPreview = CGSize(width: 116, height: 72)
    /// The ring on the chosen layout — the Space swatch's, the other chooser
    /// in Settings that answers with a ring.
    static let settingsLayoutRing = spaceSwatchRing

    /// Settings › About's app icon: 64, the size macOS's own About panel
    /// draws an app's icon at.
    static let aboutIcon: CGFloat = 64

    /// A section's tile (`SettingsSymbolTile`): in the list, 22 — the
    /// 16 pt glyph column with three points of tile round it, so a tile
    /// sits where a symbol used to without moving the title; at the head of
    /// the page, twice that, the size macOS gives a settings pane's own tile.
    static let settingsListTile: CGFloat = 22
    static let settingsPageTile: CGFloat = 44

    /// The back/forward capsule at the head of the detail pane.
    static let settingsNavCapsule = RoundedMetric(width: 64, height: 30, cornerRadius: 10)

    /// §23.1 §3.2's live glass preview tile: the sample of the real material
    /// beside the Appearance row. `rowCornerRadius`'s 12 rather than a new
    /// radius — the tile is a rounded card in a settings pane. Pass `.size` to
    /// `Glass.previewTile(size:optimised:)`.
    static let glassPreviewTile = RoundedMetric(width: 160, height: 72, cornerRadius: rowCornerRadius)

    // MARK: History (§6.4)

    /// §6.4's History pop-out: the panel the §3.5 bottom-bar button opens,
    /// beside the button rather than over the page.
    ///
    /// A sidebar's width and a bit, not the Command Bar's 640. It used to be the
    /// Command Bar's, because the two looked like the same kind of surface —
    /// centred over the page, behind a scrim, dismissed the same way. They are
    /// not: the Command Bar is where you are looking when you summon it, and
    /// History is a shelf you glance at beside the button you pressed.
    ///
    /// 320 keeps a title and its `host · date` subtitle on one line at §1's
    /// 13 pt while staying visibly a panel next to the sidebar rather than a
    /// second one. The height is a ceiling: the pop-out shrinks to the room
    /// between the button and the top of the window, and to its rows when there
    /// are few of them.
    static let historyPanel = CGSize(width: 320, height: 420)

    /// §5's downloads pop-out, the same surface one size wider.
    ///
    /// A filename is longer than a page title and cannot be shortened the way a
    /// URL can — `97103328759-2026-01-01-2026-08-31.pdf` has to keep both ends,
    /// which is what the row's middle truncation is for — so 360 buys the run of
    /// characters that makes the ellipsis land between two halves rather than
    /// next to the extension. Shorter than History's ceiling: a download list is
    /// a handful of rows, not a month of tabs.
    static let downloadsPanel = CGSize(width: 360, height: 340)

    /// §3.2's site settings pop-out. Measured off the reference: its rows'
    /// glyphs stand 1/16 of the panel's width in and their titles 3/16, which
    /// at `rowFaviconInset`'s 17.5 puts the panel at 280. The height is its
    /// rows (`SiteSettingsContent.height`).
    static let siteSettingsPanel: CGFloat = 280

    /// The gap between the History button and the pop-out standing on it —
    /// §3.1's control gap, so the pop-out sits off its button by the same
    /// distance the back and reload circles sit off each other.
    static let historyPopoutGap = controlPairGap

    // MARK: Window (M0 — consumed by `BrowserWindowController`)

    static let windowMinWidth: CGFloat = 640
    static let windowMinHeight: CGFloat = 480
    static let windowDefaultWidth: CGFloat = 1200
    static let windowDefaultHeight: CGFloat = 800

    /// §22.6: how far a new window lands down and across from the one it came
    /// out of. `windowCornerRadius`, the rounder of the two corners, plus the
    /// control gap — which is what it takes for the traffic lights of the
    /// window underneath to stay clear of the new window's rounded corner, and
    /// so still be clickable, whichever corner the windows wear.
    static let windowCascadeStep = windowCornerRadius + controlPairGap
}
