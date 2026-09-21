//
//  ContentCardView.swift
//  Luna
//
//  The web content's host: an opaque pane filling everything the chrome
//  does not (UI-SPEC §3.6, TODO.md §30.11). The pane owns its own edge
//  constraints — one place computes the insets, and they animate for free.
//
//  There is no gap any more. §3.6's "inset 8 pt from the sidebar and from
//  the window's top, right and bottom edges" is not what
//  `inspiration/main-tab-bar-and-ui.png` does: the page runs flush to all
//  three window edges and flush against the sidebar, and only its two
//  leading corners are rounded — at the window's own radius, so they nest
//  with the window's corners instead of leaving a crescent of glass inside
//  each one. The floating read comes from the sidebar's glass, not from a moat.
//
//  The card is never translucent. A live web page behind glass is unreadable
//  (UI-SPEC §2), which is why this is the one chrome surface that does not ask
//  `Glass` for anything.
//

import AppKit

extension ChromeState {

    /// Which of the pane's vertical edges is not a window edge, and
    /// therefore which pair of corners is rounded. Only the sidebar layout has
    /// such an edge, and which one it is depends on the side the sidebar is on:
    /// under the top bar, collapsed, or in fullscreen the pane meets the window
    /// on every side and the window's own mask is the only corner there is.
    var cardInsetEdge: SidebarEdge? {
        switch self {
        case let .sidebar(_, edge): edge
        case .sidebarCollapsed, .topBar, .fullscreen: nil
        }
    }

    var cardIsInset: Bool { cardInsetEdge != nil }

    /// The card's inset from the window's content view, per layout.
    ///
    /// Pure, and unit-tested alongside the traffic lights: this and
    /// `TrafficLightLayout` are the only two places window geometry is decided.
    var cardInsets: NSEdgeInsets {
        let row = Tokens.Metric.topBarHeight
        switch self {
        case let .sidebar(width, edge):
            // Flush to the window's top and bottom and to the edge the sidebar
            // is not on; the sidebar is the only thing that insets it.
            return switch edge {
            case .leading: NSEdgeInsets(top: 0, left: width, bottom: 0, right: 0)
            case .trailing: NSEdgeInsets(top: 0, left: 0, bottom: 0, right: width)
            }
        case .sidebarCollapsed:
            // Flush, lights and all. Hiding the sidebar means the page
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

    /// The pane's non-window edge — the one it shares with the sidebar — whose
    /// two corners are rounded. Nil everywhere the pane meets the window on all
    /// four sides.
    var insetEdge: SidebarEdge? = .leading {
        didSet {
            guard insetEdge != oldValue else { return }
            updateCornerRadius()
        }
    }

    var isInset: Bool { insetEdge != nil }

    /// top, leading, bottom, trailing — in that order, always.
    private var edges: [NSLayoutConstraint] = []
    private var content: NSView?
    /// §3.2b's page bar, floating over the page at the pane's top edge — the
    /// one thing that is allowed inside the card and is not the web content.
    private var overlay: NSView?
    private var insetsBeforeFullscreen: NSEdgeInsets?
    private var insetEdgeBeforeFullscreen: SidebarEdge? = .leading
    /// The content's leading edge, pinned to the card's. Active at rest, so
    /// the page is exactly as wide as the pane with no bookkeeping at all.
    private var contentLeading: NSLayoutConstraint?
    /// The content's width, held at the final value for the length of a
    /// layout transition and inactive the rest of the time — see
    /// `beginGeometryTransition(toWidth:)`.
    private var contentWidth: NSLayoutConstraint?
    /// The content's top edge. §3.2b's bar stands above the page rather
    /// than over it, so the page starts under the bar's band — see
    /// `setContentTopInset`.
    private var contentTop: NSLayoutConstraint?
    private var pageBarInset: CGFloat = 0
    /// Cancels the watchdog when a transition ends the ordinary way.
    private var transitionWatchdog: Task<Void, Never>?

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
        // Under the overlay, whichever arrived first: the page bar floats over
        // the page, and a web view added afterwards would otherwise cover it.
        if let overlay {
            addSubview(view, positioned: .below, relativeTo: overlay)
        } else {
            addSubview(view)
        }
        // Four edges at rest; trailing-pinned and width-driven only while a
        // chrome transition is running.
        //
        // The width is the interesting half — see `beginGeometryTransition` —
        // but it must not be the resting state. A constant carries no
        // relationship, so keeping it meant re-deriving it from `bounds` on
        // every layout pass, and writing a constraint constant from inside
        // `layout()` is not reliably picked up: the pass that reads it has
        // already run. A window resized in one jump — the zoom button, a
        // hidden sidebar — left the page at the old width with the pane's own
        // grey showing beside it, which is exactly the band in Martin's
        // captures. Auto Layout keeps the resting case right for free.
        let leading = view.leadingAnchor.constraint(equalTo: leadingAnchor)
        contentLeading = leading
        let width = view.widthAnchor.constraint(equalToConstant: bounds.width)
        width.isActive = false
        contentWidth = width
        let top = view.topAnchor.constraint(equalTo: topAnchor, constant: pageBarInset)
        contentTop = top
        NSLayoutConstraint.activate([
            top,
            view.trailingAnchor.constraint(equalTo: trailingAnchor),
            view.bottomAnchor.constraint(equalTo: bottomAnchor),
            leading
        ])
    }

    /// §3.2b's bar.
    ///
    /// Pinned to all four edges, not to a 52 pt strip. The bar draws in the
    /// strip and hit-tests only its own band, so a smaller frame would have
    /// been the honest size — until the address pill grew a suggestion list
    /// that hangs below it. Hit testing stops at a superview's bounds, so a
    /// list drawn outside a 52 pt host would have been visible and unclickable.
    /// What keeps the page's clicks is `PageChromeBar.hitTest`, which is where
    /// that decision belongs anyway.
    ///
    /// The card clips it, so it takes the pane's rounded leading corners free.
    func setOverlay(_ view: NSView?) {
        overlay?.removeFromSuperview()
        overlay = view
        guard let view else { return }
        view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(view, positioned: .above, relativeTo: nil)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: topAnchor),
            view.leadingAnchor.constraint(equalTo: leadingAnchor),
            view.trailingAnchor.constraint(equalTo: trailingAnchor),
            view.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    /// How far §3.2b's bar pushes the page down.
    ///
    /// Above the page, not over it. The bar takes the site's own colour, so
    /// laid over the page it merged with the top of the document — and hid
    /// whatever the document had put there. The page starts below it instead,
    /// in both of the bar's states, which means the 22 pt between them is a
    /// real change of height and the page reflows for it.
    ///
    /// That reflow is affordable because it is rare: the bar changes state at
    /// most once per reversal of scroll direction (`PageBarScroll` holds it
    /// through `pageBarScrollSlack` of travel), not once per frame. Zero when
    /// the bar is not on screen, which is every layout but §3.2b's.
    func setContentTopInset(_ inset: CGFloat, animated: Bool) {
        guard inset != pageBarInset else { return }
        pageBarInset = inset
        guard let contentTop else { return }
        let assign: () -> Void = {
            contentTop.constant = inset
            self.layoutSubtreeIfNeeded()
        }
        guard animated else { return Tokens.Motion.immediately(assign) }
        // The same spec the bar collapses on, so the page and the bar arrive
        // together rather than one chasing the other.
        Tokens.Motion.animate(Tokens.Motion.sidebarCollapse) { context in
            context.allowsImplicitAnimation = true
            assign()
        }
    }

    // MARK: - Layout transitions

    /// Tells the page how wide it is about to be, before the card starts
    /// moving, and holds it there until `endGeometryTransition`.
    ///
    /// Hiding the sidebar used to be the most obviously expensive thing in the
    /// app: the page re-flowed 280 pt wider over 0.20 s, one relayout per
    /// frame, and on a heavy site that is a visible stutter and a column of
    /// text that jumps four times on the way. Now it re-flows once, to its
    /// final width, and the card slides its own edge across to reveal it. The
    /// page is anchored to the trailing edge, which does not move, so nothing
    /// under the pointer shifts either.
    ///
    /// - Parameter duration: how long the caller's animation runs. A watchdog
    ///   hands the width back after it, so a dropped completion handler cannot
    ///   strand the page at a width the pane has since grown past — the failure
    ///   this used to have, and the one that is invisible until it isn't.
    func beginGeometryTransition(toWidth width: CGFloat, over duration: TimeInterval) {
        // Deactivate before activating: the two contradict each other, and an
        // over-constrained instant is a console full of broken-constraint logs.
        contentLeading?.isActive = false
        contentWidth?.constant = max(width, 0)
        contentWidth?.isActive = true
        transitionWatchdog?.cancel()
        transitionWatchdog = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration + Tokens.Motion.hoverPeekDelay))
            guard !Task.isCancelled else { return }
            self?.endGeometryTransition()
        }
    }

    /// Hands the width back to Auto Layout.
    func endGeometryTransition() {
        transitionWatchdog?.cancel()
        transitionWatchdog = nil
        guard contentLeading?.isActive == false else { return }
        contentWidth?.isActive = false
        contentLeading?.isActive = true
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
            insetEdgeBeforeFullscreen = insetEdge
        }
        let target = on ? NSEdgeInsets() : (insetsBeforeFullscreen ?? insets)
        let targetEdge: SidebarEdge? = on ? nil : insetEdgeBeforeFullscreen
        if !on { insetsBeforeFullscreen = nil }

        // `Tokens.Motion.animate` owns the Reduce Motion check (§21.2);
        // `allowsImplicitAnimation` is what makes constraint constants and the
        // corner radius animate rather than snap.
        Tokens.Motion.animate(Tokens.Motion.cardFullscreen) { context in
            context.allowsImplicitAnimation = true
            self.insetEdge = targetEdge
            self.setInsets(target)
            self.superview?.layoutSubtreeIfNeeded()
        }
    }

    // MARK: - Appearance

    private func updateCornerRadius() {
        // One pair of corners, on the side the sidebar is. The other edge
        // is the window's, and the window's own mask already rounds it —
        // rounding it here as well would round the pane inside a corner that is
        // already round and show glass through the crescent between the two.
        layer?.maskedCorners = switch insetEdge {
        case .trailing: [.layerMaxXMinYCorner, .layerMaxXMaxYCorner]
        case .leading, nil: [.layerMinXMinYCorner, .layerMinXMaxYCorner]
        }
        layer?.cornerRadius = isInset ? Tokens.Metric.contentCardRadius : 0
        // The edge is drawn by `updateLayer` and turns off with the corners.
        needsDisplay = true
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        guard let layer else { return }
        layer.backgroundColor = Tokens.Surface.base.cgColor
        // The glass edge (§3.6). The pane is opaque, so the chrome's
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
