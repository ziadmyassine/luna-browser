//
//  Metrics+Effects.swift
//  Luna
//
//  §5's downloads popover and §7's reload bloom. Split out of `Metrics.swift`
//  when it crossed SwiftLint's 400-line file limit; nothing changed on the way.
//

import Foundation

extension Tokens.Metric {

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
}
