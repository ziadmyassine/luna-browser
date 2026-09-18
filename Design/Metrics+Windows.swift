//
//  Metrics+Windows.swift
//  Luna
//
//  Window and panel geometry: the browser window's own size floor, §6.4's
//  history panel and `docs/SETTINGS-SPEC.md` §1's Settings window.
//
//  None of it is browser *chrome*, which is what `Metrics.swift` is for — and
//  that file had crossed SwiftLint's 400-line limit. Nothing changed on the way
//  across.
//

import Foundation

extension Tokens.Metric {

    // MARK: Settings window (§23.1 §1 — consumed by `Features/Settings/Shell`)

    /// Same four-scalar shape as the browser window above, for the same
    /// reason: the minimum is applied as two `greaterThanOrEqualToConstant`
    /// constraints, not as an `NSSize` — `NSWindow.minSize` is ignored once
    /// the content is under Auto Layout.
    static let settingsDefaultWidth: CGFloat = 720
    static let settingsDefaultHeight: CGFloat = 520
    static let settingsMinWidth: CGFloat = 640
    static let settingsMinHeight: CGFloat = 420

    /// The section list. Fixed, and deliberately not `sidebarWidth` — that one
    /// is a `SpanMetric` because the user drags it (§3.7); a nine-row list has
    /// nothing to drag for.
    static let settingsListWidth: CGFloat = 230
    /// A section row: its pitch, and the rounded square its symbol sits in. The
    /// gap between two pills comes out of the pitch, not on top of it.
    static let settingsSectionRow: CGFloat = 34
    static let settingsSectionIcon = RoundedMetric(width: 24, height: 24, cornerRadius: 7)
    /// The pill's inset from the column's edges.
    static let settingsSectionInset: CGFloat = 8
    /// A control row inside a card, and the gap from one card to the next.
    static let settingsCardRow: CGFloat = 44
    static let settingsGroupGap: CGFloat = 24

    /// **One height and one corner for every control in the pane** — button,
    /// segment, key chip, text field. The browser's chrome does the same thing
    /// with `capsuleHeight` and `controlCircle`: a window where each control
    /// picked its own size read as a form, not as Luna.
    static let settingsControl: CGFloat = 28
    static let settingsControlCorner: CGFloat = 8
    /// Room either side of a button's or a segment's label.
    static let settingsControlInset: CGFloat = 12
    static let settingsSegmentGap: CGFloat = 2

    /// The pick-one switch, and **why Luna draws its own**.
    ///
    /// Measured on macOS 26: `NSSwitch` is 54 × 24 at every `controlSize` —
    /// `.small` and `.mini` are accepted and ignored. Fifty-four points is
    /// twice `settingsControl`'s width budget and nearly half again the height,
    /// so a card of them read as a row of levers beside 13 pt type. This is the
    /// size the pane actually has room for; `SettingsSwitch` draws it.
    static let settingsSwitch = RoundedMetric(width: 36, height: 20, cornerRadius: 10)
    /// Inset either side of the knob inside the track.
    static let settingsSwitchKnobInset: CGFloat = 2

    /// The back/forward capsule at the head of the detail pane.
    static let settingsNavCapsule = RoundedMetric(width: 64, height: 30, cornerRadius: 10)

    /// §23.1 §3.2's live glass preview tile: the sample of the real
    /// material that sits beside the Appearance row. `rowCornerRadius`'s
    /// 12 rather than a new radius — the tile is a rounded card in a
    /// settings pane, which is what `rowCornerRadius` already describes.
    /// Pass `.size` to `Glass.previewTile(size:optimised:)`.
    static let glassPreviewTile = RoundedMetric(width: 160, height: 72, cornerRadius: rowCornerRadius)

    // MARK: History (§6.4)

    /// §6.4's History **pop-out**: the panel the §3.5 bottom-bar button opens,
    /// beside the button rather than over the page.
    ///
    /// **A sidebar's width and a bit**, not the Command Bar's 640. It used to
    /// be the Command Bar's, because the two were the same kind of surface —
    /// centred over the page, behind a scrim, dismissed the same way. They are
    /// not: the Command Bar is where you are looking when you summon it, and
    /// History is a shelf you glance at beside the button you pressed. A
    /// centred panel that took the page away for a glance was the surface
    /// answering a bigger question than the one being asked.
    ///
    /// 320 wide keeps a title and its `host · date` subtitle on one line at
    /// §1's 13 pt while staying visibly a panel *next to* the sidebar rather
    /// than a second one. The height is a ceiling, not a size: the pop-out
    /// shrinks to the room between the button and the top of the window, and
    /// to its rows when there are few of them.
    static let historyPanel = CGSize(width: 320, height: 420)

    /// §5's downloads pop-out, the same surface one size wider.
    ///
    /// A filename is longer than a page title and it cannot be shortened the
    /// way a URL can — `97103328759-2026-01-01-2026-08-31.pdf` has to keep both
    /// ends, which is what the row's middle truncation is for — so 360 buys the
    /// extra run of characters that makes the middle ellipsis land between two
    /// halves rather than next to the extension. Shorter than History's
    /// ceiling: a download list is a handful of rows, not a month of tabs.
    static let downloadsPanel = CGSize(width: 360, height: 340)

    /// The gap between the History button and the pop-out standing on it —
    /// §3.1's control gap, so the pop-out sits off its button by the same
    /// distance the back and reload circles sit off each other.
    static let historyPopoutGap = controlPairGap

    // MARK: Window (M0 — consumed by `BrowserWindowController`)

    static let windowMinWidth: CGFloat = 640
    static let windowMinHeight: CGFloat = 480
    static let windowDefaultWidth: CGFloat = 1200
    static let windowDefaultHeight: CGFloat = 800
}
