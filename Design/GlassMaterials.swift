//
//  GlassMaterials.swift
//  Luna
//
//  §2's material table: what each of `Glass.Style`'s four surfaces is made of.
//  The `NSGlassEffectView` style, the tint, the fullscreen backdrop and §2a's
//  frost, read by `GlassBackingView` and nothing else.
//
//  Split out of GlassBacking.swift for that file's length limit. The seam is
//  right: that file is the view — the live Reduce Transparency swap, the
//  fullscreen edges, the frame discipline — and this is the table it reads.
//  Contract rule 4 still covers this file, because `glassStyle(optimised:)`
//  names `NSGlassEffectView` in its return type.
//

import AppKit

extension Glass.Style {

    /// §7: at 1×, `.clear` transmits 2.5× more backdrop structure than
    /// `.regular` — measured — and the row backing is where that shows.
    func glassStyle(optimised: Bool) -> NSGlassEffectView.Style {
        switch self {
        case .sidebar, .topBar, .popover: .regular
        case .control: optimised ? .regular : .clear
        }
    }

    /// The §2 tint handed to `NSGlassEffectView`, or nil for the surfaces that
    /// take the material neat.
    func tint(optimised: Bool) -> NSColor? {
        switch self {
        case .sidebar, .topBar: optimised ? Tokens.Surface.glassTintDense : Tokens.Surface.glassTint
        case .control: optimised ? Tokens.Surface.glassTintControl : nil
        case .popover: nil
        }
    }

    /// Whether this surface paints its `solidFallback` behind the glass in
    /// fullscreen. The chrome planes do — they are what the user is looking at,
    /// and they would otherwise be black. Controls do not: a control's job is
    /// to read as raised above whatever the plane became.
    var hasBackdrop: Bool {
        switch self {
        case .sidebar, .topBar: true
        case .control, .popover: false
        }
    }

    /// §2's frost — the plane painted behind this surface's glass in every
    /// window state — or nil for the surfaces that take the material neat.
    ///
    /// Not the same question as `hasBackdrop`. That one is about fullscreen,
    /// where the material stands down and the plane replaces it; this is the
    /// plane the glass sits on and samples through, which is how the popover
    /// gains one at `.opaque` without becoming a flat plate when the window is
    /// zoomed.
    ///
    /// A control never gets one at either density: it is a small shape over an
    /// already-frosted bar, and frosting it would leave it reading as a hole
    /// rather than as something raised (§2).
    func frost(_ density: GlassDensity) -> NSColor? {
        switch (self, density) {
        case (.sidebar, .clear), (.topBar, .clear): Tokens.Surface.frost
        case (.sidebar, .opaque), (.topBar, .opaque): Tokens.Surface.frostOpaque
        case (.popover, .opaque): Tokens.Surface.popoverFrostOpaque
        case (.popover, .clear), (.control, _): nil
        }
    }

    /// What this surface becomes when Reduce Transparency is on (§2, §21.2).
    var solidFallback: NSColor {
        switch self {
        // The chrome plane. Not `Surface.base`: the §3.6 content card is
        // `base`, and a sidebar the same colour as the card is not a sidebar.
        case .sidebar, .topBar: Tokens.Surface.glassFallback
        // Controls and the popover already read as raised above the bar.
        case .control, .popover: Tokens.Surface.raised
        }
    }
}
