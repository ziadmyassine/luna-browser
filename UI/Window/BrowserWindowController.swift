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
    private var trafficLights: TrafficLightLayoutManager?
    private var chrome: NSView?

    // The chrome's four switchable constraints: a left column in the sidebar
    // layout, a top bar in the other. Two are active at a time.
    private var chromeWidth: NSLayoutConstraint?
    private var chromeHeight: NSLayoutConstraint?
    private var chromeFillsHeight: NSLayoutConstraint?
    private var chromeFillsWidth: NSLayoutConstraint?
    /// How far the chrome is pushed off the window's leading edge. Zero in
    /// every layout except a hidden sidebar, which parks at `-width` and comes
    /// back to zero for §7.2's peek.
    private var chromeLeading: NSLayoutConstraint?

    /// §7.2's hover-peek: the strip that notices the pointer and the little
    /// state machine that debounces it.
    private let peekEdge = SidebarPeekEdgeView()
    private let peek = SidebarPeekController()

    /// §7.2: the chrome plane a peeked sidebar floats on.
    ///
    /// A sibling of the chrome rather than a subview of it, so the host's own
    /// clipping does not sit between the material and what it samples; it
    /// shares the chrome's four edges, so it slides with it for free.
    private let peekBackdrop = Glass.peekPlane()

    private var stateBeforeFullscreen: ChromeState?
    /// The width to come back to when the sidebar is shown again. Not the
    /// default: a user who dragged the sidebar to 200 pt and hid it expects
    /// 200 pt back.
    private var widthBeforeCollapse: CGFloat?

    private(set) var chromeState: ChromeState = .sidebar(width: Tokens.Metric.sidebarWidth.default)

    /// Builds the window and its two hosts. It opens **empty**: the content
    /// card is filled by `setContent` once `BrowserSession` has a selected tab,
    /// because a window that loads a page of its own would be a web view for a
    /// tab nobody chose (§19.4). Wave 2 replaced M0's placeholder web view here.
    convenience init() {
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
        windowFrameAutosaveName = "LunaBrowserWindow"
        window.delegate = self
        buildContent(in: window)
        trafficLights = TrafficLightLayoutManager(window: window)
        peek.onChange = { [weak self] peeking in self?.applyPeek(peeking) }
        peekEdge.onPointerInside = { [weak self] inside in self?.peek.setPointerInEdge(inside) }
        apply(chromeState, animated: false)
    }

    // MARK: - The window itself

    /// §30.1: the window is a shape we draw, not a system frame. Everything the
    /// standard chrome would paint is turned off so the root view's rounded
    /// glass *is* the window.
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
        peekEdge.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(peekEdge, positioned: .above, relativeTo: card)
        peekBackdrop.translatesAutoresizingMaskIntoConstraints = false
        peekBackdrop.alphaValue = 0
        root.addSubview(peekBackdrop, positioned: .above, relativeTo: peekEdge)
        NSLayoutConstraint.activate([
            // `NSWindow.minSize` is documented as ignored once the content view
            // uses Auto Layout (verified verbatim in NSWindow.h, M0), so the
            // size floor lives in the constraint system instead.
            root.widthAnchor.constraint(greaterThanOrEqualToConstant: Tokens.Metric.windowMinWidth),
            root.heightAnchor.constraint(greaterThanOrEqualToConstant: Tokens.Metric.windowMinHeight),

            peekEdge.topAnchor.constraint(equalTo: root.topAnchor),
            peekEdge.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            peekEdge.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            peekEdge.widthAnchor.constraint(equalToConstant: Tokens.Metric.sidebarPeekEdge)
        ])
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
        chromeFillsWidth = nil
        chromeLeading = nil
        guard let view, let root = window?.contentView else { return }

        view.translatesAutoresizingMaskIntoConstraints = false
        // Above the card **and above the peek strip**: §7.2's hover-peek slides
        // the sidebar *over* the page, and once it has arrived it is the thing
        // the pointer is on.
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
        chromeFillsWidth = view.trailingAnchor.constraint(equalTo: root.trailingAnchor)
        let leading = view.leadingAnchor.constraint(equalTo: root.leadingAnchor)
        chromeLeading = leading
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: root.topAnchor),
            leading
        ])
        applyChromeGeometry(chromeState)
    }

    /// The web content (or anything else) inside the card.
    func setContent(_ view: NSView?) {
        card.setContent(view)
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

    /// §3.7's live drag. **Not animated**: the pointer is already the
    /// animation, and a 0.20 s spring on every drag event puts the divider
    /// permanently behind the mouse. Ignored unless the sidebar is showing —
    /// a width applied while collapsed would expand it.
    func setSidebarWidth(_ width: CGFloat) {
        guard case .sidebar = chromeState else { return }
        apply(.sidebar(width: Tokens.Metric.sidebarWidth.clamp(width)), animated: false)
    }

    /// `⌘S` and §3.1's toggle: the sidebar slides out to zero width and the page
    /// takes the whole window (§4.1's curve, `Motion.sidebarCollapse`).
    ///
    /// **This is not the layout switch.** Which chrome the window wears is a
    /// setting (`Settings.chromeLayout`); this only hides and shows it. In
    /// top-bar layout there is no sidebar to hide and the call is a no-op.
    func setSidebarCollapsed(_ collapsed: Bool) {
        switch (collapsed, chromeState) {
        case let (true, .sidebar(width)):
            widthBeforeCollapse = width
            apply(.sidebarCollapsed, animated: true)
        case (false, .sidebarCollapsed):
            apply(.sidebar(width: parkedSidebarWidth), animated: true)
        default:
            break
        }
    }

    var isSidebarCollapsed: Bool { chromeState == .sidebarCollapsed }

    /// The width the hidden sidebar parks at, and comes back at for a peek.
    private var parkedSidebarWidth: CGFloat {
        widthBeforeCollapse ?? Tokens.Metric.sidebarWidth.default
    }

    // MARK: - §7.2's hover-peek

    /// `ChromeHostView` reports the pointer arriving on and leaving the sidebar
    /// itself; the edge strip reports the other half. Either one keeps the peek
    /// open — see `SidebarPeekController`.
    func setPointerInsideChrome(_ inside: Bool) {
        peek.setPointerInSidebar(inside)
    }

    /// Slides the hidden sidebar over the page, and back off it.
    ///
    /// **The page does not move.** Only the chrome's leading constraint and its
    /// opacity change; the card's insets are the collapsed ones throughout, so
    /// nothing reflows for a glance at the tab list.
    private func applyPeek(_ peeking: Bool) {
        guard chromeState == .sidebarCollapsed, let chrome else { return }
        let width = parkedSidebarWidth
        // The lights are hidden while the page has the whole window; a peeked
        // sidebar is a sidebar, and it has a control row with a hole in it if
        // they are not there.
        trafficLights?.isPeeking = peeking
        // The lights coming and going does not change any view's bounds, so
        // nothing else would mark the control row dirty — and it lays its
        // buttons out *against* the lights. See `SidebarControlRow`.
        for layout in chrome.subviews { layout.needsLayout = true }
        Tokens.Motion.animate(Tokens.Motion.sidebarCollapse) { context in
            context.allowsImplicitAnimation = true
            chromeLeading?.constant = peeking ? 0 : -width
            chrome.alphaValue = peeking ? 1 : 0
            peekBackdrop.alphaValue = peeking ? 1 : 0
            window?.contentView?.layoutSubtreeIfNeeded()
        }
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
        let restore = stateBeforeFullscreen ?? .sidebar(width: Tokens.Metric.sidebarWidth.default)
        if !on { stateBeforeFullscreen = nil }
        apply(on ? .fullscreen : restore, animated: true)
    }

    private func apply(_ state: ChromeState, animated: Bool) {
        let previous = chromeState
        chromeState = state
        // A peek belongs to the collapsed state and to nothing else. Both flags
        // are reset rather than left to the controller's own `onChange`: that
        // callback early-returns once the state has already moved on, and a
        // stale `isPeeking` would leave the traffic lights showing over a
        // full-bleed page the next time the sidebar was hidden.
        trafficLights?.isPeeking = false
        peekBackdrop.alphaValue = 0
        peek.isEnabled = state == .sidebarCollapsed
        peekEdge.isEnabled = state == .sidebarCollapsed
        let insets = state.cardInsets
        let spec = Self.motion(from: previous, to: state)
        // **The page is told its final width before the chrome starts moving.**
        // See `ContentCardView.beginGeometryTransition` — a web view that is
        // re-laid out on every frame of a 0.20 s slide is the "resizing is very
        // obvious" this fixes.
        if animated, let root = window?.contentView {
            card.beginGeometryTransition(
                toWidth: root.bounds.width - insets.left - insets.right,
                over: spec.duration
            )
        }
        let body = { [self] in
            applyChromeGeometry(state)
            card.isInset = state.cardIsInset
            card.setInsets(insets)
            // In the same transaction, never as a second step: a re-anchor one
            // frame later is exactly the visible jump §4.1 warns about.
            trafficLights?.apply(state)
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

    private func applyChromeGeometry(_ state: ChromeState) {
        guard let chrome else { return }
        // Deactivate before activating: the two pairs contradict each other.
        switch state {
        case let .sidebar(width):
            chromeHeight?.isActive = false
            chromeFillsWidth?.isActive = false
            chromeWidth?.constant = width
            chromeWidth?.isActive = true
            chromeFillsHeight?.isActive = true
            chromeLeading?.constant = 0
            chrome.alphaValue = 1
        case .topBar:
            chromeWidth?.isActive = false
            chromeFillsHeight?.isActive = false
            chromeHeight?.isActive = true
            chromeFillsWidth?.isActive = true
            chromeLeading?.constant = 0
            chrome.alphaValue = 1
        case .sidebarCollapsed:
            // **It slides out, it does not shrink.** Collapsing the width to
            // zero squeezed the tab list, the pill and the control row through
            // 280 pt of relayout on the way out — visible, and pointless work.
            // Parking it at `-width` keeps it whole, and leaves it exactly one
            // constraint away from §7.2's peek.
            chromeHeight?.isActive = false
            chromeFillsWidth?.isActive = false
            chromeWidth?.constant = parkedSidebarWidth
            chromeWidth?.isActive = true
            chromeFillsHeight?.isActive = true
            chromeLeading?.constant = -parkedSidebarWidth
            chrome.alphaValue = 0
        case .fullscreen:
            // Page fullscreen has no peek and nothing to come back to, so the
            // chrome goes to zero width and stays where it is.
            chromeHeight?.isActive = false
            chromeFillsWidth?.isActive = false
            chromeWidth?.constant = 0
            chromeWidth?.isActive = true
            chromeFillsHeight?.isActive = true
            chromeLeading?.constant = 0
            chrome.alphaValue = 0
        }
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

    // MARK: - NSWindowDelegate

    /// macOS fullscreen keeps the chrome — a browser without its tab list in
    /// fullscreen is unusable. Only the window's own corners change: the system
    /// frame is square there, and a rounded mask would show as black notches.
    func windowDidEnterFullScreen(_ notification: Notification) {
        (window?.contentView as? WindowRootView)?.isWindowFullScreen = true
        relayoutChrome()
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        (window?.contentView as? WindowRootView)?.isWindowFullScreen = false
        relayoutChrome()
    }

    /// **The traffic lights change size without changing anyone's bounds.**
    ///
    /// §3.1's control row lays its three circles out *against* the lights —
    /// measured, because `TrafficLightLayoutManager` owns their frames — and
    /// macOS takes the lights away in fullscreen and puts them back on the way
    /// out. Neither edge resizes the row, so nothing marks it dirty, and the
    /// row kept whichever placement it happened to have when it last laid out:
    /// the toggle sitting on top of the green light after a return to windowed.
    /// The same call fixes the peek, for the same reason.
    private func relayoutChrome() {
        guard let chrome else { return }
        for layout in chrome.subviews { layout.needsLayout = true }
        // AppKit restores the buttons *after* posting the notification on the
        // way out of fullscreen, so the pass that matters is the next one.
        DispatchQueue.main.async { [weak chrome] in
            guard let chrome else { return }
            for layout in chrome.subviews { layout.needsLayout = true }
        }
    }
}
