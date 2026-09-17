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
    static func backing(_ style: Style, cornerRadius: CGFloat = 0) -> NSView {
        GlassBackingView(style: style, cornerRadius: cornerRadius)
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
    static func apply(_ style: Style, to view: NSView, cornerRadius: CGFloat = 0) -> NSView {
        for existing in view.subviews where existing is GlassBackingView {
            existing.removeFromSuperview()
        }
        let backing = backing(style, cornerRadius: cornerRadius)
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
        return view
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

// MARK: - Backing

/// Hosts either real glass or, under Reduce Transparency, a solid fill — and
/// swaps between them **live**, because the user can change either
/// accessibility setting while Luna is running (§21.2).
@MainActor
private final class GlassBackingView: NSView {

    private let style: Glass.Style
    private let radius: CGFloat
    private var glass: NSGlassEffectView?

    init(style: Glass.Style, cornerRadius: CGFloat) {
        self.style = style
        self.radius = cornerRadius
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        rebuild()
        // NotificationCenter holds observers weakly and zeroes them on dealloc,
        // so there is nothing to remove — which keeps `deinit` free of the
        // main-actor hop Swift 6 would otherwise demand.
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(accessibilityDisplayOptionsChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    override var wantsUpdateLayer: Bool { true }

    /// **Framed by hand, never by `autoresizingMask`.**
    ///
    /// A backing is built before its host has a size, so the glass inside it
    /// starts at `.zero` — and autoresizing cannot scale a zero frame, so it
    /// stayed zero for the life of the window. Two consequences, both of which
    /// shipped: the sidebar had no glass over most of its height (the effect
    /// covered a strip at the bottom and nothing else), and the required
    /// `NSAutoresizingMaskLayoutConstraint`s AppKit derives from that stale
    /// frame — `V:|-(6790)-[glass]` — became part of the window's fitting
    /// size, ratcheting the window taller on every layout pass until it was
    /// 6800 pt tall with its bottom bar far below the screen.
    ///
    /// Setting the frame here is the fix: the derived constraints collapse to
    /// "fill the backing", which is what they were always meant to say.
    override func layout() {
        super.layout()
        // **Actions off.** A layout pass can run inside somebody else's
        // animation transaction — AppKit restoring a window from Stage Manager
        // is one — and an implicitly animated `frame` on a glass view sweeps
        // the effect across the surface over the next few frames. That sweep is
        // the flash: the sidebar is briefly glass over nothing. The frame is a
        // consequence of the layout, never something to animate.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        glass?.frame = bounds
        CATransaction.commit()
    }

    /// §21 / item 8: **glass has nothing to sample in fullscreen.**
    ///
    /// `NSGlassEffectView` composites what is behind the window, and in
    /// fullscreen there is no desktop behind it — so the sidebar renders as
    /// very nearly black in dark mode and very nearly white in light. The
    /// backdrop is the same opaque plane Reduce Transparency already falls back
    /// to, painted *under* the glass rather than instead of it: dark grey in
    /// dark, light grey in light, with the material still on top of it.
    ///
    /// It is only painted in fullscreen. Painting it always would be sampled by
    /// the glass in every window state and the wallpaper would stop coming
    /// through, which is the whole look.
    private var isWindowFullScreen = false {
        didSet {
            guard isWindowFullScreen != oldValue else { return }
            applyTint()
            needsDisplay = true
        }
    }

    /// **No tint over the fullscreen backdrop.** §2's chrome tint is what makes
    /// the sidebar read as dense over a desktop — it is *black* in dark mode,
    /// deliberately, because the glass is sampling a bright wallpaper. In
    /// fullscreen there is no wallpaper: the glass is sampling the opaque plane
    /// below, and darkening that by half took the sidebar under the content
    /// pane's own colour. The plane is already doing the tint's job there.
    private func applyTint() {
        glass?.tintColor = isWindowFullScreen && style.hasBackdrop ? nil : style.tint
    }

    /// **The plane goes up on `will`, and comes down on `did`.**
    ///
    /// `styleMask` does not carry `.fullScreen` until the transition finishes,
    /// so reading it on `didEnterFullScreen` meant the sidebar spent the whole
    /// half-second zoom as glass with nothing behind it — black — and only
    /// turned grey once the window had landed. Entering is therefore driven by
    /// `willEnterFullScreen`, which fires before the first frame of the zoom,
    /// and leaving by `didExitFullScreen`, so the plane is still there for the
    /// zoom back out. Both edges then happen while there is no desktop to
    /// sample, which is the only time the plane is wanted.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        isWindowFullScreen = window?.styleMask.contains(.fullScreen) ?? false
        guard let window else { return }
        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(windowWillEnterFullScreen),
            name: NSWindow.willEnterFullScreenNotification,
            object: window
        )
        center.addObserver(
            self,
            selector: #selector(windowDidExitFullScreen),
            name: NSWindow.didExitFullScreenNotification,
            object: window
        )
        center.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: NSWindow.didDeminiaturizeNotification,
            object: window
        )
    }

    /// **Settles the material the instant the app comes back.**
    ///
    /// Returning from the Dock, from Stage Manager or from another app runs a
    /// layout pass inside AppKit's own animation transaction, and an implicitly
    /// animated frame on a glass view sweeps the effect across the surface over
    /// the next few frames — which is what the sidebar's flash looked like.
    /// `layout()` already disables actions; this puts the frame back *before*
    /// the first frame is composited rather than waiting for the pass that
    /// transaction schedules.
    @objc private func applicationDidBecomeActive() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        glass?.frame = bounds
        layer?.displayIfNeeded()
        CATransaction.commit()
    }

    @objc private func windowWillEnterFullScreen() {
        isWindowFullScreen = true
    }

    @objc private func windowDidExitFullScreen() {
        isWindowFullScreen = false
    }

    /// Solid under Reduce Transparency, so AppKit can skip what is behind it.
    override var isOpaque: Bool { Tokens.A11y.reduceTransparency }

    @objc private func accessibilityDisplayOptionsChanged() {
        rebuild()
    }

    private func rebuild() {
        glass?.removeFromSuperview()
        glass = nil

        if !Tokens.A11y.reduceTransparency {
            let view = NSGlassEffectView(frame: bounds)
            view.style = style.glassStyle
            view.cornerRadius = radius
            // §2: the chrome planes are tinted so they read as surfaces rather
            // than as a pane of wallpaper. Controls are not — `.clear` glass
            // over an already-tinted bar is what makes them read as raised.
            view.tintColor = nil
            // The header only guarantees placement for `contentView`, so give
            // it an empty one rather than relying on a bare glass view.
            view.contentView = NSView(frame: bounds)
            addSubview(view)
            glass = view
            applyTint()
        }

        needsDisplay = true
    }

    /// Called with this view's effective appearance already current, so the
    /// dynamic tokens below resolve for the right theme and contrast setting.
    override func updateLayer() {
        guard let layer else { return }
        layer.cornerRadius = radius

        // §2 / §21.2: Reduce Transparency ⇒ solid. Fullscreen ⇒ the same plane
        // *behind* the glass, because there is no desktop left to sample.
        let needsPlane = Tokens.A11y.reduceTransparency || (isWindowFullScreen && style.hasBackdrop)
        layer.backgroundColor = needsPlane ? style.solidFallback.cgColor : nil

        // §2 / §21.2: Increase Contrast ⇒ a visible border on every control.
        let highContrast = Tokens.A11y.increaseContrast
        layer.borderWidth = highContrast ? Tokens.Metric.hairline : 0
        layer.borderColor = highContrast ? Tokens.Line.border.cgColor : nil
    }
}

// MARK: - §2's material table

private extension Glass.Style {

    var glassStyle: NSGlassEffectView.Style {
        switch self {
        case .sidebar, .topBar, .popover: .regular
        case .control: .clear
        }
    }

    /// The §2 tint handed to `NSGlassEffectView`, or nil for the surfaces that
    /// take the material neat.
    var tint: NSColor? {
        switch self {
        case .sidebar, .topBar: Tokens.Surface.glassTint
        case .control, .popover: nil
        }
    }

    /// Whether this surface paints its `solidFallback` behind the glass when
    /// the window is fullscreen. The chrome planes do — they are what the user
    /// is looking at and they would otherwise be black. Controls do not: a
    /// control's job is to read as raised above whatever the plane became.
    var hasBackdrop: Bool {
        switch self {
        case .sidebar, .topBar: true
        case .control, .popover: false
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
