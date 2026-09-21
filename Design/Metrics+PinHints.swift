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
    /// 70. `pinHintInset` above and below an 18 pt glyph, a `pinHintGap` and
    /// one line of `TypeScale.sidebarHint` — but stated rather than summed, because
    /// the content is centred in it and how much air a piece of advice is worth
    /// is a judgement rather than an addition.
    ///
    /// What it is measured against is the 54 pt the grid stands at with one
    /// tile in it (`essentialsTile.height` plus both `essentialsVerticalInset`
    /// margins). The well has to be visibly taller than that or it reads as an
    /// empty tile rather than as a message, which is the whole distinction this
    /// number carries.
    static let pinHintBlock: CGFloat = 70

    /// §3.3a's row: the well that stands in for an empty §3.4b tier.
    ///
    /// A row pill's height, because it stands exactly where the first folder's
    /// row will stand and is saying so.
    static let pinHintRow = rowPillHeight

    /// The glyph in either well.
    ///
    /// A folder's, because the row well stands where a folder will and draws
    /// its glyph in the same column at the same size — so the well and the
    /// first real row put the same picture in the same place. The block's pin
    /// takes it too: two wells, one glyph size.
    static let pinHintIcon = groupIconSize

    /// Between the glyph and the line it labels, in the block — which is the
    /// one well that stacks them. The row puts its line in §3.4's title column
    /// and takes the gap from there.
    static let pinHintGap: CGFloat = 8

    /// Both wells, and §3.3's own drop outline: one dash, so the three marks
    /// that mean "something goes here" are the same mark.
    static let pinHintDash: [CGFloat] = [6, 4]
}
