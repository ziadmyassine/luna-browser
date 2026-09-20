//
//  CommandBarAnchor.swift
//  Luna
//
//  What §9.1's bar grows out of, when it grows out of something.
//
//  Its own file rather than a nested type on the panel: the controller takes
//  one from the caller, the panel reads it every layout pass, and §3.2 and
//  §3.2b both build one — four files for a type that is two properties and a
//  paragraph of why.
//

import AppKit

/// Where the bar grows from, when it grows out of an **address pill** rather
/// than floating over the page.
///
/// §3.2's pill and §3.2b's both hand the whole job over — the field, the
/// history, the ranking and the list are all §9.1's, and neither pill has any
/// of them. A panel that answered a click on a bar at the edge of the window by
/// opening a second surface in the middle of it was two controls pretending not
/// to be related. Anchored, the panel takes the pill's exact place and grows
/// down out of it: the same glass, at the same width, with more of it.
@MainActor
struct CommandBarAnchor {

    /// The pill. **Hidden for as long as the bar stands in its place** — the
    /// bar's own input row shows what the pill was showing, and two of them on
    /// the same 34 pt would be the address drawn twice.
    let view: NSView

    /// The bar has closed and the pill is its own again. §3.2b's bar takes
    /// itself back from the open state it went into to be typed in.
    var onDismiss: (() -> Void)?

    init(view: NSView, onDismiss: (() -> Void)? = nil) {
        self.view = view
        self.onDismiss = onDismiss
    }
}
