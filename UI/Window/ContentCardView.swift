//
//  ContentCardView.swift
//  Luna
//
//  The web content's host: an **opaque** rounded card floating inside the
//  window's glass (UI-SPEC §3.6, TODO.md §30.11). The 8 pt gap around it is
//  what makes the whole window read as floating, so the card owns its own edge
//  constraints — one place computes the gap, and it animates for free.
//
//  The card is never translucent. A live web page behind glass is unreadable
//  (UI-SPEC §2), which is why this is the one chrome surface that does not ask
//  `Glass` for anything.
//

import AppKit

extension ChromeState {

    /// Whether the content card is the inset floating card (§3.6) or flush
    /// full-bleed under the top bar (§4). Not a style choice: §4 says the
    /// top-bar layout has no gap and no card corners at all.
    var cardIsInset: Bool {
        switch self {
        case .sidebar, .sidebarCollapsed: true
        case .topBar, .fullscreen: false
        }
    }

    /// The card's inset from the window's content view, per layout.
    ///
    /// Pure, and unit-tested alongside the traffic lights: this and
    /// `TrafficLightLayout` are the only two places window geometry is decided.
    var cardInsets: NSEdgeInsets {
        let gap = Tokens.Metric.contentCardGap
        let row = Tokens.Metric.topBarHeight
        switch self {
        case let .sidebar(width):
            // §3.6: 8 pt from the sidebar and from the window's other edges.
            return NSEdgeInsets(top: gap, left: width + gap, bottom: gap, right: gap)
        case .sidebarCollapsed:
            // No sidebar to inset from, but the traffic lights still need their
            // row — without it they would sit on top of the page.
            return NSEdgeInsets(top: row, left: gap, bottom: gap, right: gap)
        case .topBar:
            // §4: flush full-bleed below the bar. No gap, on purpose.
            return NSEdgeInsets(top: row, left: 0, bottom: 0, right: 0)
        case .fullscreen:
            return NSEdgeInsets()
        }
    }
}

/// Opaque rounded host for the web content.
@MainActor
final class ContentCardView: NSView {

    /// `true` = sidebar layout (rounded, floating). `false` = top-bar layout
    /// (square, flush). Drives the corner radius; the gap itself is `insets`.
    var isInset: Bool = true {
        didSet {
            guard isInset != oldValue else { return }
            updateCornerRadius()
        }
    }

    /// top, leading, bottom, trailing — in that order, always.
    private var edges: [NSLayoutConstraint] = []
    private var content: NSView?
    private var insetsBeforeFullscreen: NSEdgeInsets?
    private var isInsetBeforeFullscreen = true

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        // Clips the page to the card's corners; also why the page can never
        // paint into the 8 pt gap.
        layer?.masksToBounds = true
        updateCornerRadius()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its views in code")
    }

    // MARK: - Content

    func setContent(_ view: NSView?) {
        guard view !== content else { return }
        content?.removeFromSuperview()
        content = view
        guard let view else { return }
        view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: topAnchor),
            view.leadingAnchor.constraint(equalTo: leadingAnchor),
            view.bottomAnchor.constraint(equalTo: bottomAnchor),
            view.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
    }

    // MARK: - Geometry

    /// Adds the card to `container` and takes ownership of its four edges.
    func pin(in container: NSView) {
        translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(self)
        edges = [
            topAnchor.constraint(equalTo: container.topAnchor),
            leadingAnchor.constraint(equalTo: container.leadingAnchor),
            container.bottomAnchor.constraint(equalTo: bottomAnchor),
            container.trailingAnchor.constraint(equalTo: trailingAnchor)
        ]
        NSLayoutConstraint.activate(edges)
    }

    /// The window controller's path: called inside the layout-switch
    /// transaction so the gap animates with everything else.
    func setInsets(_ insets: NSEdgeInsets) {
        guard edges.count == 4 else { return }
        edges[0].constant = insets.top
        edges[1].constant = insets.left
        edges[2].constant = insets.bottom
        edges[3].constant = insets.right
    }

    var insets: NSEdgeInsets {
        guard edges.count == 4 else { return NSEdgeInsets() }
        return NSEdgeInsets(
            top: edges[0].constant,
            left: edges[1].constant,
            bottom: edges[2].constant,
            right: edges[3].constant
        )
    }

    /// Page fullscreen (§3.6): the card grows to fill the window over 0.30 s and
    /// comes back to exactly the gap it left. The chrome-driven path is
    /// `setInsets` from `BrowserWindowController` — same two properties, one
    /// writer at a time.
    func animateToFullscreen(_ on: Bool) {
        // The stash is the state: set means "filling the window". Without this
        // guard, an exit that never entered would round a flush card.
        guard on == (insetsBeforeFullscreen == nil) else { return }
        if on {
            insetsBeforeFullscreen = insets
            isInsetBeforeFullscreen = isInset
        }
        let target = on ? NSEdgeInsets() : (insetsBeforeFullscreen ?? insets)
        let targetIsInset = on ? false : isInsetBeforeFullscreen
        if !on { insetsBeforeFullscreen = nil }

        // `Tokens.Motion.animate` owns the Reduce Motion check (§21.2);
        // `allowsImplicitAnimation` is what makes constraint constants and the
        // corner radius animate rather than snap.
        Tokens.Motion.animate(Tokens.Motion.cardFullscreen) { context in
            context.allowsImplicitAnimation = true
            self.isInset = targetIsInset
            self.setInsets(target)
            self.superview?.layoutSubtreeIfNeeded()
        }
    }

    // MARK: - Appearance

    private func updateCornerRadius() {
        // Square when flush: a full-bleed card has no corners to round, and the
        // window's own 18 pt mask already rounds it at the window edges.
        layer?.cornerRadius = isInset ? Tokens.Metric.contentCardRadius : 0
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = Tokens.Surface.base.cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    /// The page is not a window drag handle. Without this, dragging any
    /// non-interactive part of a web page would move the window.
    override var mouseDownCanMoveWindow: Bool { false }
}
