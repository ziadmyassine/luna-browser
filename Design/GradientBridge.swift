//
//  GradientBridge.swift
//  Luna
//
//  The one place BrowserKit's AppKit-free colour types become AppKit ones.
//  Colours cross that boundary as `RGBA` because BrowserKit must stay portable
//  (contract rule 2, enforced by Tools/check-no-appkit.sh); without this file
//  every view would redo the conversion by hand.
//
//  §8.2's artwork — the 12 curated pairs, the Space badge, the sidebar wash,
//  the content-edge glow — is deliberately not here. This is the bridge.
//

import AppKit
import BrowserKit

extension NSColor {
    /// A page's `themeColor`, a Space gradient stop — anything that arrived as
    /// `RGBA`. Always sRGB, because `RGBA` is documented as sRGB.
    convenience init(_ rgba: RGBA) {
        self.init(srgbRed: rgba.r, green: rgba.g, blue: rgba.b, alpha: rgba.a)
    }

    /// The reverse trip, for state that goes back into the store.
    func rgba(for appearance: NSAppearance) -> RGBA {
        let components = srgbComponents(for: appearance)
        return RGBA(r: components.red, g: components.green, b: components.blue, a: components.alpha)
    }
}

extension NSGradient {
    /// A Space's two-stop gradient (§8.2).
    ///
    /// Fails only if AppKit rejects the stops, which sRGB components in 0...1
    /// never do, so a `!` at the call site is safe. The initialiser stays
    /// failable because `NSGradient`'s is.
    convenience init?(_ pair: GradientPair) {
        self.init(starting: NSColor(pair.start), ending: NSColor(pair.end))
    }
}
