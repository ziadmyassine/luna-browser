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
    @MainActor
    static func apply(_ style: Style, to view: NSView, cornerRadius: CGFloat = 0) {
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
        glass?.frame = bounds
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
            view.tintColor = style.tint
            // The header only guarantees placement for `contentView`, so give
            // it an empty one rather than relying on a bare glass view.
            view.contentView = NSView(frame: bounds)
            addSubview(view)
            glass = view
        }

        needsDisplay = true
    }

    /// Called with this view's effective appearance already current, so the
    /// dynamic tokens below resolve for the right theme and contrast setting.
    override func updateLayer() {
        guard let layer else { return }
        layer.cornerRadius = radius

        // §2 / §21.2: Reduce Transparency ⇒ solid.
        layer.backgroundColor = Tokens.A11y.reduceTransparency ? style.solidFallback.cgColor : nil

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
