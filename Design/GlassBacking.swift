//
//  GlassBacking.swift
//  Luna
//
//  The view behind every `Glass.apply` / `Glass.backing` call. Glass.swift is
//  the API — the four styles and the five entry points — and this is the
//  machinery: the live Reduce Transparency swap, the fullscreen and peek
//  backdrops, and the frame discipline that stops a glass view sweeping across
//  the surface every time AppKit re-lays the window out.
//
//  §2's material table is next door in GlassMaterials.swift.
//
//  Contract rule 4 covers all three: `NSGlassEffectView` is named here, in
//  `Glass.swift` and in `GlassMaterials.swift`, and nowhere else in Luna.
//

import AppKit

// MARK: - Backing

/// Hosts either real glass or, under Reduce Transparency, a solid fill, and
/// swaps between them live — the user can change either accessibility setting
/// while Luna is running (§21.2).
@MainActor
final class GlassBackingView: NSView {

    private let style: Glass.Style
    private let radius: CGFloat
    private let curve: CALayerCornerCurve
    private var corners: CACornerMask

    /// Which corners the radius applies to.
    ///
    /// Settable for exactly one caller: §7.2's peek plane rounds the edge it
    /// shares with the page, and that edge moves when the sidebar changes
    /// sides. Everything else passes its mask in and never looks at it again.
    var maskedCorners: CACornerMask {
        get { corners }
        set {
            guard newValue != corners else { return }
            corners = newValue
            layer?.masksToBounds = curve == .circular || newValue != Glass.allCorners
            needsDisplay = true
        }
    }
    /// §7.2's floating sidebar: the rim that separates a plane from whatever it
    /// is floating over. See `Glass.peekPlane`.
    private let rimmed: Bool
    private var glass: NSGlassEffectView?
    /// §2's chrome tint, painted by Luna for the length of a window that is not
    /// the active one. See `isSurfaceActive`.
    private let tintPlate = NSView()
    /// Non-nil pins this backing to one side of §7's table whatever display it
    /// lands on. Exactly one caller sets it: `Glass.previewTile`, which has to
    /// show the 1× rendering and the 2× one side by side on one screen.
    private let pinned: Bool?
    /// Which half of §7's table is on screen now, so a display change that
    /// resolves to the same answer costs nothing.
    private var optimised: Bool

    init(
        style: Glass.Style,
        cornerRadius: CGFloat,
        cornerCurve: CALayerCornerCurve,
        maskedCorners: CACornerMask,
        rimmed: Bool = false,
        pinned: Bool? = nil
    ) {
        self.style = style
        self.radius = cornerRadius
        self.curve = cornerCurve
        self.corners = maskedCorners
        self.rimmed = rimmed
        self.pinned = pinned
        // No window yet, so `isOptimised(for: nil)` is the honest answer and it
        // is the unoptimised one — a Retina user must see today's chrome, and
        // `viewDidMoveToWindow` re-resolves against the real screen first.
        self.optimised = pinned ?? Glass.isOptimised(for: nil)
        super.init(frame: .zero)
        Glass.beginObservingDisplayChanges()
        wantsLayer = true
        layer?.cornerCurve = cornerCurve
        // The mask is how a circle stays a circle, and the only way to round
        // some corners and not others. `NSGlassEffectView` has one radius and no
        // `cornerCurve`, so a radius of half the side gives the same
        // flat-flanked superellipse `CALayer` would — the shape that read as
        // "longer than wide". Clipping the backing to a real arc is the only
        // lever, and it costs nothing on a 34 pt button.
        layer?.masksToBounds = cornerCurve == .circular || maskedCorners != Glass.allCorners
        tintPlate.wantsLayer = true
        tintPlate.layer?.cornerCurve = cornerCurve
        tintPlate.layer?.cornerRadius = maskedCorners == Glass.allCorners ? cornerRadius : 0
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

    /// Framed by hand, never by `autoresizingMask`.
    ///
    /// A backing is built before its host has a size, so the glass inside it
    /// starts at `.zero`, and autoresizing cannot scale a zero frame — it stayed
    /// zero for the life of the window. Both consequences shipped: the sidebar
    /// had glass over a strip at the bottom and nothing else, and the
    /// `NSAutoresizingMaskLayoutConstraint`s AppKit derives from that stale
    /// frame — `V:|-(6790)-[glass]` — joined the window's fitting size and
    /// ratcheted it to 6800 pt tall, bottom bar far below the screen.
    override func layout() {
        super.layout()
        // Actions off. A layout pass can run inside somebody else's animation
        // transaction — AppKit restoring a window from Stage Manager is one —
        // and an implicitly animated `frame` on a glass view sweeps the effect
        // across the surface over the next few frames. That sweep is the flash:
        // the sidebar is briefly glass over nothing.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        glass?.frame = bounds
        CATransaction.commit()
    }

    /// §21 / item 8: glass has nothing to sample in fullscreen.
    ///
    /// `NSGlassEffectView` composites what is behind the window, and in
    /// fullscreen there is no desktop behind it — the sidebar renders very
    /// nearly black in dark mode and very nearly white in light. The backdrop is
    /// a plate of its own, `Tokens.Surface.fullScreenChrome`, painted instead of
    /// the material rather than under it (`wantsFlatPlane`).
    ///
    /// Only in fullscreen: painted always, the glass would sample it in every
    /// window state and the wallpaper would stop coming through.
    private var isWindowFullScreen = false {
        didSet {
            guard isWindowFullScreen != oldValue else { return }
            applyTint()
            glass?.isHidden = wantsFlatPlane
            needsDisplay = true
        }
    }

    /// Whether the opaque plane is up: fullscreen, or Reduce Transparency,
    /// which has no glass left to put anything behind.
    private var wantsOpaquePlane: Bool {
        Tokens.A11y.reduceTransparency || wantsFlatPlane
    }

    /// In fullscreen the chrome is a plate and the material stands down.
    ///
    /// There is nothing behind the window to refract, so the glass on top was
    /// not a refraction of anything — only a film that lifted the plane a few
    /// steps and made its colour un-nameable. No value for the plane fixes that
    /// while something else is painted over it, so the glass is hidden for the
    /// length of fullscreen and `Tokens.Surface.fullScreenChrome` is the colour
    /// exactly.
    ///
    /// Only the surfaces with a backdrop: a control's glass in fullscreen is
    /// still reading as raised above the plate, which is its job.
    ///
    /// And not the plane a peeked sidebar floats on. `rimmed` means "this
    /// surface is over the page rather than part of the window's own chrome".
    /// Flattening it made a panel meant to read as floating look like a hole cut
    /// in the page, so it keeps its material in every window state.
    private var wantsFlatPlane: Bool { isWindowFullScreen && style.hasBackdrop && !rimmed }

    /// Whether this surface is in the window the user is working in.
    ///
    /// Both halves matter. An app that is not frontmost has no active window at
    /// all, and an app that is frontmost has exactly one — Settings in front of
    /// a browser window leaves the browser's chrome inactive behind it.
    private var isSurfaceActive: Bool {
        NSApp.isActive && (window?.isMainWindow ?? false)
    }

    /// No tint over the fullscreen backdrop. §2's chrome tint is black in dark
    /// mode because the glass is sampling a bright wallpaper; in fullscreen it
    /// is sampling the opaque plane below, and darkening that by half took the
    /// sidebar under the content pane's own colour.
    ///
    /// The same tint is painted by hand while the window is not the active one,
    /// and that is the whole of `tintPlate`. `NSGlassEffectView` drops
    /// `tintColor` the moment its window stops being active — measured, by
    /// sampling the sidebar in both states: the difference was §2's tint
    /// exactly, black at `Ink.glassTint`, and the column came up a third
    /// brighter every time the user clicked into another app. AppKit offers no
    /// equivalent of `NSVisualEffectView.state` here, so the tint the material
    /// stops applying is applied over it instead. It is the same colour in both
    /// states; only which layer carries it changes.
    private func applyTint() {
        let tint = wantsOpaquePlane ? nil : style.tint(optimised: optimised)
        glass?.tintColor = tint
        // Resolved against this view's own appearance. A notification arrives
        // with whatever appearance was current where it was posted, and a
        // dynamic colour asked for `cgColor` there answers for the wrong theme.
        effectiveAppearance.performAsCurrentDrawingAppearance {
            Tokens.Motion.wash(tintPlate.layer, to: isSurfaceActive ? nil : tint)
        }
    }

    /// The plane goes up on `will` and comes down on `did`.
    ///
    /// `styleMask` does not carry `.fullScreen` until the transition finishes,
    /// so reading it on `didEnterFullScreen` left the sidebar black for the
    /// whole half-second zoom. Entering is driven by `willEnterFullScreen`,
    /// which fires before the first frame, and leaving by `didExitFullScreen`,
    /// so the plane is still there for the zoom back out.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // §7: the scale factor belongs to the window's current screen, so a
        // backing re-asks every time it changes window, and `.auto` can flip in
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
        for name in [
            NSApplication.didBecomeActiveNotification,
            NSApplication.didResignActiveNotification
        ] {
            center.addObserver(self, selector: #selector(activationChanged), name: name, object: nil)
        }
        for name in [NSWindow.didBecomeMainNotification, NSWindow.didResignMainNotification] {
            center.addObserver(self, selector: #selector(activationChanged), name: name, object: window)
        }
        applyTint()
    }

    @objc private func activationChanged() {
        applyTint()
    }

    /// Settles the material the instant the app comes back.
    ///
    /// Returning from the Dock, from Stage Manager or from another app runs a
    /// layout pass inside AppKit's own animation transaction, and an implicitly
    /// animated frame sweeps the effect across the surface — the sidebar's
    /// flash. `layout()` already disables actions; this puts the frame back
    /// before the first frame is composited rather than waiting for the pass
    /// that transaction schedules.
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

    /// Decoration takes no events. A backing fills its host edge to edge, so
    /// wherever the host has no glyph the deepest view under the pointer is this
    /// one — and a view that draws no background answers
    /// `mouseDownCanMoveWindow` with `true`, which on a window that moves by its
    /// background spends the press dragging the window instead of pressing the
    /// control. Handing the hit test back puts the question to the host.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// And the same answer for the host that does hit-test to here anyway.
    override var mouseDownCanMoveWindow: Bool { false }

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

    /// Re-reads §2a's density. Nothing is rebuilt — the density chooses which
    /// plane `updateLayer` paints behind the glass, and the glass itself is
    /// unchanged — so this is a redraw and not a swap. See `Glass.density`.
    func refreshMaterial() {
        needsDisplay = true
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
            // The header only guarantees placement for `contentView`, and the
            // tint plate has to be in front of the material rather than behind
            // it, so the plate is the content.
            view.contentView = tintPlate
            view.isHidden = wantsFlatPlane
            addSubview(view)
            glass = view
        }
        applyTint()

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
        // the page ⇒ the same plane behind the glass, because there is nothing
        // left for the material to sample.
        //
        // Otherwise frost: the chrome planes carry `Surface.frost` behind their
        // glass at all times, the same grey at half strength. The desktop still
        // refracts through, but through a surface rather than a hole, and it
        // costs no darkening the way a heavier tint did.
        //
        // How much of it, and whether a popover gets one at all, is §2a's
        // setting (`Glass.density`). Read here rather than cached, so the
        // reapply pass is a redraw.
        layer.backgroundColor = if wantsFlatPlane {
            Tokens.Surface.fullScreenChrome.cgColor
        } else if wantsOpaquePlane {
            style.solidFallback.cgColor
        } else {
            style.frost(Glass.density)?.cgColor
        }

        // §2 / §21.2: Increase Contrast ⇒ a visible border on every control.
        // A rimmed plane draws the same hairline unconditionally — it is the
        // edge `ContentCardView` draws where the page meets the sidebar, read
        // the other way round. A plane floating over the page has nothing but
        // its own material to end it, and a material without an edge reads as a
        // smudge. The hairline follows `maskedCorners`.
        let bordered = rimmed || Tokens.A11y.increaseContrast
        layer.borderWidth = bordered ? Tokens.Metric.hairline : 0
        layer.borderColor = bordered ? Tokens.Line.border.cgColor : nil
    }
}
