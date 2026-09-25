//
//  Metrics+Extensions.swift
//  Luna
//
//  §16.4: extension buttons on the three surfaces, their badge, and the
//  pop-out that lists them. Separate from Metrics.swift, which is at its
//  length limit.
//
//  Nearly every size here is borrowed. A pinned extension is a glyph on a
//  surface that already has glyphs, so it takes that surface's chip; what is
//  new is the badge and the rules for how many pins a surface gives room to.
//

import Foundation

extension Tokens.Metric {

    /// Rows the pop-out shows before its list scrolls: §9.1's
    /// `CommandBarMetrics.visibleRows`, the other list in Luna that opens over
    /// the page from a control.
    static let extensionsPanelRows = 8

    /// A badge on a pinned button: the line height of `TypeScale.extensionBadge`
    /// with no leading, so it covers as little of the 16 pt icon as a legible
    /// badge can.
    static let extensionBadgeHeight: CGFloat = 9

    /// The badge beside a name in the pop-out's rows, where there is room to
    /// set it at the caption size rather than squeezing it onto an icon.
    static let extensionRowBadgeHeight: CGFloat = 16

    /// How much of the sidebar's pill the address keeps however many
    /// extensions are pinned. Half: past that the column's one landmark reads
    /// as a toolbar with an address squeezed into it. Zen's URL bar makes the
    /// same trade at 55 % before it folds its buttons into a grid
    /// (docs/EXTENSIONS.md §2).
    static let pinnedExtensionsAddressShare: CGFloat = 0.5

    /// The room §4's tab strip keeps however many are pinned: two tabs. Fewer
    /// and a pinned extension has cost the user the thing the bar is for.
    static var pinnedExtensionsStripFloor: CGFloat { 2 * TopBarMetrics.tabWidth + TopBarMetrics.tabGap }
}

extension Tokens.Metric {

    /// An extension's icon at the head of its card in Settings: twice
    /// `faviconSize`. Beside two lines of type a 16 pt icon read as a bullet,
    /// and 32 is a size every extension ships a drawing for.
    static let extensionCardIcon: CGFloat = 2 * faviconSize
}
