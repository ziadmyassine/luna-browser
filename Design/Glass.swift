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
        cornerCurve: CALayerCornerCurve = .continuous
    ) -> NSView {
        GlassBackingView(style: style, cornerRadius: cornerRadius, cornerCurve: cornerCurve)
    }

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
    /// The Command Bar's scrim is the one surface in Luna that has to blur
    /// in-window content, so it is the one surface that is not glass.
    /// `NSVisualEffectView` at `.withinWindow` is the only API that does this
    /// job, it is what §9.1's "blurred backdrop scrim" describes, and it brings
    /// its own Reduce Transparency and Increase Contrast handling. It lives
    /// here, behind a name, for the same reason everything else does: so no
    /// other file has to know which material it got.
    @MainActor
    static func scrim() -> NSView {
        let view = NSVisualEffectView()
        view.blendingMode = .withinWindow
        // **The lightest in-window material that still genuinely blurs.**
        // `.hudWindow` and `.fullScreenUI` both blur beautifully and then
        // flatten everything above them into one dark plate — the Command
        // Bar's own Liquid Glass stopped looking like a material at all, and
        // the page behind it stopped being visible as context. `.sidebar` is
        // the most see-through of the in-window materials: the page is still
        // there, softened, and a glass surface on top of it still reads as
        // glass.
        view.material = .sidebar
        // Not `.followsWindowActiveState`: the bar is modal over this window
        // and a scrim that thins out when the window loses focus is a scrim
        // that stops hiding the page mid-interaction.
        view.state = .active
        // **Held just short of full strength, so the page keeps its colour.**
        //
        // Every in-window material desaturates what it blurs, and that grey is
        // what a colourful page turns into behind the bar. The material is not
        // tunable and its neighbours are no use: `.selection` barely registers,
        // `.menu` and `.underWindowBackground` take the page away entirely, and
        // a `CIColorControls` saturation boost on the layer collapses the
        // backdrop group into an opaque plate. All four were tried on screen.
        //
        // What is left is the mix. A little of the sharp, saturated page
        // composited back over the blurred one is enough to carry the colour —
        // the blur still reads as a blur, and the veil stops reading as grey.
        view.alphaValue = Tokens.Metric.scrimStrength
        return view
    }

    /// Forces the opaque chrome plane behind `view`'s glass, and drops the
    /// §2 tint while it is up.
    ///
    /// **For glass that floats over in-window content.** The material samples
    /// what is behind the *window*, so a chrome surface sliding over a live web
    /// page — §7.2's hover-peek is the only one — composites the desktop and
    /// the page together and reads as having no background at all. The plane is
    /// the same one fullscreen already puts up for the same reason: there, the
    /// thing the glass cannot see is the wallpaper; here it is the page.
    ///
    /// Idempotent, and a no-op on a view with no glass (Reduce Transparency
    /// has already made it a plane).
    @MainActor
    static func setOpaqueBackdrop(_ on: Bool, on view: NSView) {
        for backing in view.subviews.compactMap({ $0 as? GlassBackingView }) {
            backing.forcesBackdrop = on
        }
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
