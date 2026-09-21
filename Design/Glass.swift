//
//  Glass.swift
//  Luna
//
//  THE ONLY FILE IN LUNA PERMITTED TO TOUCH LIQUID GLASS (contract rule 4,
//  §0.3). Every other file asks for a style by name.
//
//  VERIFIED against the installed SDK, not remembered:
//    MacOSX26.5.sdk/System/Library/Frameworks/AppKit.framework/.../NSGlassEffectView.h
//
//      NS_ENUM NSGlassEffectViewStyle { Regular, Clear }
//          NS_SWIFT_NAME(NSGlassEffectView.Style)  →  .regular / .clear
//      @interface NSGlassEffectView : NSView          API_AVAILABLE(macos(26.0))
//          contentView: __kindof NSView?   cornerRadius: CGFloat
//          tintColor: NSColor?             style: NSGlassEffectView.Style
//      @interface NSGlassEffectContainerView : NSView API_AVAILABLE(macos(26.0))
//          contentView: __kindof NSView?   spacing: CGFloat
//
//  There is no `NSLiquidGlass*` type and no "heavy" or "thick" style: the SDK
//  ships exactly the two above. Two consequences:
//    · §2 asks for "Liquid Glass, heavier" where a surface floats above the
//      chrome rather than being part of it. That style does not exist; those
//      surfaces use `.regular` and get their weight from `Shadow.popover`.
//    · The deployment target is macOS 26.0 and so is `NSGlassEffectView`, so
//      §8.4's `NSVisualEffectView` fallback would be dead code and is not
//      built. The path that does run is Reduce Transparency, which §2 requires
//      to be solid colour.
//
//  §7's 1× adaptation lives in DisplayScale.swift. The only part of it here is
//  the `optimised` parameter threaded through the style table; nothing else in
//  Luna may read it.
//

import AppKit

enum Glass {

    /// The four chrome materials of §2.
    enum Style: Sendable, CaseIterable {
        /// Liquid Glass, regular.
        case sidebar
        /// Liquid Glass, regular.
        case topBar
        /// Liquid Glass, clear — action capsule, control buttons, Essentials tiles.
        case control
        /// Liquid Glass, regular, over its own shadow (§5).
        case popover
    }

    /// A fresh glass view, ready to be positioned by the caller.
    ///
    /// `cornerRadius` defaults to 0 for the edge-to-edge surfaces; pass the
    /// matching `Tokens.Metric` radius for anything rounded.
    @MainActor
    static func backing(
        _ style: Style,
        cornerRadius: CGFloat = 0,
        cornerCurve: CALayerCornerCurve = .continuous,
        maskedCorners: CACornerMask = Glass.allCorners,
        rimmed: Bool = false
    ) -> NSView {
        GlassBackingView(
            style: style,
            cornerRadius: cornerRadius,
            cornerCurve: cornerCurve,
            maskedCorners: maskedCorners,
            rimmed: rimmed
        )
    }

    /// The default for `maskedCorners`: all four, which is what a radius means
    /// unless a caller says otherwise.
    static let allCorners: CACornerMask = [
        .layerMinXMinYCorner, .layerMinXMaxYCorner,
        .layerMaxXMinYCorner, .layerMaxXMaxYCorner
    ]

    /// Puts `style` behind `view`'s own content, resizing with it.
    ///
    /// Idempotent: calling it again replaces the previous backing rather than
    /// stacking a second one.
    ///
    /// - Returns: the backing, for the callers that fade it — §3.1's sidebar
    ///   toggle carries its glass only while the pointer is on it.
    @discardableResult
    @MainActor
    static func apply(
        _ style: Style,
        to view: NSView,
        cornerRadius: CGFloat = 0,
        cornerCurve: CALayerCornerCurve = .continuous
    ) -> NSView {
        for existing in view.subviews where existing is GlassBackingView {
            existing.removeFromSuperview()
        }
        let backing = backing(style, cornerRadius: cornerRadius, cornerCurve: cornerCurve)
        backing.frame = view.bounds
        // The mask is enough for the backing: its margins are zero, so the
        // constraints AppKit derives read "fill" whatever size it starts at.
        // What could not survive a zero start is the glass inside it — see
        // `GlassBackingView.layout()`.
        backing.autoresizingMask = [.width, .height]
        view.addSubview(backing, positioned: .below, relativeTo: nil)
        return backing
    }

    // THERE IS NO `scrim()`, and the gap is deliberate. Liquid Glass cannot
    // blur in-window content: it composites what is behind the window, so
    // over a live page it replaces the page and in fullscreen it goes
    // near-black. §9.1's "blurred backdrop scrim" was therefore the one surface
    // built from `NSVisualEffectView` at `.withinWindow`. It worked, and it was
    // then cut — the Command Bar does not want a backdrop at all.
    // `CommandBarPanel` floats over the page as it is, and its own full-window
    // view still swallows the clicks. The finding is kept in `peekPlane`, where
    // it still decides something.

    /// §7.2's peeked sidebar: the chrome plane, as a plane of its own.
    ///
    /// The window's own glass is behind the content pane, not in front of it,
    /// so a sidebar sliding over the page had nothing under it and the page
    /// showed through the gaps between its rows. This is the same `.sidebar`
    /// material standing on its own in front of the pane, so the peeked sidebar
    /// wears over a website exactly the finish it wears over the wallpaper.
    ///
    /// It does not blur the page, and no material can: `NSGlassEffectView`
    /// composites what is behind the window, and `NSVisualEffectView` at
    /// `.withinWindow` will not sample a `WKWebView`'s out-of-process layer.
    /// Both were tried on screen.
    @MainActor
    static func peekPlane(on edge: SidebarEdge = .leading) -> NSView {
        // Rounded on the edge it shares with the page and nowhere else. §3.6's
        // content pane rounds the edge that is not a window edge; a peeked
        // sidebar is that seam read the other way round, so the corner belongs
        // to the sidebar. Rimmed for the same reason: where the sidebar is not
        // floating the page's own leading hairline draws the join, and over the
        // page there is no page edge to draw it.
        backing(
            .sidebar,
            cornerRadius: Tokens.Metric.contentCardRadius,
            maskedCorners: peekCorners(on: edge),
            rimmed: true
        )
    }

    /// Moves a plane built by `peekPlane` to the other edge.
    ///
    /// The plane lives for the window's lifetime, so changing sides is a mask
    /// change rather than a rebuild. It stays in this file, which is the only
    /// one allowed to know what a glass backing is made of (contract rule 4).
    @MainActor
    static func setPeekEdge(_ edge: SidebarEdge, on plane: NSView) {
        (plane as? GlassBackingView)?.maskedCorners = peekCorners(on: edge)
    }

    private static func peekCorners(on edge: SidebarEdge) -> CACornerMask {
        edge == .trailing
            ? [.layerMinXMinYCorner, .layerMinXMaxYCorner]
            : [.layerMaxXMinYCorner, .layerMaxXMaxYCorner]
    }

    /// Merges glass surfaces that sit within `spacing` of each other into one —
    /// the §3.1 control cluster, the §3.3 Essentials grid, the §4 action
    /// capsule. Apple documents this as a render-pass saving, so use it
    /// wherever glass elements are adjacent.
    ///
    /// - Returns: a view to place in the hierarchy. Lay `content` out as usual;
    ///   the container re-parents it.
    @MainActor
    static func merging(_ content: NSView, spacing: CGFloat) -> NSView {
        let container = NSGlassEffectContainerView(frame: content.bounds)
        container.spacing = spacing
        container.contentView = content
        return container
    }
}
