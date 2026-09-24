//
//  CommandBarAnchor.swift
//  Luna
//
//  What §9.1's bar grows out of, when it grows out of something.
//
//  Its own file rather than a nested type on the panel: the controller takes
//  one from the caller, the panel reads it every layout pass, and §3.2, §3.2b
//  and §4's tabs all build one.
//

import AppKit

/// Where the bar grows from, when it grows out of an address pill rather
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

    /// The pill. Hidden for as long as the bar stands in its place — the
    /// bar's own input row shows what the pill was showing, and two of them on
    /// the same 34 pt would be the address drawn twice.
    let view: NSView

    /// The bar has closed and the pill is its own again. §3.2b's bar takes
    /// itself back from the open state it went into to be typed in.
    var onDismiss: (() -> Void)?

    /// The span the bar may widen into, when it is not the whole window.
    ///
    /// §4's tab sits in the titlebar, where the traffic lights and back and
    /// forward are to its left: a bar wider than the tab, clamped only to the
    /// window's edge, opened over the lights. Nil for the address pills, whose
    /// bar may use the window.
    var span: NSView?

    /// The corner the anchor is drawn with, which is the corner the bar opens
    /// from and folds back into. Nil for the address pills, whose corner is
    /// already the bar's (`CommandBarPanel.bodyRadius`).
    var cornerRadius: CGFloat?

    /// A second click on the bar while it is still where the anchor was, within
    /// the double-click interval, closes it and calls this once it has folded.
    ///
    /// §4's tab opens the bar on the first click, and a double-click renames
    /// the tab. Waiting out the interval before opening kept the two apart
    /// and made every single click half a second late; this keeps them apart
    /// the other way round.
    var onDoubleClick: (() -> Void)?

    init(
        view: NSView,
        span: NSView? = nil,
        cornerRadius: CGFloat? = nil,
        onDoubleClick: (() -> Void)? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        self.view = view
        self.span = span
        self.cornerRadius = cornerRadius
        self.onDoubleClick = onDoubleClick
        self.onDismiss = onDismiss
    }
}
