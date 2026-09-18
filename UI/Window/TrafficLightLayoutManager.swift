//
//  TrafficLightLayoutManager.swift
//  Luna
//
//  THE single owner of the traffic lights' frames (TODO.md §7.7, UI-SPEC §3.1).
//  Nothing else in the app may touch a standard window button's frame. Manual
//  repositioning spread across view controllers is the #1 visual bug source in
//  Arc-style browsers; the geometry therefore lives in a pure function that is
//  unit-tested for every `ChromeState` (see `Tests/Window/`).
//
//  Measured on macOS 26 with a running probe, not assumed:
//    · the buttons live in `NSTitlebarView`, 32 pt tall, unflipped;
//    · they are 14 × 14 at x = 9 / 32 / 55 (23 pt apart), y = 9;
//    · **AppKit resets those frames on every window resize** — which is exactly
//      the bug. Re-application is not optional, so this class owns it.
//    · neither `NSTitlebarView` nor `NSTitlebarContainerView` clips, but hit
//      testing still stops at the container's bounds, so a button hung below the
//      titlebar would draw and not click. `TrafficLightLayout` clamps instead.
//

import AppKit

/// Which window edge §3's sidebar stands on.
///
/// **The traffic lights do not move with it.** macOS puts them at the window's
/// top-left and there is no API that does otherwise, so a right-hand sidebar
/// leaves them floating over the page's top-left corner — which is what every
/// browser that offers this does, and the honest alternative to pretending the
/// choice is symmetric.
enum SidebarEdge: String, Sendable, Equatable, CaseIterable {
    case leading
    case trailing
}

/// Which chrome the window is showing. Drives both traffic-light placement and
/// the content card's geometry (UI-SPEC §3, §4).
enum ChromeState: Sendable, Equatable {
    case sidebar(width: CGFloat, edge: SidebarEdge)
    case sidebarCollapsed(edge: SidebarEdge)
    case topBar
    case fullscreen

    /// The side the sidebar is on, in the two states that have one.
    ///
    /// The collapsed state carries it as well: a hidden sidebar parks off the
    /// edge it belongs to and §7.2's peek slides back in from that same edge,
    /// so "which side" outlives "is it showing".
    var sidebarEdge: SidebarEdge? {
        switch self {
        case let .sidebar(_, edge), let .sidebarCollapsed(edge): edge
        case .topBar, .fullscreen: nil
        }
    }

    var isSidebarCollapsed: Bool {
        if case .sidebarCollapsed = self { true } else { false }
    }
}

/// What AppKit tells us about the buttons — measured at runtime, never assumed.
struct TrafficLightMetrics: Sendable, Equatable {
    /// Button origins as AppKit lays them out, in titlebar coordinates.
    var natural: [CGPoint]
    var buttonHeight: CGFloat
    var titlebarHeight: CGFloat
}

/// Pure geometry: no window, no AppKit state, no side effects — so the placement
/// for every state can be asserted in a test instead of eyeballed in a running
/// app (§7.7). This is the point of the type.
enum TrafficLightLayout {

    /// Where the standard window buttons belong, in their superview's
    /// (`NSTitlebarView`, bottom-left origin) coordinates.
    ///
    /// The lights sit at the same place in every chrome layout by design: the
    /// sidebar's control row and the top bar both start at the window's
    /// top-left, so switching layout or collapsing the sidebar must not move
    /// them. A test pins that down.
    ///
    /// **`inset` is one number for both axes.** It used to be a leading inset
    /// plus a vertical centring in the control row, which put the lights 8 pt
    /// from the window's leading edge and 18 pt from its top — unequal padding
    /// into a corner, and the first thing the eye catches. The reference insets
    /// them equally; so does this.
    ///
    /// - Returns: `nil` when the system owns the frames (fullscreen), meaning
    ///   "do not touch".
    static func origins(
        for state: ChromeState,
        system: TrafficLightMetrics,
        inset: CGFloat
    ) -> [CGPoint]? {
        if case .fullscreen = state { return nil }
        guard let first = system.natural.first else { return nil }

        // A button hung below the titlebar still draws but stops hit-testing,
        // so the vertical inset is clamped into it. At the measured macOS 26
        // sizes (32 pt titlebar, 14 pt buttons) 18 pt fits exactly.
        let floor = max(system.titlebarHeight - system.buttonHeight, 0)
        let fromTop = min(max(inset, 0), floor)
        let originY = system.titlebarHeight - fromTop - system.buttonHeight

        // Keep AppKit's own spacing: translate the natural row, never rebuild it.
        return system.natural.map { CGPoint(x: inset + ($0.x - first.x), y: originY) }
    }
}

/// Applies `TrafficLightLayout` to a real window, and re-applies it every time
/// AppKit undoes the work (resize, fullscreen, any titlebar mutation).
@MainActor
final class TrafficLightLayoutManager {

    private static let buttonTypes: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]

    private weak var window: NSWindow?
    private var state: ChromeState = .sidebarCollapsed(edge: .leading)
    private let natural: [CGPoint]

    /// §7.2: the sidebar is peeking over a hidden-sidebar window, so the lights
    /// belong back on screen for as long as it is there.
    var isPeeking = false {
        didSet {
            guard isPeeking != oldValue else { return }
            layoutButtons()
        }
    }

    /// **Hidden while the page has the whole window.**
    ///
    /// `⌘S` means "give the page the window", and three lights floating over
    /// the top-left corner of a web page is the one piece of chrome that did
    /// not go away — sitting on the site's own navigation more often than not.
    /// They come back the moment there is a sidebar to put them in, which
    /// includes a peek.
    private var hidesButtons: Bool {
        state.isSidebarCollapsed && !isPeeking
    }

    init(window: NSWindow) {
        self.window = window
        // Captured before anything moves them: these are AppKit's own origins
        // and only the deltas between them are used, so they never go stale.
        natural = Self.buttons(of: window).map(\.frame.origin)
        observe(window)
    }

    /// Single entry point. Call it inside the same animation transaction as the
    /// layout change it belongs to — a second step is a visible jump (§4.1).
    func apply(_ state: ChromeState) {
        self.state = state
        layoutButtons()
    }

    // MARK: - Re-application

    private func observe(_ window: NSWindow) {
        let center = NotificationCenter.default
        // Target/action observers are zeroing-weak since 10.11, so there is
        // nothing to unregister and no `deinit` to reason about.
        for name: Notification.Name in [
            NSWindow.didResizeNotification,
            NSWindow.didEnterFullScreenNotification,
            NSWindow.didExitFullScreenNotification
        ] {
            center.addObserver(self, selector: #selector(systemDidRelayout), name: name, object: window)
        }
        // Catches the rest: anything that re-lays the titlebar resets the frames.
        if let titlebar = Self.buttons(of: window).first?.superview {
            titlebar.postsFrameChangedNotifications = true
            center.addObserver(
                self,
                selector: #selector(systemDidRelayout),
                name: NSView.frameDidChangeNotification,
                object: titlebar
            )
        }
    }

    /// Posted synchronously on the main thread by AppKit (`queue:` is deliberately
    /// not used: an enqueued re-apply lands a frame late and reads as a jump).
    @objc private func systemDidRelayout(_ notification: Notification) {
        layoutButtons()
    }

    private func layoutButtons() {
        guard let window, !window.styleMask.contains(.fullScreen) else { return }
        let buttons = Self.buttons(of: window)
        guard let first = buttons.first, let titlebar = first.superview else { return }

        // Before the placement, and unconditionally: a hidden button still has
        // a frame, and AppKit resets `isHidden` on some titlebar rebuilds the
        // same way it resets the origins.
        let hidden = hidesButtons
        for button in buttons where button.isHidden != hidden { button.isHidden = hidden }

        let system = TrafficLightMetrics(
            natural: natural,
            buttonHeight: first.frame.height,
            titlebarHeight: titlebar.bounds.height
        )
        guard let origins = TrafficLightLayout.origins(
            for: state,
            system: system,
            inset: Tokens.Metric.trafficLightInset
        ), origins.count == buttons.count else { return }

        // Set directly, not through `animator()`: the placement is identical in
        // every managed state, so there is nothing to interpolate, and this runs
        // inside the caller's transaction anyway.
        for (button, origin) in zip(buttons, origins) where button.frame.origin != origin {
            button.setFrameOrigin(origin)
        }
    }

    private static func buttons(of window: NSWindow) -> [NSButton] {
        buttonTypes.compactMap { window.standardWindowButton($0) }
    }
}
