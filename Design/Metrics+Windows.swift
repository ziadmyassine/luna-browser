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

    /// The back/forward capsule at the head of the detail pane.
    static let settingsNavCapsule = RoundedMetric(width: 64, height: 30, cornerRadius: 10)

    /// §23.1 §3.2's live glass preview tile: the sample of the real
    /// material that sits beside the Appearance row. `rowCornerRadius`'s
    /// 12 rather than a new radius — the tile is a rounded card in a
    /// settings pane, which is what `rowCornerRadius` already describes.
    /// Pass `.size` to `Glass.previewTile(size:optimised:)`.
    static let glassPreviewTile = RoundedMetric(width: 160, height: 72, cornerRadius: rowCornerRadius)

    // MARK: History (§6.4)

    /// §6.4's floating history panel. As wide as the Command Bar — they are
    /// the same kind of surface over the same page, and two transient
    /// panels of different widths read as two different apps. The height is
    /// a ceiling, not a size: the panel shrinks to the window when the
    /// window is shorter, and to its rows when there are few of them.
    static let historyPanel = CGSize(width: windowMinWidth, height: 520)

    // MARK: Window (M0 — consumed by `BrowserWindowController`)

    static let windowMinWidth: CGFloat = 640
    static let windowMinHeight: CGFloat = 480
    static let windowDefaultWidth: CGFloat = 1200
    static let windowDefaultHeight: CGFloat = 800
}
