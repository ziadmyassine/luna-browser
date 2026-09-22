//
//  Metrics+PinHints.swift
//  Luna
//
//  The two wells §3.3a draws in a Space that has pinned nothing yet: the block
//  under the URL pill where the tiles would be, and the row under it where the
//  first folder would be.
//
//  Its own file rather than a section in `Metrics.swift`, which sits on the
//  400-line limit — and because these two shapes are one idea and belong
//  together.
//

import Foundation

extension Tokens.Metric {

    /// §3.3a's block: the well that stands in for an empty Essentials grid.
    ///
    /// A tile's height, because the well is a tile — the empty one, drawn in
    /// the slot the first pinned tab lands in. It was 70, a figure chosen to
    /// be taller than a tile so the well could not be mistaken for one; being
    /// mistaken for one is the whole point. At 70 the column also dropped 16
    /// points the moment the first tab was pinned, which is the grid jumping
    /// in answer to a drop that has already landed.
    static let pinHintBlock = essentialsTile.height

    /// §3.3a's row: the well that stands in for an empty §3.4b tier.
    ///
    /// A row pill's height, because it stands exactly where the first folder's
    /// row will stand and is saying so.
    static let pinHintRow = rowPillHeight

    // The glyph in each well is the size the thing it stands in for draws its
    // own at — `essentialsIcon` in the block, `groupIconSize` in the row — so
    // there is no token here. A pin at a folder's 20 pt beside a 13 pt line was
    // the biggest thing in the grid and the line's own room went into it.

    /// Between the glyph and the line it labels. Both wells set the two side by
    /// side; where they differ is what they are lined up against — §3.4's own
    /// columns in the row, and the middle of the tile in the block, because a
    /// tile centres what is in it.
    static let pinHintGap: CGFloat = 8

    /// Both wells, and §3.3's own drop outline: one dash, so the three marks
    /// that mean "something goes here" are the same mark.
    static let pinHintDash: [CGFloat] = [6, 4]
}
