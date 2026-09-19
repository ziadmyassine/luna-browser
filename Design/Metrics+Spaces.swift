//
//  Metrics+Spaces.swift
//  Luna
//
//  §8.2's Space-identity metrics. Its own file for the reason `+Effects` and
//  `+Windows` are theirs: `Metrics.swift` sits exactly on SwiftLint's 400-line
//  limit, so anything added to it has to evict something first.
//
//  The gradient *values* are in `SpacePalette.swift`; these are the sizes the
//  three intensities of §8.2a are drawn at. `spaceDot` stays in `Metrics.swift`
//  next to the §3.5 pill it lives inside.
//
//  The two menu sizes live here as well, beside the swatch that was the first of them.
//  They belong together — both are "how big is the thing to the left of a menu item's
//  word" — and neither has anywhere better to go while `Metrics.swift` sits on the line.
//

import Foundation

extension Tokens.Metric {

    /// A gradient swatch in a menu (§8.2's picker).
    ///
    /// 14 pt, and it is a ceiling rather than a preference: `NSMenuItem.image`
    /// is laid out against the menu's own font, so a swatch taller than the cap
    /// height pushes every row in the menu apart — including the rows that have
    /// no image at all.
    static let menuSwatch: CGFloat = 14

    /// §3.4a's glyph beside a menu item's word — the pin, the link, the speaker.
    ///
    /// **Two points under `menuSwatch`, and not for the same reason that one is 14.** A
    /// swatch is a solid disc and reads at whatever size it is given; a symbol is a line
    /// drawing, and at the swatch's size it was heavier than the word it sits beside and
    /// pulled the eye off the text. 12 pt sits just under the menu font's cap height,
    /// which is where a glyph stops competing with the label and starts introducing it.
    static let menuGlyph: CGFloat = 12
}
