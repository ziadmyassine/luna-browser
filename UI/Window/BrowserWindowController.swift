//
//  BrowserWindowController.swift
//  Luna
//
//  The floating browser window (UI-SPEC §3.6/§4, TODO.md §30.1): no titlebar,
//  no toolbar, rounded at 18 pt, detached, with the wallpaper visible around it.
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

    private var stateBeforeFullscreen: ChromeState?

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
        // The window's glass plane. This is what shows through the §3.6 gap and
        // the only reason the card reads as floating. Applied before any subview
        // so the glass stays behind them.
        Glass.apply(.sidebar, to: root)
        card.pin(in: root)
        NSLayoutConstraint.activate([
            // `NSWindow.minSize` is documented as ignored once the content view
            // uses Auto Layout (verified verbatim in NSWindow.h, M0), so the
            // size floor lives in the constraint system instead.
            root.widthAnchor.constraint(greaterThanOrEqualToConstant: Tokens.Metric.windowMinWidth),
            root.heightAnchor.constraint(greaterThanOrEqualToConstant: Tokens.Metric.windowMinHeight)
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
        guard let view, let root = window?.contentView else { return }

        view.translatesAutoresizingMaskIntoConstraints = false
        // Above the card: §7.2's hover-peek slides the sidebar *over* the page.
        root.addSubview(view, positioned: .above, relativeTo: card)
        chromeWidth = view.widthAnchor.constraint(equalToConstant: Tokens.Metric.sidebarWidth.default)
        chromeHeight = view.heightAnchor.constraint(equalToConstant: Tokens.Metric.topBarHeight)
        chromeFillsHeight = view.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        chromeFillsWidth = view.trailingAnchor.constraint(equalTo: root.trailingAnchor)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: root.topAnchor),
            view.leadingAnchor.constraint(equalTo: root.leadingAnchor)
        ])
        applyChromeGeometry(chromeState)
    }

    /// The web content (or anything else) inside the card.
    func setContent(_ view: NSView?) {
        card.setContent(view)
    }

    // MARK: - Chrome state

    func setChromeState(_ state: ChromeState) {
        apply(state, animated: true)
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
        let body = { [self] in
            applyChromeGeometry(state)
            card.isInset = state.cardIsInset
            card.setInsets(state.cardInsets)
            // In the same transaction, never as a second step: a re-anchor one
            // frame later is exactly the visible jump §4.1 warns about.
            trafficLights?.apply(state)
            window?.contentView?.layoutSubtreeIfNeeded()
        }
        if animated {
            Tokens.Motion.animate(Self.motion(from: previous, to: state)) { context in
                // Without this the constraint constants snap instead of sliding.
                context.allowsImplicitAnimation = true
                body()
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
            chrome.alphaValue = 1
        case .topBar:
            chromeWidth?.isActive = false
            chromeFillsHeight?.isActive = false
            chromeHeight?.isActive = true
            chromeFillsWidth?.isActive = true
            chrome.alphaValue = 1
        case .sidebarCollapsed, .fullscreen:
            // §4.1: the sidebar collapses to zero width rather than vanishing,
            // so the card slides across instead of jumping.
            chromeHeight?.isActive = false
            chromeFillsWidth?.isActive = false
            chromeWidth?.constant = 0
            chromeWidth?.isActive = true
            chromeFillsHeight?.isActive = true
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
    /// frame is square there, and an 18 pt mask would show as black notches.
    func windowDidEnterFullScreen(_ notification: Notification) {
        (window?.contentView as? WindowRootView)?.isWindowFullScreen = true
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        (window?.contentView as? WindowRootView)?.isWindowFullScreen = false
    }
}

/// The window's shape: an 18 pt rounded, clipping plane that everything else
/// lives inside (§1 `windowCornerRadius`, §30.1).
private final class WindowRootView: NSView {

    var isWindowFullScreen = false {
        didSet {
            guard isWindowFullScreen != oldValue else { return }
            updateCornerRadius()
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        updateCornerRadius()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its views in code")
    }

    private func updateCornerRadius() {
        layer?.cornerRadius = isWindowFullScreen ? 0 : Tokens.Metric.windowCornerRadius
    }
}
