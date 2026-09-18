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

    /// The section list. **Fixed, and deliberately not `sidebarWidth`** —
    /// that one is a `SpanMetric` because the user drags it (§3.7), and a
    /// nine-row settings list has nothing to drag for.
    static let settingsListWidth: CGFloat = 230
    /// A section row in the Settings column: its pitch, and the rounded square
    /// its symbol sits in. The tile is what makes the column read as a list of
    /// *places* rather than as a stack of labels with glyphs beside them.
    static let settingsSectionRow: CGFloat = 34
    static let settingsSectionIcon = RoundedMetric(width: 24, height: 24, cornerRadius: 7)
    /// The section row's own inset from the column's edges — the selected pill
    /// stops short of the glass on both sides rather than running edge to edge.
    static let settingsSectionInset: CGFloat = 8
    /// A control row inside a §1 card. Taller than a sidebar row by half again:
    /// it carries a switch or a popup, and often a second line under the label.
    static let settingsCardRow: CGFloat = 48
    /// The gap between one card and the next, header included.
    static let settingsGroupGap: CGFloat = 26

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
