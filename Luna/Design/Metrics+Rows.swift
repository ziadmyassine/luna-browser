//
//  Metrics+Rows.swift
//  Luna
//
//  §3.4's rows, the measurements that do not fit in Metrics.swift, which is
//  at its length limit.
//

import Foundation

extension Tokens.Metric {

    /// How far a row's icon stands above the row's middle, so it is centred
    /// on the title's letters rather than on the title's line box, which
    /// keeps room under the letters for descenders. Measured from the pixels
    /// of a row at 2×: the capitals of "New Tab" centred 1.25 pt above the
    /// row's middle and a favicon on it, so a favicon or an emoji rises 1.
    /// An SF Symbol rises by this and by however far its ink sits below its
    /// box's middle (`SymbolInk`).
    static let rowIconLift: CGFloat = 1
}
