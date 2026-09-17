//
//  ContentCardView.swift
//  Luna
//
//  The web content's host: an **opaque** pane filling everything the chrome
//  does not (UI-SPEC §3.6, TODO.md §30.11). The pane owns its own edge
//  constraints — one place computes the insets, and they animate for free.
//
//  **There is no gap any more.** §3.6's "inset 8 pt from the sidebar and from
//  the window's top, right and bottom edges" is not what
//  `inspiration/main-tab-bar-and-ui.png` does: the page runs flush to all
//  three window edges and flush against the sidebar, and only its two
//  **leading** corners are rounded — at the window's own radius, so they nest
//  with the window's corners instead of leaving a crescent of glass inside
//  each one. The floating read comes from the sidebar's glass, not from a moat.
//
//  The card is never translucent. A live web page behind glass is unreadable
//  (UI-SPEC §2), which is why this is the one chrome surface that does not ask
//  `Glass` for anything.
//

import AppKit

extension ChromeState {

    /// Whether the pane's **leading** corners are rounded. Only the sidebar
    /// layout has an edge that is not a window edge, so only it does: under the
    /// top bar, collapsed, or in fullscreen the pane meets the window on every
    /// side and the window's own mask is the only corner there is.
    var cardIsInset: Bool {
        switch self {
        case .sidebar: true
        case .sidebarCollapsed, .topBar, .fullscreen: false
        }
    }

    /// The card's inset from the window's content view, per layout.
    ///
    /// Pure, and unit-tested alongside the traffic lights: this and
    /// `TrafficLightLayout` are the only two places window geometry is decided.
    var cardInsets: NSEdgeInsets {
        let row = Tokens.Metric.topBarHeight
        switch self {
        case let .sidebar(width):
            // Flush to the window's top, bottom and trailing edges; the sidebar
            // is the only thing that insets it.
            return NSEdgeInsets(top: 0, left: width, bottom: 0, right: 0)
        case .sidebarCollapsed:
            // **Flush, lights and all.** Hiding the sidebar means the page
            // fills the window; reserving a 52 pt strip for the traffic lights
            // would leave a band of empty glass across the top, which is not
            // "hidden". The lights keep their own place in the titlebar and
            // float over the page, which is what every browser that has this
            // mode does.
            return NSEdgeInsets()
        case .topBar:
            // §4: flush full-bleed below the bar.
            return NSEdgeInsets(top: row, left: 0, bottom: 0, right: 0)
        case .fullscreen:
            return NSEdgeInsets()
        }
    }
}

/// Opaque rounded host for the web content.
@MainActor
final class ContentCardView: NSView {

    /// `true` = sidebar layout, where the pane's leading edge is not a window
    /// edge and its two leading corners are rounded. `false` everywhere else.
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
    /// The content's own width. Normally the card's, but held at the *final*
    /// width for the length of a layout transition — see
    /// `beginGeometryTransition(toWidth:)`.
    private var contentWidth: NSLayoutConstraint?
    private var isTransitioning = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        // Clips the page to the pane's corners.
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
        // **Trailing-pinned and width-driven, not four edges.** Pinning the
        // leading edge as well would make the page's width a function of the
        // card's frame on every single frame of the sidebar animation, which is
        // a full WebKit relayout per frame at 120 Hz. With the width as its own
        // constraint, a transition can hand the page its destination size once
        // and let the card's mask do the rest.
        let width = view.widthAnchor.constraint(equalToConstant: bounds.width)
        contentWidth = width
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: topAnchor),
            view.trailingAnchor.constraint(equalTo: trailingAnchor),
            view.bottomAnchor.constraint(equalTo: bottomAnchor),
            width
        ])
    }

    // MARK: - Layout transitions

    /// Tells the page how wide it is **about to** be, before the card starts
    /// moving, and holds it there until `endGeometryTransition`.
    ///
    /// Hiding the sidebar used to be the most obviously expensive thing in the
    /// app: the page re-flowed 280 pt wider over 0.20 s, one relayout per
    /// frame, and on a heavy site that is a visible stutter and a column of
    /// text that jumps four times on the way. Now it re-flows **once**, to its
    /// final width, and the card slides its own edge across to reveal it. The
    /// page is anchored to the trailing edge, which does not move, so nothing
    /// under the pointer shifts either.
    func beginGeometryTransition(toWidth width: CGFloat) {
        isTransitioning = true
        contentWidth?.constant = max(width, 0)
    }

    /// Hands the width back to the card's own bounds.
    func endGeometryTransition() {
        isTransitioning = false
        syncContentWidth()
    }

    private func syncContentWidth() {
        guard !isTransitioning, let contentWidth, contentWidth.constant != bounds.width else { return }
        contentWidth.constant = bounds.width
    }

    /// A live window resize is the pointer's own animation and wants the page
    /// to track it; only a scripted transition holds the width still.
    override func layout() {
        super.layout()
        syncContentWidth()
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
        // **Leading corners only.** The trailing edge is the window's, and the
        // window's own mask already rounds it — rounding it here as well would
        // round the pane inside a corner that is already round and show glass
        // through the crescent between the two.
        layer?.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner]
        layer?.cornerRadius = isInset ? Tokens.Metric.contentCardRadius : 0
        // The edge is drawn by `updateLayer` and turns off with the corners.
        needsDisplay = true
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        guard let layer else { return }
        layer.backgroundColor = Tokens.Surface.base.cgColor
        // **The glass edge** (§3.6). The pane is opaque, so the chrome's
        // material stops dead at its leading edge and the two planes met with
        // nothing between them. `Line.border` is that edge — the same hairline
        // every other glass surface in the app carries, drawn on the side where
        // the page meets the sidebar. It follows `maskedCorners`, so it runs
        // down the rounded leading edge and nowhere else.
        layer.borderWidth = isInset ? Tokens.Metric.hairline : 0
        layer.borderColor = isInset ? Tokens.Line.border.cgColor : nil
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    /// The page is not a window drag handle. Without this, dragging any
    /// non-interactive part of a web page would move the window.
    override var mouseDownCanMoveWindow: Bool { false }
}
