//
//  ExtensionShelfFit.swift
//  Luna
//
//  How many pinned extensions a surface shows: as many as fit in the room it
//  can spare, in pin order, and the rest are one press away in the pop-out.
//
//  Each surface decides its own room — the sidebar's pill keeps half of
//  itself for the address, the page bar keeps half its pill, the top bar keeps
//  two tabs' worth of strip (`Metrics+Extensions.swift`) — and all three count
//  the same way, so the rule is one function with a test.
//

import CoreGraphics

enum ExtensionShelfFit {

    /// How many of `pinned` buttons, each `pitch` wide with `gap` between
    /// neighbours, fit in `room`.
    static func count(_ pinned: Int, room: CGFloat, pitch: CGFloat, gap: CGFloat = 0) -> Int {
        guard pinned > 0, pitch > 0, room >= pitch else { return 0 }
        return min(pinned, Int(((room + gap) / (pitch + gap)).rounded(.down)))
    }
}
