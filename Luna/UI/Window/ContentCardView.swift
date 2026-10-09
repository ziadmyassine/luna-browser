//
//  ContentCardView.swift
//  Luna
//
//  The web content's host: an opaque pane filling everything the chrome
//  does not (UI-SPEC §3.6, §30.11). The pane owns its own edge
//  constraints — one place computes the insets, and they animate for free.
//
//  No gap, despite §3.6's "inset 8 pt": as `inspiration/main-tab-bar-and-ui.png`
//  does, the page runs flush to the window's edges and against the sidebar or
//  §4's bar, with only the two corners against the chrome rounded, at the
//  window's own radius so they nest. The floating read comes from the sidebar's
//  glass, not from a moat.
//
//  The card is never translucent: a live web page behind glass is unreadable
//  (UI-SPEC §2), so this is the one chrome surface that asks `Glass` for nothing.
//

import AppKit
import BrowserKit
import WebKit

/// The one edge of the page's pane that meets the chrome rather than the
/// window, and so the pair of corners that is rounded.
enum CardEdge: Equatable {
    case leading, trailing, top

    init(_ edge: SidebarEdge) {
        self = edge == .leading ? .leading : .trailing
    }

    /// The pane's two corners along this edge.
    var corners: CACornerMask {
        switch self {
        case .trailing: [.layerMaxXMinYCorner, .layerMaxXMaxYCorner]
        case .top: [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        case .leading: [.layerMinXMinYCorner, .layerMinXMaxYCorner]
        }
    }
}

extension ChromeState {

    /// Which of the pane's edges is not a window edge, and therefore which pair
    /// of corners is rounded: the side the sidebar is on, or the top under §4's
    /// bar. Collapsed or in fullscreen the pane meets the window on every side
    /// and the window's own mask is the only corner there is.
    var cardInsetEdge: CardEdge? {
        switch self {
        case let .sidebar(_, edge): CardEdge(edge)
        case .topBar: .top
        case .sidebarCollapsed, .fullscreen: nil
        }
    }

    var cardIsInset: Bool { cardInsetEdge != nil }

    /// The card's inset from the window's content view, per layout.
    ///
    /// Pure, and unit-tested alongside the traffic lights: this and
    /// `TrafficLightLayout` are the only two places window geometry is decided.
    var cardInsets: NSEdgeInsets {
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
            return NSEdgeInsets(top: TopBarMetrics.barHeight, left: 0, bottom: 0, right: 0)
        case .fullscreen:
            return NSEdgeInsets()
        }
    }
}

/// Opaque rounded host for the web content.
@MainActor
final class ContentCardView: NSView {

    /// The pane's non-window edge — the one it shares with the sidebar or the
    /// top bar — whose two corners are rounded. Nil everywhere the pane meets
    /// the window on all four sides.
    var insetEdge: CardEdge? = .leading {
        didSet {
            guard insetEdge != oldValue else { return }
            updateCornerRadius()
        }
    }

    var isInset: Bool { insetEdge != nil }

    /// The edge the agent panel stands against (`AgentPanelHost`), whose
    /// corners are rounded too: there the pane meets the window's glass.
    var agentEdge: CardEdge? {
        didSet {
            guard agentEdge != oldValue else { return }
            updateCornerRadius()
        }
    }

    /// Told when a view comes into the card or leaves it. A docked Web
    /// Inspector is one, and the card goes clear under it, so the agent
    /// panel's light reaching under the card would show (`AgentPanelHost`).
    var onSubviewsChange: (() -> Void)?

    /// Files and web links dropped on the page bar, or on a card with no page
    /// (`WindowDrop`). A web view registers for drops itself, so over the page
    /// it is the one asked.
    var onDropPages: (([URL]) -> Void)? {
        didSet { onDropPages == nil ? unregisterDraggedTypes() : registerForDraggedTypes(WindowDrop.types) }
    }

    /// A file or link is over the card, at this point in the window, or has
    /// left it (nil) — for §6.6's mark of where it will open.
    var onDropHover: ((NSPoint?) -> Void)?

    /// top, leading, bottom, trailing — in that order, always.
    private var edges: [NSLayoutConstraint] = []
    private var content: NSView?
    /// §3.2b's page bar, floating over the page at the pane's top edge — the
    /// one thing that is allowed inside the card and is not the web content.
    private var overlay: NSView?
    /// Luna Control's layer (`ControlSurfaceView`): over the page, under the
    /// page bar, whichever tab is showing.
    private var agentLayer: ControlSurfaceView?
    private var insetsBeforeFullscreen: NSEdgeInsets?
    private var insetEdgeBeforeFullscreen: CardEdge? = .leading
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
    /// The content's four resting edges, handed to WebKit while its inspector
    /// is docked in the card (`followFrames`).
    private var contentEdges: [NSLayoutConstraint] = []
    private var contentFollowsFrames = false
    /// WebKit's docked inspector, told how much of it §3.2b's bar covers.
    private weak var dockedInspector: WKWebView? { didSet { needsDisplay = true } }
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
        // The corner is the window's, which the Appearance setting changes.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(settingsDidChange),
            name: Settings.didChange,
            object: nil
        )
    }

    @objc private func settingsDidChange() {
        updateCornerRadius()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its views in code")
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        WindowDrop.hover(sender, report: onDropHover)
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        WindowDrop.hover(sender, report: onDropHover)
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        onDropHover?(nil)
    }

    override func draggingEnded(_ sender: any NSDraggingInfo) {
        onDropHover?(nil)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        WindowDrop.perform(sender, open: onDropPages)
    }

    // MARK: - Content

    func setContent(_ view: NSView?) {
        guard view !== content else { return }
        // Only if it is still here. A page another window has since taken
        // (§6.6's tear-off) is that window's now, and removing it would take
        // it off the card it moved to.
        if content?.superview === self { content?.removeFromSuperview() }
        content = view
        guard let view else { return }
        view.translatesAutoresizingMaskIntoConstraints = false
        // Under the overlay, whichever arrived first: the page bar floats over
        // the page, and a web view added afterwards would otherwise cover it.
        if let below = agentLayer ?? overlay {
            addSubview(view, positioned: .below, relativeTo: below)
        } else {
            addSubview(view)
        }
        // Four edges at rest; one edge and a width only while a chrome
        // transition is running (`beginGeometryTransition`).
        //
        // The width must not be the resting state. A constant carries no
        // relationship, so it would be re-derived from `bounds` every layout
        // pass, and a constraint constant written from inside `layout()` is not
        // reliably picked up — the pass that reads it has already run. A window
        // resized in one jump left the page at the old width with the pane's
        // own grey showing beside it.
        let leading = view.leadingAnchor.constraint(equalTo: leadingAnchor)
        contentLeading = leading
        let width = view.widthAnchor.constraint(equalToConstant: bounds.width)
        width.isActive = false
        contentWidth = width
        let top = view.topAnchor.constraint(equalTo: topAnchor)
        contentTop = top
        contentFollowsFrames = false
        contentEdges = [
            top,
            view.trailingAnchor.constraint(equalTo: trailingAnchor),
            view.bottomAnchor.constraint(equalTo: bottomAnchor),
            leading
        ]
        NSLayoutConstraint.activate(contentEdges)
        // A tab arriving under a bar that is already there.
        applyTopInset()
    }

    /// §3.2b's bar.
    ///
    /// Pinned to all four edges, not to the bar's own strip: hit testing stops
    /// at a superview's bounds, so anything the bar draws below its band would
    /// be visible and unclickable. What keeps the page's clicks is
    /// `PageChromeBar.hitTest`.
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

    /// §3.2b's bar is drawn over the page and read before it.
    override func accessibilityChildren() -> [Any]? {
        let children = super.accessibilityChildren()
        guard let children, let overlay else { return children }
        return AccessibilityOrder.led(children, by: [overlay])
    }

    /// Luna Control's layer, over the four edges like the bar, and under it.
    func setAgentLayer(_ view: ControlSurfaceView) {
        agentLayer = view
        view.translatesAutoresizingMaskIntoConstraints = false
        if let overlay {
            addSubview(view, positioned: .below, relativeTo: overlay)
        } else {
            addSubview(view)
        }
        view.topInset = pageBarInset
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
    /// without moving the web view. Animating the web view's top edge with the
    /// bar resized it a frame at a time: the page redrew behind the edge and
    /// visibly bobbed, and on the way open the pane's grey showed between the
    /// bar and a page that had not caught up.
    ///
    /// A new inset still moves the content by the difference, so the page is
    /// scrolled by the same amount in the same turn and stays where it is on
    /// screen. Not at the top of a document when the bar opens: there the bar
    /// pushing the page down is the page making room, which is what it is.
    func setContentTopInset(_ inset: CGFloat, animated: Bool) {
        guard inset != pageBarInset else { return }
        let change = inset - pageBarInset
        pageBarInset = inset
        agentLayer?.topInset = inset
        applyTopInset(holdingPage: animated ? change : 0)
        coverInspector()
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
    /// re-flows once instead of once a frame. Hiding the sidebar changes the
    /// page's width by 280 pt; told each frame's width, a page counting its own
    /// `resize` events re-flowed 13 times hiding and 10 showing, and the slide
    /// stuttered while the web process kept up.
    ///
    /// The page is held at the wider of the two widths, anchored to the edge
    /// that does not move, and the card's other edge does all the moving.
    /// Hiding, that is the final width: the page re-flows once, up front.
    /// Showing, it is the width the page already has, and
    /// `endGeometryTransition` narrows it once everything is still.
    ///
    /// - Parameters:
    ///   - duration: how long the caller's animation runs. A watchdog hands the
    ///     width back after it, so a dropped completion handler cannot strand
    ///     the page at a width the pane has since grown past.
    ///   - edge: the edge that stays put — the trailing one while the sidebar
    ///     comes and goes, the leading one for the agent panel. Held by the
    ///     edge that moves, the page slid sideways with it and jumped back at
    ///     the end.
    func beginGeometryTransition(toWidth width: CGFloat, over duration: TimeInterval, holding edge: CardEdge = .trailing) {
        guard !contentFollowsFrames else { return }
        let trailing = contentEdges.first { $0.firstAttribute == .trailing }
        // Deactivate before activating: the two contradict each other, and an
        // over-constrained instant is a console full of broken-constraint logs.
        (edge == .leading ? trailing : contentLeading)?.isActive = false
        contentWidth?.constant = max(width, bounds.width, 0)
        contentWidth?.isActive = true
        (edge == .leading ? contentLeading : trailing)?.isActive = true
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
        guard !contentFollowsFrames, contentWidth?.isActive == true else { return }
        Tokens.Motion.immediately {
            contentWidth?.isActive = false
            NSLayoutConstraint.activate(contentEdges)
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
        let targetEdge: CardEdge? = on ? nil : insetEdgeBeforeFullscreen
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
        // One pair of corners, on the side the chrome is. The other edges
        // are the window's, and the window's own mask already rounds them —
        // rounding them here as well would round the pane inside a corner that
        // is already round and show glass through the crescent between the two.
        let edges = [insetEdge, agentEdge].compactMap { $0 }
        layer?.maskedCorners = edges.isEmpty ? CardEdge.leading.corners
            : edges.map(\.corners).reduce([]) { $0.union($1) }
        layer?.cornerRadius = edges.isEmpty ? 0 : WindowCorner.radius
        // The edge is drawn by `updateLayer` and turns off with the corners.
        needsDisplay = true
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        guard let layer else { return }
        // Clear while an inspector is docked: it is restyled to be the chrome
        // carried on into the card (`InspectorStyle`), so the window's glass
        // has to be what is behind it. The page paints its own background.
        layer.backgroundColor = dockedInspector == nil ? Tokens.Surface.base.cgColor : NSColor.clear.cgColor
        // The glass edge (§3.6). The pane is opaque, so the chrome's
        // material stops dead at its leading edge and the two planes meet with
        // nothing between them. `Line.border` is that edge — the same hairline
        // every other glass surface in the app carries, drawn on the side where
        // the page meets the chrome. It follows `maskedCorners`, so it runs
        // round the rounded edge and nowhere else.
        let edged = isInset || agentEdge != nil
        layer.borderWidth = edged ? Tokens.Metric.hairline : 0
        layer.borderColor = edged ? Tokens.Line.border.cgColor : nil
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    /// The page is not a window drag handle. Without this, dragging any
    /// non-interactive part of a web page would move the window.
    override var mouseDownCanMoveWindow: Bool { false }
}

// MARK: - A docked Web Inspector

extension ContentCardView {

    /// WebKit docks its inspector by adding a view beside the page and setting
    /// both frames itself. The page's constraints put it back over the
    /// inspector on the next pass (measured: a 1000 × 700 page on top of a
    /// 1000 × 500 inspector), so while one is docked the page is sized by frame.
    /// Watching the card rather than the commands also catches Inspect Element
    /// and the inspector's own close button.
    override func didAddSubview(_ subview: NSView) {
        super.didAddSubview(subview)
        onSubviewsChange?()
        guard Self.isDockedInspector(subview) else { return }
        followFrames(true)
        dockedInspector = subview as? WKWebView
        if let inspector = dockedInspector { WebInspector.restyle(inspector, css: InspectorStyle.css) }
        subview.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(inspectorMoved), name: NSView.frameDidChangeNotification, object: subview
        )
        // WebKit zeroes the inspector's insets after adding it, so the
        // cover goes on again once it has finished.
        coverInspector()
        DispatchQueue.main.async { [weak self] in self?.coverInspector() }
    }

    override func willRemoveSubview(_ subview: NSView) {
        super.willRemoveSubview(subview)
        onSubviewsChange?()
        guard Self.isDockedInspector(subview) else { return }
        followFrames(false)
        NotificationCenter.default.removeObserver(self, name: NSView.frameDidChangeNotification, object: subview)
        dockedInspector = nil
    }

    /// Where a docked Web Inspector stands, in the card's coordinates.
    var dockedInspectorFrame: NSRect? {
        subviews.first(where: Self.isDockedInspector)?.frame
    }

    @objc private func inspectorMoved() { coverInspector() }

    /// Docked beside the page, the inspector runs the card's full height and
    /// its toolbar sat under §3.2b's bar, so it is told what the bar covers the
    /// way the page is. Docked below the page it reaches nowhere near the bar
    /// and is told nothing. Recomputed on every move: WebKit re-adds the view
    /// when it changes side, and zeroes the insets whenever it sets the frame.
    private func coverInspector() {
        guard let inspector = dockedInspector else { return }
        let top = isFlipped ? inspector.frame.minY : bounds.height - inspector.frame.maxY
        let covered = max(0, pageBarInset - top)
        guard inspector.obscuredContentInsets.top != covered else { return }
        var insets = inspector.obscuredContentInsets
        insets.top = covered
        inspector.obscuredContentInsets = insets
    }

    private static func isDockedInspector(_ view: NSView) -> Bool {
        view is WKWebView && view.className.contains("Inspector")
    }

    fileprivate func followFrames(_ on: Bool) {
        guard let content, on != contentFollowsFrames else { return }
        contentFollowsFrames = on
        if on {
            endGeometryTransition()
            NSLayoutConstraint.deactivate(contentEdges + [contentWidth].compactMap { $0 })
            content.translatesAutoresizingMaskIntoConstraints = true
            content.autoresizingMask = [.width, .height]
        } else {
            content.translatesAutoresizingMaskIntoConstraints = false
            // A card being torn down lets go of the page before the inspector,
            // and edges to a view no longer in it raise. Inside, not directly
            // in: WebKit may hold the page in a view of its own while docked.
            guard content.isDescendant(of: self) else { return }
            NSLayoutConstraint.activate(contentEdges)
            needsLayout = true
        }
    }
}
