//
//  BrowserWindowController.swift
//  Luna
//
//  The floating browser window (UI-SPEC §3.6/§4, TODO.md §30.1): no titlebar,
//  no toolbar, rounded at `windowCornerRadius`, detached, with the wallpaper
//  visible around it.
//  It hosts exactly two things — a chrome view (the sidebar or the top bar,
//  built in wave 2) and the content card — and switches between `ChromeState`s.
//
//  Geometry is decided in two pure functions and nowhere else: `ChromeState`'s
//  `cardInsets`/`cardIsInset` for the card, `TrafficLightLayout` for the lights.
//  This controller only applies them, in one transaction (§4.1).
//

import AppKit
import BrowserKit
import WebKit

@MainActor
final class BrowserWindowController: NSWindowController, NSWindowDelegate {

    private let card = ContentCardView()
    /// §8.2a's wash, in the two places the sidebar's own copy cannot reach.
    /// See `SpaceCornerFillView` for why it is a second view.
    private let cornerFill = SpaceCornerFillView()
    private var cornerFillWidth: NSLayoutConstraint?
    private var trafficLights: TrafficLightLayoutManager?
    private(set) var chrome: NSView?

    /// §22.6: this window came forward. The app tracks the front window from
    /// this rather than reading `NSApp.keyWindow`, which is nil whenever a
    /// sheet, a pop-out or the Settings window is up — and every command Luna
    /// has would then be about no window at all.
    var onBecameKey: (() -> Void)?

    /// §22.6: this window has gone.
    ///
    /// A notification and not `windowWillClose(_:)`, which is the same trap
    /// `toggleSidebar(_:)` was: `NSWindowController` implements that delegate
    /// method itself, so a copy declared in an extension never overrides it and
    /// never runs. Measured — a private window closed with its database still
    /// on disk, and nothing said so.
    var onClosed: (() -> Void)? {
        didSet {
            closeWatch = nil
            guard onClosed != nil, let window else { return }
            closeWatch = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.onClosed?() }
            }
        }
    }

    private var closeWatch: (any NSObjectProtocol)? {
        didSet {
            guard let old = oldValue else { return }
            NotificationCenter.default.removeObserver(old)
        }
    }

    // The chrome's switchable constraints: a column on one side in the sidebar
    // layout, a top bar spanning the window in the other.
    private var chromeWidth: NSLayoutConstraint?
    private var chromeHeight: NSLayoutConstraint?
    private var chromeFillsHeight: NSLayoutConstraint?
    /// How far the chrome is pushed off each window edge. The column is pinned
    /// by exactly one of them and the top bar by both: a sidebar stands on the
    /// edge it belongs to, and a hidden one parks a width off it and comes back
    /// for §7.2's peek. The sign follows the edge — leading parks at `-width`,
    /// trailing at `+width`.
    private var chromeLeading: NSLayoutConstraint?
    private var chromeTrailing: NSLayoutConstraint?

    /// §7.2's hover-peek: the strip that notices the pointer and the little
    /// state machine that debounces it.
    private let peekEdge = SidebarPeekEdgeView()
    private let peekMenuBar = SidebarPeekMenuBarWatch()
    private let peek = SidebarPeekController()

    /// §7.2: the chrome plane a peeked sidebar floats on.
    ///
    /// A sibling of the chrome rather than a subview of it, so the host's own
    /// clipping does not sit between the material and what it samples; it
    /// shares the chrome's four edges, so it slides with it for free.
    private let peekBackdrop = Glass.peekPlane()
    /// §3.2c's fallback: the load line, across the window's top edge, for the
    /// chrome states that have no address bar on screen to put it under. See
    /// `ChromeState.loadProgressHost`.
    private let loadLine = LoadProgressLine()
    /// §3.2b's placement, as the one reader resolved it. Told rather than read
    /// (`AppDelegate.applySearchBarPlacement`): the sidebar, the page bar and
    /// this line all have to agree about which address bar is up.
    private var searchBarOnPage = false
    /// The peek strip's two possible homes — it lies along whichever window
    /// edge the hidden sidebar parks behind.
    private var peekEdgeLeading: NSLayoutConstraint?
    private var peekEdgeTrailing: NSLayoutConstraint?
    /// The strip's width, which is narrower in fullscreen — see
    /// `sidebarPeekEdgeFullScreen`.
    private var peekEdgeWidth: NSLayoutConstraint?
    /// The corner fill's, for the same reason.
    private var cornerFillLeading: NSLayoutConstraint?
    private var cornerFillTrailing: NSLayoutConstraint?

    private var stateBeforeFullscreen: ChromeState?
    /// The width to come back to when the sidebar is shown again. Not the
    /// default: a user who dragged the sidebar to 200 pt and hid it expects
    /// 200 pt back.
    private var widthBeforeCollapse: CGFloat?

    private(set) var chromeState: ChromeState = .sidebar(
        width: Tokens.Metric.sidebarWidth.default,
        edge: .leading
    )

    /// Builds the window and its two hosts. It opens empty: the content
    /// card is filled by `setContent` once `BrowserSession` has a selected tab,
    /// because a window that loads a page of its own would be a web view for a
    /// tab nobody chose (§19.4). Wave 2 replaced M0's placeholder web view here.
    /// Spelled out rather than left to `remembersFrame`'s default, and it has
    /// to be: `NSWindowController` declares `init()` itself, and with only a
    /// defaulted parameter below that inherited one wins the call — handing
    /// back a controller with no window at all, silently.
    convenience init() {
        self.init(remembersFrame: true)
    }

    /// - Parameter remembersFrame: whether this window is the one that restores
    ///   and saves the remembered frame. Exactly one is (§22.6): an autosave
    ///   name is per name, not per window, so several windows sharing one open
    ///   on top of each other and the last to close overwrites the rest. The
    ///   others cascade off the front window instead.
    convenience init(remembersFrame: Bool) {
        let window = NSWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: Tokens.Metric.windowDefaultWidth,
                height: Tokens.Metric.windowDefaultHeight
            ),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        Self.makeFloating(window)
        window.center()

        self.init(window: window)

        // Set after `center()` so a remembered frame wins over the default placement.
        if remembersFrame { windowFrameAutosaveName = "LunaBrowserWindow" }
        window.delegate = self
        buildContent(in: window)
        trafficLights = TrafficLightLayoutManager(window: window)
        peek.onChange = { [weak self] peeking in self?.applyPeek(peeking) }
        peek.holdWhilePopoutIsUp(in: window)
        peekEdge.onPointerInside = { [weak self] inside in self?.peek.setPointerInEdge(inside) }
        peekMenuBar.window = window
        peekMenuBar.onPointerInside = { [weak self] inside in self?.peek.setPointerInMenuBar(inside) }
        apply(chromeState, animated: false)
    }

    // MARK: - The window itself

    /// §30.1: the window is a shape we draw, not a system frame. Everything the
    /// standard chrome would paint is turned off so the root view's rounded
    /// glass is the window.
    private static func makeFloating(_ window: NSWindow) {
        window.title = "Luna"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.toolbar = nil
        window.isOpaque = false
        // Not a colour token: this is "draw nothing", so the root view's own
        // corners and the system shadow define the window's shape.
        window.backgroundColor = .clear
        // The shadow is what separates the window from the wallpaper on a light
        // desktop as well as a dark one; with a non-opaque window AppKit shapes
        // it to what we actually draw.
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        // A floor the window server honours as well as one Auto Layout does.
        // The root view's `greaterThanOrEqualTo` constraints bind AppKit's own
        // layout and nothing else: a window resized from outside that pass — a
        // tiling gesture, a drag onto a screen edge — went straight through them
        // and left the chrome squeezed smaller than its contents.
        window.minSize = NSSize(
            width: Tokens.Metric.windowMinWidth,
            height: Tokens.Metric.windowMinHeight
        )
        // Luna has its own tabs; system window tabs would be a second, worse set.
        window.tabbingMode = .disallowed
    }

    private func buildContent(in window: NSWindow) {
        let root = WindowRootView()
        window.contentView = root
        // The window's glass plane. The sidebar is a window of it: the content
        // pane is opaque and flush, so this is what the chrome is made of.
        // Applied before any subview so the glass stays behind them.
        Glass.apply(.sidebar, to: root)
        card.pin(in: root)
        // Below the card, so the only place it can show is the notch the card's
        // rounded leading corners leave. Above it, it would be a tinted stripe
        // down the page's edge.
        cornerFill.translatesAutoresizingMaskIntoConstraints = false
        cornerFill.isHidden = true
        root.addSubview(cornerFill, positioned: .below, relativeTo: card)
        let fillWidth = cornerFill.widthAnchor.constraint(equalToConstant: 0)
        cornerFillWidth = fillWidth
        cornerFillLeading = cornerFill.leadingAnchor.constraint(equalTo: root.leadingAnchor)
        cornerFillTrailing = cornerFill.trailingAnchor.constraint(equalTo: root.trailingAnchor)
        cornerFillLeading?.isActive = true
        NSLayoutConstraint.activate([
            cornerFill.topAnchor.constraint(equalTo: root.topAnchor),
            cornerFill.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            fillWidth
        ])
        peekEdge.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(peekEdge, positioned: .above, relativeTo: card)
        peekBackdrop.translatesAutoresizingMaskIntoConstraints = false
        peekBackdrop.alphaValue = 0
        root.addSubview(peekBackdrop, positioned: .above, relativeTo: peekEdge)
        NSLayoutConstraint.activate([
            // The floor, in the layout system. `makeFloating` sets the window's
            // own `minSize` as well, and both are needed: this one binds every
            // pass AppKit runs, that one binds the resize itself.
            root.widthAnchor.constraint(greaterThanOrEqualToConstant: Tokens.Metric.windowMinWidth),
            root.heightAnchor.constraint(greaterThanOrEqualToConstant: Tokens.Metric.windowMinHeight),

            // It starts below the bar, not at the window's top corner. With the
            // sidebar hidden, §3.2b puts the sidebar toggle on the page at this
            // exact corner, so a full-height strip meant reaching for that
            // button pulled the sidebar out over it; the button moved 280 pt,
            // the pointer followed it off the strip, the peek closed and the
            // button came back — unclickable. Nothing above this line triggers a
            // peek; the whole leading edge below it still does.
            peekEdge.topAnchor.constraint(equalTo: root.topAnchor, constant: Tokens.Metric.pageBar),
            peekEdge.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])
        let width = peekEdge.widthAnchor.constraint(equalToConstant: Tokens.Metric.sidebarPeekEdge)
        width.isActive = true
        peekEdgeWidth = width
        peekEdgeLeading = peekEdge.leadingAnchor.constraint(equalTo: root.leadingAnchor)
        peekEdgeTrailing = peekEdge.trailingAnchor.constraint(equalTo: root.trailingAnchor)
        peekEdgeLeading?.isActive = true

        // Last, so it is above everything — including the chrome, which
        // `setChrome` inserts directly above `peekBackdrop` and therefore below
        // this. §7.2's peek slides a sidebar over the page at this corner, and a
        // progress line the peek covers disappears whenever the pointer brushes
        // the window's edge.
        loadLine.translatesAutoresizingMaskIntoConstraints = false
        loadLine.isHidden = true
        root.addSubview(loadLine, positioned: .above, relativeTo: peekBackdrop)
        NSLayoutConstraint.activate([
            loadLine.topAnchor.constraint(equalTo: root.topAnchor),
            loadLine.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            loadLine.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            loadLine.heightAnchor.constraint(equalToConstant: Tokens.Metric.loadLineHeight)
        ])
    }

    // MARK: - §3.2c's load line

    /// §3.2b's placement, from the one reader that owns it. Which address bar
    /// is on screen decides whether this window's top edge is the one wearing
    /// the load line.
    func setSearchBarOnPage(_ onPage: Bool) {
        guard onPage != searchBarOnPage else { return }
        searchBarOnPage = onPage
        updateLoadLineHost()
    }

    /// The active tab's load, for the fallback line. Fed whether or not this
    /// window is the host: `⌘S` mid-load moves the line from the pill to the
    /// window's edge, and a line that only started counting once it was shown
    /// would come back empty half way through a page.
    func setLoadProgress(_ state: TabState?, for tab: UUID?) {
        guard let state else { return loadLine.clear() }
        loadLine.show(state, for: tab)
    }

    private func updateLoadLineHost() {
        loadLine.isHidden = chromeState.loadProgressHost(searchBarOnPage: searchBarOnPage) != .windowTop
    }

    // MARK: - Hosting

    /// Hosts the sidebar or the top bar. Wave 2 builds their contents; this
    /// controller only decides where the view sits.
    func setChrome(_ view: NSView?) {
        chrome?.removeFromSuperview()
        chrome = view
        chromeWidth = nil
        chromeHeight = nil
        chromeFillsHeight = nil
        chromeLeading = nil
        chromeTrailing = nil
        guard let view, let root = window?.contentView else { return }

        view.translatesAutoresizingMaskIntoConstraints = false
        // Above the card and above the peek strip: §7.2's hover-peek slides the
        // sidebar over the page, and once it has arrived it is the thing the
        // pointer is on.
        root.addSubview(view, positioned: .above, relativeTo: peekBackdrop)
        NSLayoutConstraint.activate([
            peekBackdrop.topAnchor.constraint(equalTo: view.topAnchor),
            peekBackdrop.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            peekBackdrop.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            peekBackdrop.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        chromeWidth = view.widthAnchor.constraint(equalToConstant: Tokens.Metric.sidebarWidth.default)
        chromeHeight = view.heightAnchor.constraint(equalToConstant: Tokens.Metric.topBarHeight)
        chromeFillsHeight = view.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        chromeLeading = view.leadingAnchor.constraint(equalTo: root.leadingAnchor)
        chromeTrailing = view.trailingAnchor.constraint(equalTo: root.trailingAnchor)
        chromeLeading?.isActive = true
        view.topAnchor.constraint(equalTo: root.topAnchor).isActive = true
        applyChromeGeometry(chromeState)
    }

    /// The web content (or anything else) inside the card.
    func setContent(_ view: NSView?) {
        card.setContent(view)
    }

    /// §3.2b's page bar, over the top of the page rather than beside it. Inside
    /// the card and not beside it in the root view, so it travels with the pane
    /// on every layout switch and is clipped to the pane's own corners.
    func setPageOverlay(_ view: NSView?) {
        card.setOverlay(view)
    }

    /// §3.2b: how much of the page the bar covers.
    func setPageBarInset(_ inset: CGFloat, animated: Bool) {
        card.setContentTopInset(inset, animated: animated)
    }

    /// The page's frame inside the window's content view. §9.1's Command Bar
    /// centres on this rather than on the window, so it does not sit half a
    /// sidebar to the left of where the user is looking.
    var contentFrame: NSRect { card.frame }

    // MARK: - Chrome state

    func setChromeState(_ state: ChromeState) {
        apply(state, animated: true)
    }

    /// The launch path: the layout the user chose is applied before there is
    /// anything on screen to animate, and animating it would show the wrong
    /// layout for 0.30 s first.
    func setChromeStateWithoutAnimation(_ state: ChromeState) {
        apply(state, animated: false)
    }

    /// §3.7's live drag. Not animated: the pointer is already the animation,
    /// and a 0.20 s spring on every drag event puts the divider permanently
    /// behind the mouse. Ignored unless the sidebar is showing — a width applied
    /// while collapsed would expand it.
    func setSidebarWidth(_ width: CGFloat) {
        guard case let .sidebar(_, edge) = chromeState else { return }
        apply(.sidebar(width: Settings.sidebarWidth.clamp(width), edge: edge), animated: false)
    }

    /// `⌘S` and §3.1's toggle: the sidebar slides out to zero width and the page
    /// takes the whole window (§4.1's curve, `Motion.sidebarCollapse`).
    ///
    /// Not the layout switch. Which chrome the window wears is a setting
    /// (`Settings.chromeLayout`); this only hides and shows it. In top-bar
    /// layout there is no sidebar to hide and the call is a no-op.
    func setSidebarCollapsed(_ collapsed: Bool) {
        switch (collapsed, chromeState) {
        case let (true, .sidebar(width, edge)):
            widthBeforeCollapse = width
            apply(.sidebarCollapsed(edge: edge), animated: true)
        case let (false, .sidebarCollapsed(edge)):
            apply(.sidebar(width: parkedSidebarWidth, edge: edge), animated: true)
        default:
            break
        }
    }

    var isSidebarCollapsed: Bool { chromeState.isSidebarCollapsed }

    /// The width the hidden sidebar parks at, and comes back at for a peek.
    private var parkedSidebarWidth: CGFloat {
        widthBeforeCollapse ?? Tokens.Metric.sidebarWidth.default
    }
}

// MARK: - §7.2's hover-peek, page fullscreen, and the geometry they share

/// An extension rather than more of the class above, which is at the type body
/// length limit. The split is along the seam the file already had: above is what
/// the window is made of and what it hosts, below is what moves when the chrome
/// changes state.
extension BrowserWindowController {

    // MARK: - §7.2's hover-peek

    /// `ChromeHostView` reports the pointer arriving on and leaving the sidebar
    /// itself; the edge strip reports the other half. Either one keeps the peek
    /// open — see `SidebarPeekController`.
    func setPointerInsideChrome(_ inside: Bool) {
        peek.setPointerInSidebar(inside)
    }

    /// Slides the hidden sidebar over the page, and back off it.
    ///
    /// The page does not move: only the chrome's leading constraint and its
    /// opacity change. The card's insets are the collapsed ones throughout, so
    /// nothing reflows for a glance at the tab list.
    /// The strip is the screen's edge in fullscreen and a band along the
    /// window's edge otherwise, and the menu bar's strip is fullscreen's only.
    /// Asked on entering and leaving fullscreen and on every chrome state.
    func updatePeekEdgeWidth() {
        let isFullScreen = window?.styleMask.contains(.fullScreen) ?? false
        peekEdgeWidth?.constant = isFullScreen ? Tokens.Metric.sidebarPeekEdgeFullScreen : Tokens.Metric.sidebarPeekEdge
        peekMenuBar.isEnabled = isFullScreen && chromeState.isSidebarCollapsed
    }

    private func applyPeek(_ peeking: Bool) {
        guard case let .sidebarCollapsed(edge) = chromeState, let chrome else { return }
        let width = parkedSidebarWidth
        // The lights are hidden while the page has the whole window; a peeked
        // sidebar is a sidebar, and it has a control row with a hole in it if
        // they are not there.
        trafficLights?.isPeeking = peeking
        markChromeForTrafficLights()
        Tokens.Motion.animate(Tokens.Motion.sidebarCollapse) { context in
            context.allowsImplicitAnimation = true
            // The park is a push off the edge the sidebar belongs to, so the
            // sign is the edge's: leading pushes negative, trailing positive.
            let parked = edge == .trailing ? width : -width
            (edge == .trailing ? chromeTrailing : chromeLeading)?.constant = peeking ? 0 : parked
            chrome.alphaValue = peeking ? 1 : 0
            peekBackdrop.alphaValue = peeking ? 1 : 0
            window?.contentView?.layoutSubtreeIfNeeded()
        }
    }

    /// The lights coming and going changes no view's bounds, so nothing else
    /// marks the sidebar's control row dirty — and that row lays its buttons out
    /// against the lights (`SidebarControlRow`).
    ///
    /// Both callers need it. Without the second, `⌘S` twice left the sidebar
    /// toggle sitting under the traffic lights: the hidden sidebar's row had
    /// laid itself out with no lights to clear, and showing the column gave them
    /// back without asking the row to look again.
    private func markChromeForTrafficLights() {
        guard let root = window?.contentView else { return }
        TrafficLightSpace.neighboursNeedLayout(in: root)
    }

    /// Whether `⌘S` has anything to do in the current layout.
    var canCollapseSidebar: Bool {
        switch chromeState {
        case .sidebar, .sidebarCollapsed: true
        case .topBar, .fullscreen: false
        }
    }

    /// Page fullscreen (§3.6): the card grows to fill the window and the chrome
    /// goes with it. Window fullscreen — the green button — is a different thing
    /// and deliberately keeps the chrome; see `windowDidEnterFullScreen`.
    func setPageFullscreen(_ on: Bool) {
        if on { stateBeforeFullscreen = chromeState }
        let restore = stateBeforeFullscreen
            ?? .sidebar(width: Tokens.Metric.sidebarWidth.default, edge: .leading)
        if !on { stateBeforeFullscreen = nil }
        apply(on ? .fullscreen : restore, animated: true)
    }

    private func apply(_ state: ChromeState, animated: Bool) {
        let previous = chromeState
        chromeState = state
        // §3.2c: hiding the sidebar takes the address bar away with it, and the
        // window's top edge takes the load line over.
        updateLoadLineHost()
        // A peek belongs to the collapsed state and to nothing else. Both flags
        // are reset rather than left to the controller's own `onChange`: that
        // callback early-returns once the state has already moved on, and a
        // stale `isPeeking` would leave the traffic lights showing over a
        // full-bleed page the next time the sidebar was hidden.
        trafficLights?.isPeeking = false
        peekBackdrop.alphaValue = 0
        peek.isEnabled = state.isSidebarCollapsed
        peekEdge.isEnabled = state.isSidebarCollapsed
        updatePeekEdgeWidth()
        let insets = state.cardInsets
        let spec = Self.motion(from: previous, to: state)
        // The page is told its final width before the chrome starts moving. See
        // `ContentCardView.beginGeometryTransition`: a web view re-laid out on
        // every frame of a 0.20 s slide is the "resizing is very obvious" this
        // fixes.
        if animated, let root = window?.contentView {
            card.beginGeometryTransition(
                toWidth: root.bounds.width - insets.left - insets.right,
                over: spec.duration
            )
        }
        let body = { [self] in
            applyChromeGeometry(state)
            card.insetEdge = state.cardInsetEdge
            card.setInsets(insets)
            // In the same transaction, never as a second step: a re-anchor one
            // frame later is exactly the visible jump §4.1 warns about.
            trafficLights?.apply(state)
            markChromeForTrafficLights()
            window?.contentView?.layoutSubtreeIfNeeded()
        }
        if animated {
            Tokens.Motion.animate(spec) { context in
                // Without this the constraint constants snap instead of sliding.
                context.allowsImplicitAnimation = true
                body()
            } completion: { [card] in
                MainActor.assumeIsolated { card.endGeometryTransition() }
            }
        } else {
            body()
        }
    }

    /// §8.2a: the Space's colour, for the corner fill as well as for the
    /// sidebar's own wash. The sidebar is where the gradient is known and the
    /// window is where the card's geometry is, so it is handed across rather
    /// than looked up twice.
    func setSpaceGradient(_ gradient: GradientPair) {
        cornerFill.show(gradient)
    }

    /// `.sidebar` is the only state whose card has a rounded leading corner —
    /// `ChromeState.cardIsInset` says so, and this follows it exactly.
    private func showCornerFill(besideColumnOf width: CGFloat, on edge: SidebarEdge) {
        cornerFill.columnWidth = width
        cornerFill.edge = edge
        cornerFillWidth?.constant = width + Tokens.Metric.contentCardRadius
        cornerFillLeading?.isActive = edge == .leading
        cornerFillTrailing?.isActive = edge == .trailing
        cornerFill.isHidden = false
        cornerFill.needsLayout = true
    }

    private func hideCornerFill() {
        cornerFill.isHidden = true
        cornerFillWidth?.constant = 0
    }

    private func applyChromeGeometry(_ state: ChromeState) {
        guard let chrome else { return }
        // Deactivate before activating: the two pairs contradict each other.
        switch state {
        case let .sidebar(width, edge):
            pinColumn(to: edge, width: width, offset: 0)
            chrome.alphaValue = 1
            showCornerFill(besideColumnOf: width, on: edge)
        case .topBar:
            chromeWidth?.isActive = false
            chromeHeight?.isActive = true
            chromeFillsHeight?.isActive = false
            // A bar spans the window, so it is pinned by both edges at once.
            chromeLeading?.constant = 0
            chromeTrailing?.constant = 0
            chromeLeading?.isActive = true
            chromeTrailing?.isActive = true
            chrome.alphaValue = 1
            hideCornerFill()
        case let .sidebarCollapsed(edge):
            // It slides out, it does not shrink. Collapsing the width to zero
            // squeezed the tab list, the pill and the control row through 280 pt
            // of relayout on the way — visible, and pointless. Parking it a
            // width off its own edge keeps it whole and leaves it one constraint
            // away from §7.2's peek.
            let width = parkedSidebarWidth
            pinColumn(to: edge, width: width, offset: edge == .trailing ? width : -width)
            chrome.alphaValue = 0
            hideCornerFill()
        case .fullscreen:
            // Page fullscreen has no peek and nothing to come back to, so the
            // chrome goes to zero width and stays where it is.
            pinColumn(to: chromeState.sidebarEdge ?? .leading, width: 0, offset: 0)
            chrome.alphaValue = 0
            hideCornerFill()
        }
    }

    /// The column half of the geometry: one width, one edge it is pinned to,
    /// and how far off that edge it is pushed.
    ///
    /// Both edge constraints exist for the whole window's life and exactly one
    /// of them is active here — which is the only thing that makes "the other
    /// side" a constraint swap rather than a second layout to keep in step.
    private func pinColumn(to edge: SidebarEdge, width: CGFloat, offset: CGFloat) {
        chromeHeight?.isActive = false
        chromeWidth?.constant = width
        chromeWidth?.isActive = true
        chromeFillsHeight?.isActive = true
        chromeLeading?.isActive = edge == .leading
        chromeTrailing?.isActive = edge == .trailing
        chromeLeading?.constant = offset
        chromeTrailing?.constant = offset
        peekEdgeLeading?.isActive = edge == .leading
        peekEdgeTrailing?.isActive = edge == .trailing
        Glass.setPeekEdge(edge, on: peekBackdrop)
    }

    private static func motion(from old: ChromeState, to new: ChromeState) -> MotionSpec {
        switch (old, new) {
        case (.fullscreen, _), (_, .fullscreen):
            Tokens.Motion.cardFullscreen
        case (.sidebar, .sidebarCollapsed), (.sidebarCollapsed, .sidebar):
            Tokens.Motion.sidebarCollapse
        default:
            Tokens.Motion.layoutSwitch
        }
    }
}
