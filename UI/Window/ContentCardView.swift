//
//  ContentCardView.swift
//  Luna
//
//  The web content's host: an opaque pane filling everything the chrome
//  does not (UI-SPEC §3.6, TODO.md §30.11). The pane owns its own edge
//  constraints — one place computes the insets, and they animate for free.
//
//  There is no gap any more. §3.6's "inset 8 pt from the sidebar and from the
//  window's top, right and bottom edges" is not what
//  `inspiration/main-tab-bar-and-ui.png` does: the page runs flush to all three
//  window edges and against the sidebar, with only its two leading corners
//  rounded, at the window's own radius so they nest rather than leaving a
//  crescent of glass inside each one. The floating read comes from the
//  sidebar's glass, not from a moat.
//
//  The card is never translucent. A live web page behind glass is unreadable
//  (UI-SPEC §2), which is why this is the one chrome surface that does not ask
//  `Glass` for anything.
//

import AppKit
import WebKit

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
    /// The content's top edge: the pane's own for a web view, which runs
    /// under §3.2b's bar, and below the bar for anything else — see
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
        // The width is the interesting half (`beginGeometryTransition`) but
        // must not be the resting state. A constant carries no relationship, so
        // keeping it meant re-deriving it from `bounds` every layout pass, and
        // a constraint constant written from inside `layout()` is not reliably
        // picked up — the pass that reads it has already run. A window resized
        // in one jump left the page at the old width with the pane's own grey
        // showing beside it. Auto Layout keeps the resting case right free.
        let leading = view.leadingAnchor.constraint(equalTo: leadingAnchor)
        contentLeading = leading
        let width = view.widthAnchor.constraint(equalToConstant: bounds.width)
        width.isActive = false
        contentWidth = width
        let top = view.topAnchor.constraint(equalTo: topAnchor)
        contentTop = top
        NSLayoutConstraint.activate([
            top,
            view.trailingAnchor.constraint(equalTo: trailingAnchor),
            view.bottomAnchor.constraint(equalTo: bottomAnchor),
            leading
        ])
        // A tab arriving under a bar that is already there.
        applyTopInset()
    }

    /// §3.2b's bar.
    ///
    /// Pinned to all four edges, not to a 52 pt strip. The bar draws in the
    /// strip and hit-tests only its own band, so a smaller frame would have been
    /// the honest size — until the address pill grew a suggestion list hanging
    /// below it. Hit testing stops at a superview's bounds, so a list drawn
    /// outside a 52 pt host would be visible and unclickable. What keeps the
    /// page's clicks is `PageChromeBar.hitTest`.
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

    /// How much of the page §3.2b's bar covers.
    ///
    /// The page runs under the bar, and WebKit is told how much of it the bar
    /// covers (`obscuredContentInsets`), which shrinks the page's viewport
    /// without moving the web view. The web view used to move: its top edge
    /// was a constraint animated with the bar, so it was resized a frame at a
    /// time, the page redrew behind the edge and visibly bobbed, and on the
    /// way open the pane's grey showed between the bar and a page that had not
    /// caught up.
    ///
    /// A new inset still moves the content by the difference, so the page is
    /// scrolled by the same amount in the same turn and stays where it is on
    /// screen. Not at the top of a document when the bar opens: there the bar
    /// pushing the page down is the page making room, which is what it is.
    func setContentTopInset(_ inset: CGFloat, animated: Bool) {
        guard inset != pageBarInset else { return }
        let change = inset - pageBarInset
        pageBarInset = inset
        applyTopInset(holdingPage: animated ? change : 0)
    }

    /// The inset, on whatever the pane is holding. A view that is not a web
    /// view — a plain one in the tests — cannot be told what is covered, so it
    /// starts below the bar instead.
    private func applyTopInset(holdingPage change: CGFloat = 0) {
        guard let content else { return }
        guard let web = content as? WKWebView else {
            contentTop?.constant = pageBarInset
            return Tokens.Motion.immediately { layoutSubtreeIfNeeded() }
        }
        contentTop?.constant = 0
        var insets = web.obscuredContentInsets
        insets.top = pageBarInset
        web.obscuredContentInsets = insets
        guard change != 0 else { return }
        web.evaluateJavaScript(Self.holdingScript(change), in: nil, in: .defaultClient, completionHandler: nil)
    }

    /// Scrolls the page by `change`, which cancels the move the new inset
    /// makes. `instant`, or a site with `scroll-behavior: smooth` would glide
    /// back into place after the jump this exists to prevent.
    static func holdingScript(_ change: CGFloat) -> String {
        let slack = Tokens.Metric.pageBarScrollSlack
        return """
        (() => {
            const change = \(Double(change));
            if (change > 0 && window.scrollY <= \(Double(slack))) return;
            window.scrollBy({ top: change, behavior: "instant" });
        })()
        """
    }

    // MARK: - Layout transitions

    /// Holds the page at one width for the length of a chrome transition, so it
    /// re-flows once instead of once a frame.
    ///
    /// Hiding the sidebar is the most expensive thing the chrome does: the page
    /// changes width by 280 pt, and a web view told its new width twelve times
    /// over 0.20 s re-flows twelve times. Measured with a page counting its own
    /// `resize` events: 13 hiding, 10 showing. What the user sees is a column of
    /// text jumping several times on the way and the slide stuttering while the
    /// web process keeps up.
    ///
    /// So the page is held at the wider of the two widths for the whole slide
    /// and the card's edge does all the moving. Hiding, that is the final width
    /// — the page re-flows once, up front, and the card opens to reveal what was
    /// clipped. Showing, it is the width the page already has — nothing re-flows
    /// while anything is moving, the card's edge closes over the page, and
    /// `endGeometryTransition` narrows it once everything is still.
    ///
    /// Either way the page is anchored to the trailing edge, which does not
    /// move, so its size is constant for the length of the animation and the
    /// web process is not asked for anything.
    ///
    /// - Parameter duration: how long the caller's animation runs. A watchdog
    ///   hands the width back after it, so a dropped completion handler cannot
    ///   strand the page at a width the pane has since grown past.
    func beginGeometryTransition(toWidth width: CGFloat, over duration: TimeInterval) {
        // Deactivate before activating: the two contradict each other, and an
        // over-constrained instant is a console full of broken-constraint logs.
        contentLeading?.isActive = false
        contentWidth?.constant = max(width, bounds.width, 0)
        contentWidth?.isActive = true
        // Here, and not with the caller's animation: a constraint activated and
        // left for the transaction that follows is laid out inside it, which
        // animates the page's width and is the per-frame re-flow this exists to
        // prevent. The one re-flow has to happen with the animations off.
        Tokens.Motion.immediately { layoutSubtreeIfNeeded() }
        transitionWatchdog?.cancel()
        transitionWatchdog = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration + Tokens.Motion.hoverPeekDelay))
            guard !Task.isCancelled else { return }
            self?.endGeometryTransition()
        }
    }

    /// Hands the width back to Auto Layout.
    ///
    /// This is where a shown sidebar's page re-flows — see
    /// `beginGeometryTransition`. Unanimated on purpose: the transition is over,
    /// and the last thing a settled layout should do is animate.
    func endGeometryTransition() {
        transitionWatchdog?.cancel()
        transitionWatchdog = nil
        guard contentLeading?.isActive == false else { return }
        Tokens.Motion.immediately {
            contentWidth?.isActive = false
            contentLeading?.isActive = true
            layoutSubtreeIfNeeded()
        }
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
