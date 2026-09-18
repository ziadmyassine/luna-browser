//
//  Glass.swift
//  Luna
//
//  THE ONLY FILE IN LUNA PERMITTED TO TOUCH LIQUID GLASS (contract rule 4, §0.3).
//  Every other file asks for a style by name. One wrong API guess here would
//  spread through every chrome surface in the app, which is exactly what §0.3
//  exists to prevent — so nothing below is guessed.
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
//  Both compile and link under `-swift-version 6 -strict-concurrency=complete`
//  at `-target arm64-apple-macos26.0`. There is **no** `NSLiquidGlass*` type and
//  no "heavy"/"thick" style: the SDK ships exactly the two above.
//
//  Two spec consequences worth knowing:
//    · §2 asks for "Liquid Glass, heavier" for the downloads popover. That
//      style does not exist. The popover uses `.regular` and gets its extra
//      weight from the shadow §5 already requires on its `NSPanel`.
//    · The deployment target is macOS 26.0 and `NSGlassEffectView` is macOS
//      26.0, so there is no OS Luna runs on where glass is missing. §8.4's
//      `NSVisualEffectView` fallback would be dead code and is not built; the
//      path that *does* run is Reduce Transparency, which §2 requires to be
//      solid colour — vibrancy is not an acceptable answer to "reduce
//      transparency" anyway.
//
//  §7's 1× adaptation lives next door in `DisplayScale.swift`, which owns the
//  setting, the detection and the re-skin pass. What lives *here* is the only
//  part of it that touches the material: the `optimised` parameter threaded
//  through the style table at the bottom of this file. Nothing else in Luna
//  may read it.
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
        // The mask is enough for the *backing*: its margins are zero, so the
        // constraints AppKit derives read "fill", whatever size it starts at.
        // What could not survive a zero start is the glass inside it — see
        // `GlassBackingView.layout()`.
        backing.autoresizingMask = [.width, .height]
        view.addSubview(backing, positioned: .below, relativeTo: nil)
        return backing
    }

    /// A **within-window** backdrop: blurs what is inside the window behind it.
    ///
    /// **Liquid Glass cannot do this, and that is not a limitation to work
    /// around — it is what the material is.** `NSGlassEffectView` composites
    /// what is behind the *window*: the desktop, the wallpaper, another app.
    /// Put it over a live web page in the same window and the page is not
    /// blurred, it is *replaced* — and in fullscreen, where there is no desktop
    /// to sample at all, it goes very nearly black and the page behind the
    /// Command Bar vanished completely.
    ///
    /// The Command Bar's backdrop is the one surface in Luna that has to blur
    /// in-window content, so it is the one surface that is not glass.
    /// `NSVisualEffectView` at `.withinWindow` is the only API that does this
    /// job, it is what §9.1's "blurred backdrop scrim" describes, and it brings
    /// its own Reduce Transparency and Increase Contrast handling. It lives
    /// here, behind a name, for the same reason everything else does: so no
    /// other file has to know which material it got.
    ///
    /// **At full strength, and frosted like §7.2's peeked sidebar** — see
    /// `GlassScrim.swift` for the measurement that says why a partial
    /// `alphaValue` was a grey film rather than a blur, and for what the peek
    /// and this surface can and cannot have in common.
    @MainActor
    static func scrim() -> NSView {
        GlassScrimView()
    }

    /// §7.2's peeked sidebar: **the chrome plane, as a plane of its own.**
    ///
    /// The window's own glass is behind the content pane, not in front of it,
    /// so a sidebar sliding over the page had nothing under it at all and the
    /// page showed through the gaps between its rows. This is the same
    /// `.sidebar` material the window is made of, standing on its own in front
    /// of the pane — so the peeked sidebar wears over a website exactly the
    /// finish it wears over the wallpaper: the desktop through the glass,
    /// §2's frost behind it and §2's tint in it.
    ///
    /// It does not blur the *page* — no material can. `NSGlassEffectView`
    /// composites what is behind the window, and `NSVisualEffectView` at
    /// `.withinWindow` will not sample a `WKWebView`'s out-of-process layer.
    /// Both were tried on screen. What the material *does* give is the right
    /// surface, which is what "floating" meant.
    @MainActor
    static func peekPlane() -> NSView {
        // **Rounded on the trailing edge, and nowhere else.** §3.6's content
        // pane rounds the edge that is not a window edge — the one it shares
        // with the sidebar — and a peeked sidebar is that same seam read the
        // other way round: the pane is flush to the window here, and the
        // sidebar is the thing floating in front of it, so the corner belongs
        // to the sidebar.
        // **And rimmed**, which is the other half of the same seam. Where the
        // sidebar is *not* floating, the page's own leading hairline draws the
        // join; floating over the page there is no page edge to draw it, so the
        // plane carries the edge itself.
        backing(
            .sidebar,
            cornerRadius: Tokens.Metric.contentCardRadius,
            maskedCorners: [.layerMaxXMinYCorner, .layerMaxXMaxYCorner],
            rimmed: true
        )
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
