//
//  Metrics+Find.swift
//  Luna
//
//  §18.1's find field. Separate from Metrics.swift because that file is past
//  its length limit already.
//
//  The capsule is §4's capsule height and holds three `controlCircle`s, so the
//  only new numbers are the two pieces of text it has to make room for.
//

import Foundation

extension Tokens.Metric {

    /// What the field shows before it scrolls: twenty-one characters of
    /// `TypeScale.urlPill`, measured at 125 pt. Long enough for a phrase, short
    /// enough that the capsule stays a corner of the page.
    static let findFieldText: CGFloat = 128

    /// Room for the count: "No matches", the widest thing it says, measures
    /// 72.5 pt at `TypeScale.findCount`, and "888 of 888" 69 pt. The field
    /// gives way for the half point rather than the count truncating.
    static let findCountWidth: CGFloat = 72

    /// The capsule: the magnifier, the field, the count and three
    /// `controlCircle`s, with `ControlWorkingCapsule`'s ends — a third of the
    /// height before the glyph, and after the last button the gap a 28 pt
    /// circle leaves in a 36 pt capsule. 340 pt.
    static let findBarWidth: CGFloat = capsuleHeight / 3 + glyphSize + chromeGap + findFieldText + chromeGap
        + findCountWidth + chromeGap + 3 * controlCircle.width + (capsuleHeight - controlCircle.height) / 2
}
