//
//  GlassBacking.swift
//  Luna
//
//  The view behind every `Glass.apply` / `Glass.backing` call, and §2's material
//  table. Split out of `Design/Glass.swift` to keep that file the *API* — the
//  four styles and the five entry points — and this one the machinery: the
//  live Reduce Transparency swap, the fullscreen and peek backdrops, and the
//  frame discipline a glass view needs to stop it sweeping across the surface
//  every time AppKit re-lays the window out.
//
//  Contract rule 4 covers both files: `NSGlassEffectView` is named here and in
//  `Glass.swift` and nowhere else in Luna.
//

import AppKit

// MARK: - Backing

/// Hosts either real glass or, under Reduce Transparency, a solid fill — and
/// swaps between them **live**, because the user can change either
/// accessibility setting while Luna is running (§21.2).
@MainActor
final class GlassBackingView: NSView {

    private let style: Glass.Style
    private let radius: CGFloat
    private let curve: CALayerCornerCurve
    private let corners: CACornerMask
    private var glass: NSGlassEffectView?
    /// Non-nil pins this backing to one side of §7's table whatever display it
    /// lands on. Exactly one caller sets it: `Glass.previewTile`, which has to
    /// show the 1× rendering *and* the 2× one side by side on one screen.
    private let pinned: Bool?
    /// Which half of §7's table is on screen now, so a display change that
    /// resolves to the same answer costs nothing.
    private var optimised: Bool

    init(
        style: Glass.Style,
        cornerRadius: CGFloat,
        cornerCurve: CALayerCornerCurve,
        maskedCorners: CACornerMask,
        pinned: Bool? = nil
    ) {
        self.style = style
        self.radius = cornerRadius
        self.curve = cornerCurve
        self.corners = maskedCorners
        self.pinned = pinned
        // No window yet, so `isOptimised(for: nil)` is the honest answer and it
        // is the *unoptimised* one — a Retina user must see today's chrome, and
        // `viewDidMoveToWindow` re-resolves against the real screen first.
        self.optimised = pinned ?? Glass.isOptimised(for: nil)
        super.init(frame: .zero)
        Glass.beginObservingDisplayChanges()
        wantsLayer = true
        layer?.cornerCurve = cornerCurve
        // **The mask is how a circle stays a circle.** `NSGlassEffectView` has
        // no `cornerCurve` of its own, so a radius of half the side gives the
        // same superellipse `CALayer` would — the flat-flanked shape that read
        // as "longer than wide". Clipping the backing to a real arc is the only
        // lever there is, and it costs nothing on a 34 pt button.
        // The mask is how a circle stays a circle, and the only way to round
        // some corners and not others: `NSGlassEffectView` has one radius and
        // no corner set of its own, so the backing does the clipping.
        layer?.masksToBounds = cornerCurve == .circular || maskedCorners != Glass.allCorners
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

    /// Whether the opaque plane is up: fullscreen, or Reduce Transparency,
    /// which has no glass left to put anything behind.
    private var wantsOpaquePlane: Bool {
        Tokens.A11y.reduceTransparency || (isWindowFullScreen && style.hasBackdrop)
    }

    /// **No tint over the fullscreen backdrop.** §2's chrome tint is what makes
    /// the sidebar read as dense over a desktop — it is *black* in dark mode,
    /// deliberately, because the glass is sampling a bright wallpaper. In
    /// fullscreen there is no wallpaper: the glass is sampling the opaque plane
    /// below, and darkening that by half took the sidebar under the content
    /// pane's own colour. The plane is already doing the tint's job there.
    private func applyTint() {
        glass?.tintColor = wantsOpaquePlane ? nil : style.tint(optimised: optimised)
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
        // §7: the scale factor belongs to the window's **current** screen, so a
        // backing re-asks every time it changes window — and `.auto` can flip in
        // either direction on the way.
        refreshForDisplay()
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

    /// AppKit's own per-view hook for a backing-store change. It fires for every
    /// view in a window whose `backingScaleFactor` or colour space changed — but
    /// never for a view with no window, which is why `DisplayScale` watches the
    /// window-level notification too.
    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        refreshForDisplay()
    }

    /// Re-resolves §7's column for the display this view is actually on.
    func refreshForDisplay() {
        guard pinned == nil else { return }
        let wanted = Glass.isOptimised(for: window)
        guard wanted != optimised else { return }
        optimised = wanted
        rebuild()
    }

    private func rebuild() {
        glass?.removeFromSuperview()
        glass = nil

        if !Tokens.A11y.reduceTransparency {
            let view = NSGlassEffectView(frame: bounds)
            view.style = style.glassStyle(optimised: optimised)
            // When the backing is masking, the shape is the mask's; a second
            // radius inside it would round the corners the mask keeps square.
            view.cornerRadius = corners == Glass.allCorners ? radius : 0
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
        layer.cornerCurve = curve
        layer.maskedCorners = corners

        // §2 / §21.2: Reduce Transparency ⇒ solid. Fullscreen, or floating over
        // the page ⇒ the same plane *behind* the glass, because there is
        // nothing left for the material to sample.
        //
        // **Otherwise: frost.** The chrome planes carry `Surface.frost` behind
        // their glass at all times — the same grey at half strength. That is
        // what "less glass, more frosted" is: the desktop still refracts
        // through, but through a surface rather than through a hole, and the
        // density costs no darkening the way a heavier tint did.
        layer.backgroundColor = if wantsOpaquePlane {
            style.solidFallback.cgColor
        } else if style.hasBackdrop {
            Tokens.Surface.frost.cgColor
        } else {
            nil
        }

        // §2 / §21.2: Increase Contrast ⇒ a visible border on every control.
        let highContrast = Tokens.A11y.increaseContrast
        layer.borderWidth = highContrast ? Tokens.Metric.hairline : 0
        layer.borderColor = highContrast ? Tokens.Line.border.cgColor : nil
    }
}

// MARK: - §2's material table

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
