//
//  SidebarRowGeometry.swift
//  Luna
//
//  §3.4's pure answers about a row: what colour its title is, how much of the
//  row the title gets, and where the chips at its trailing end stand — plus
//  the one method that puts the chips there.
//
//  Out of `SidebarRowView.swift` because that class passed SwiftLint's length
//  limit. The answers are `static` so the rules can be asserted without a
//  window to hover in — `Tests/Sidebar/SidebarRowModelTests.swift` is where
//  they are — and they are decisions that have been argued once and must not
//  be re-argued at a call site.
//

import AppKit

extension SidebarRowView {

    /// - Parameter isDormant: §3.4b — a saved row whose page has been closed.
    ///   It reads like a loading row on purpose: both are rows with no page
    ///   behind them right now, and both come back at full strength the moment
    ///   there is one. It is deliberately not `Text.disabled`, which is the tier
    ///   for a control that cannot be operated — this row is one press from
    ///   being open again.
    static func titleInk(isSelected: Bool, isLoading: Bool, isDormant: Bool = false) -> NSColor {
        if isLoading || isDormant { return Tokens.Text.tertiary }
        return isSelected ? Tokens.Text.primary : Tokens.Text.secondary
    }

    /// §3.4's title column: where the title starts, and how wide it may be.
    ///
    /// The trailing slot is given back when nothing is in it. A row with
    /// no glyph runs its title to the pill's inner edge and lets §3.4's fade
    /// end there; a row drawing the close chip or the speaker stops half an
    /// inset short of the slot and fades before it.
    ///
    /// That was decided with both versions side by side, and the trade is
    /// worth writing down. The column moving is how a title dims under the
    /// pointer: the close chip appears, the box loses 22 pt, and the last
    /// glyphs of a long title dissolve where they were solid a frame earlier.
    /// Reserving the slot on every row holds the title still and costs every
    /// row 22 pt of pill it mostly does not need. A tab is hovered for a moment
    /// and read for hours, so the resting state wins.
    ///
    /// `rowTitleFade` at 12 rather than 24 is what makes it affordable: the
    /// shift is a ramp moving two characters, not four.
    ///
    /// Pure, like ``titleInk``, so both states can be asserted without a
    /// window to hover in. It takes the slot, not the hover — an audio row
    /// has a glyph without a pointer anywhere near it.
    ///
    /// - Parameter siteSlot: §4's selected tab, whose site settings glyph
    ///   stands before the trailing slot. The title stops short of it whether
    ///   the trailing slot is filled or not.
    static func titleColumn(
        inRowOfWidth width: CGFloat,
        hasUnread: Bool,
        slotOccupied: Bool,
        siteSlot: Bool = false,
        indent: CGFloat = 0
    ) -> (x: CGFloat, width: CGFloat) {
        let x = Tokens.Metric.rowTitleInset + indent
            + (hasUnread ? Tokens.Metric.spaceDot + Tokens.Metric.rowInset : 0)
        // Half an inset before the slot, not the full `chromeGap` two controls
        // would take between them. The title's last glyphs are already
        // dissolving by the time they reach here — `rowTitleFade` is the gap,
        // and 8 pt of clearance on top of it is 8 pt of pill left empty.
        let right = if siteSlot {
            siteSlotX(inRowOfWidth: width) - Tokens.Metric.rowInset / 2
        } else if slotOccupied {
            trailingSlotX(inRowOfWidth: width) - Tokens.Metric.rowInset / 2
        } else {
            width - 2 * Tokens.Metric.rowInset
        }
        return (x, max(right - x, 0))
    }

    /// Where the trailing glyph's slot begins, occupied or not. See
    /// ``titleColumn``.
    static func trailingSlotX(inRowOfWidth width: CGFloat) -> CGFloat {
        width - 2 * Tokens.Metric.rowInset - Tokens.Metric.rowTrailingChip.width
    }

    /// Inset from the pill, not from the row. The pill is already `rowInset`
    /// inside the row, so one inset put the chip flush against the pill's
    /// edge; the reference keeps a full inset inside it.
    func placeChips() {
        let chip = Tokens.Metric.rowTrailingChip
        let y = (bounds.height - chip.height) / 2
        trailing.frame = NSRect(
            x: Self.trailingSlotX(inRowOfWidth: contentWidth),
            y: y,
            width: chip.width,
            height: chip.height
        ).pixelAligned
        siteButton.frame = NSRect(
            x: Self.siteSlotX(inRowOfWidth: contentWidth),
            y: y,
            width: chip.width,
            height: chip.height
        ).pixelAligned
    }

    /// Where the site settings glyph's slot begins: one chip before the
    /// trailing slot, the two chips `rowInset / 2` apart — the clearance the
    /// title keeps before a chip, so the three stand evenly.
    static func siteSlotX(inRowOfWidth width: CGFloat) -> CGFloat {
        trailingSlotX(inRowOfWidth: width) - Tokens.Metric.rowInset / 2 - Tokens.Metric.rowTrailingChip.width
    }

    /// §3.4b's three: the chevron that folds a group, the hairline down the
    /// leading edge of its tabs, and the outline a lift aimed into it draws.
    /// All three are hidden on an ordinary row, and placed anyway — the frames
    /// are two rectangles and cost nothing next to the branch that would skip them.
}
