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
//    · AppKit resets those frames on every window resize — which is exactly
//      the bug. Re-application is not optional, so this class owns it.
//    · neither `NSTitlebarView` nor `NSTitlebarContainerView` clips, but hit
//      testing still stops at the container's bounds, so a button hung below the
//      titlebar would draw and not click. `TrafficLightLayout` clamps instead.
//    · fullscreen takes the titlebar out of the window entirely and hangs it
//      off the top of the screen, to slide down on a hover. The lights go with
//      it, and §3.1's sidebar is left with a hole where they were. So this class
//      owns where they live as well as where they sit: see `TrafficLightStrip`.
//    · that slide lays the three out again on the way past. Measured on the
//      reveal and again on the hide: all three back at AppKit's own origins,
//      still inside the strip, with no resize, no fullscreen transition and the
//      titlebar's own frame unmoved — in fullscreen it is the container around
//      it that travels. The buttons say so themselves and nothing else does.
//

import AppKit

/// Which window edge §3's sidebar stands on.
///
/// The traffic lights do not move with it. macOS puts them at the window's
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
    /// The lights sit at the same place in every chrome layout: the sidebar's
    /// control row and the top bar both start at the window's top-left, so
    /// switching layout or collapsing the sidebar must not move them. A test
    /// pins that down.
    ///
    /// `inset` is one number for both axes. It used to be a leading inset plus
    /// a vertical centring in the control row, which put the lights 8 pt from
    /// the window's leading edge and 18 pt from its top — unequal padding into
    /// a corner. The reference insets them equally.
    ///
    /// `system.titlebarHeight` is whichever container holds the buttons, not
    /// necessarily AppKit's titlebar: fullscreen takes that away and the lights
    /// move into `TrafficLightStrip`. Both are unflipped with their top edge on
    /// the window's, so one piece of arithmetic serves both — which is why the
    /// container is measured rather than named.
    ///
    /// - Returns: `nil` when the system owns the frames (page fullscreen, §3.6),
    ///   meaning "do not touch".
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

/// The lights' home in fullscreen, where AppKit's titlebar is not in the window
/// any more: a strip along the window's top edge, the titlebar's own height, in
/// front of the chrome so the three buttons sit on the sidebar rather than under
/// it. It holds AppKit's real buttons, so they keep their real actions.
///
/// It hit-tests to nothing of its own. A plain view answers for every point
/// inside its bounds, and this one lies across the top of §3.1's control row —
/// so the sidebar's toggle would have stopped taking clicks the moment the
/// window went fullscreen.
private final class TrafficLightStrip: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
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
    /// AppKit's own titlebar, and its height — captured at init, because
    /// fullscreen is precisely the state in which neither can be read. The
    /// first is where the buttons go home to, the second is the height the
    /// strip stands in for so the lights land on the same line either way.
    private weak var naturalSuperview: NSView?
    private let naturalTitlebarHeight: CGFloat
    private var strip: TrafficLightStrip?
    /// See `holdPlacement`. A second covers a launch with room to spare — the
    /// window is up in about a sixth of one — and a screen refresh is the
    /// rate at which a wrong placement would be visible anyway.
    private static let placementHold: TimeInterval = 1
    private static let placementStep: TimeInterval = 1.0 / 60
    private var holdUntil: Date?
    private var isHolding = false
    /// See `layoutButtons`: a pass writes frames, writing a frame is announced,
    /// and both this class and AppKit answer that announcement.
    private var isApplying = false
    private var wantsAnotherPass = false
    /// See `observe`: a new title takes the lights back into AppKit's titlebar.
    private var titleObservation: NSKeyValueObservation?

    /// §7.2: the sidebar is peeking over a hidden-sidebar window, so the lights
    /// belong back on screen for as long as it is there.
    var isPeeking = false {
        didSet {
            guard isPeeking != oldValue else { return }
            layoutButtons()
        }
    }

    /// Hidden while the page has the whole window.
    ///
    /// `⌘S` means "give the page the window", and three lights floating over
    /// the top-left corner of a web page is the one piece of chrome that did
    /// not go away — sitting on the site's own navigation more often than not.
    /// They come back the moment there is a sidebar to put them in, which
    /// includes a peek.
    private var hidesButtons: Bool {
        state.isSidebarCollapsed && !isPeeking
    }

    /// For a window that has no chrome to be in — Settings — whose lights must
    /// nevertheless land where every other Luna window's do. `.topBar` is the
    /// state that means exactly that: no sidebar to sit in, `trafficLightInset`
    /// from both edges. Settings' own column is already laid out from that
    /// number, so without this the lights and the content it clears disagree.
    convenience init(pinningLightsIn window: NSWindow) {
        self.init(window: window)
        apply(.topBar)
    }

    init(window: NSWindow) {
        self.window = window
        // Captured before anything moves them: these are AppKit's own origins
        // and only the deltas between them are used, so they never go stale.
        let buttons = Self.buttons(of: window)
        natural = buttons.map(\.frame.origin)
        naturalSuperview = buttons.first?.superview
        naturalTitlebarHeight = buttons.first?.superview?.bounds.height ?? 0
        observe(window)
    }

    /// Single entry point. Call it inside the same animation transaction as the
    /// layout change it belongs to — a second step is a visible jump (§4.1).
    func apply(_ state: ChromeState) {
        self.state = state
        layoutButtons()
        holdPlacement()
    }

    /// Keeps re-asserting the placement for a moment after a chrome change.
    ///
    /// The observers below catch every re-layout AppKit announces, and that is
    /// not all of them. Measured: five normal launches out of five ended with
    /// all three buttons back at AppKit's own origins — no resize, no titlebar
    /// frame change, no frame-change notification from the buttons, and no
    /// window notification of any kind between the placement and the reset.
    /// The same build launched from a shell, where the app never activates,
    /// was right every time, so the reset rides on the window becoming key and
    /// arrives without a word.
    ///
    /// So the placement is held rather than caught. A pass is three comparisons
    /// and writes nothing when nothing moved, which is the cost of all but one
    /// of these; it stops on its own, and `⌘S` was doing exactly this by hand.
    private func holdPlacement() {
        holdUntil = Date().addingTimeInterval(Self.placementHold)
        guard !isHolding else { return }
        isHolding = true
        checkPlacementAgain()
    }

    /// A chain rather than a repeating `Timer`: the run loop keeps a timer
    /// alive whether or not anyone is left to answer it, and this is a manager
    /// that goes when its window does.
    private func checkPlacementAgain() {
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.placementStep) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                guard let until = self.holdUntil, Date() < until else {
                    self.isHolding = false
                    return
                }
                self.layoutButtons()
                self.checkPlacementAgain()
            }
        }
    }

    // MARK: - Re-application

    private func observe(_ window: NSWindow) {
        let center = NotificationCenter.default
        // Target/action observers are zeroing-weak since 10.11, so there is
        // nothing to unregister and no `deinit` to reason about.
        for name: Notification.Name in [
            NSWindow.didResizeNotification,
            NSWindow.didEnterFullScreenNotification,
            NSWindow.didExitFullScreenNotification,
            // The window arriving on screen. It is the one re-layout AppKit
            // announces no other way, and the reason §3.1's row and the lights
            // could disagree on a fresh window.
            //
            // Measured at launch, in the layout that shows it: the manager
            // places the three at `trafficLightInset`, the window goes up, and
            // the zoom button alone is back at AppKit's own origin — nine
            // points high and nine points in, with close and miniaturize
            // correct beside it. No resize, no titlebar frame change, and no
            // frame-change notification from the button either, so none of the
            // three observers above hears a thing. Re-placing on any later
            // event sticks, which is why `⌘S` twice appeared to fix it: a
            // chrome-state change re-applies.
            NSWindow.didChangeOcclusionStateNotification
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
        // And the buttons, which is the whole of the warning fullscreen gives:
        // the titlebar sliding back down on a hover moves the container, not
        // the titlebar, and the three are not in either of them by then.
        for button in Self.buttons(of: window) {
            button.postsFrameChangedNotifications = true
            center.addObserver(
                self,
                selector: #selector(buttonDidMove),
                name: NSView.frameDidChangeNotification,
                object: button
            )
        }
        // A new title rebuilds AppKit's titlebar, and the rebuild takes the
        // three back into it. Windowed, that resets their origins and the
        // observer above hears it. In fullscreen they stand at the same
        // origins in the strip as in the titlebar, so the move changes no
        // frame and nothing is announced: the lights went into a titlebar
        // kept invisible, on every tab switch, since the title is the page's.
        titleObservation = window.observe(\.title) { [weak self] _, _ in
            MainActor.assumeIsolated {
                self?.layoutButtons()
                self?.holdPlacement()
            }
        }
    }

    /// One of the three moved. Whether this class moved it decides the hold:
    /// one that its own writes kept renewing would never stop.
    ///
    /// AppKit gets the last word inside its own layout pass — a button re-placed
    /// while it is being laid out is overwritten again a moment later, measured
    /// across a whole reveal — so the placement that sticks is the one made on
    /// a later turn, which is what `holdPlacement` is for. The pass below still
    /// runs first, because everywhere else it is the one that lands in the same
    /// frame as the change.
    @objc private func buttonDidMove(_ notification: Notification) {
        let wasOurs = isApplying
        layoutButtons()
        if !wasOurs { holdPlacement() }
    }

    /// Posted synchronously on the main thread by AppKit (`queue:` is deliberately
    /// not used: an enqueued re-apply lands a frame late and reads as a jump).
    @objc private func systemDidRelayout(_ notification: Notification) {
        layoutButtons()
    }

    /// A write is announced, and AppKit's own reset arrives inside one — so a
    /// pass landing during a pass asks for another rather than being turned
    /// away. A refused pass is a reset left standing, which is the zoom button
    /// alone in the wrong corner.
    private func layoutButtons() {
        if isApplying {
            wantsAnotherPass = true
            return
        }
        isApplying = true
        defer { isApplying = false }
        repeat {
            wantsAnotherPass = false
            placeButtons()
        } while wantsAnotherPass
    }

    private func placeButtons() {
        guard let window else { return }
        let buttons = Self.buttons(of: window)
        guard let first = buttons.first, let container = container(for: window, holding: buttons) else { return }

        // Before the placement, and unconditionally: a hidden button still has
        // a frame, and AppKit resets `isHidden` on some titlebar rebuilds the
        // same way it resets the origins.
        let hidden = hidesButtons
        for button in buttons where button.isHidden != hidden { button.isHidden = hidden }

        let system = TrafficLightMetrics(
            natural: natural,
            buttonHeight: first.frame.height,
            titlebarHeight: container.bounds.height
        )
        // In the strip the lights stand at AppKit's own origins and the strip
        // is what is placed (`container`), so AppKit's resets change nothing.
        let managed = container === strip ? natural : TrafficLightLayout.origins(
            for: state,
            system: system,
            inset: Tokens.Metric.trafficLightInset
        )
        guard let origins = managed, origins.count == buttons.count else { return }

        // Set directly, not through `animator()`: the placement is identical in
        // every managed state, so there is nothing to interpolate, and this runs
        // inside the caller's transaction anyway.
        var moved = false
        for (button, origin) in zip(buttons, origins) where button.frame.origin != origin {
            button.setFrameOrigin(origin)
            moved = true
        }
        // Whatever stands beside the lights measured them where they were. The
        // top bar laid its plate out against AppKit's default spacing at
        // launch, before this spread them, and kept the plate 9 pt too close
        // until something else happened to lay it out again.
        if moved, let root = window.contentView { TrafficLightSpace.neighboursNeedLayout(in: root) }
    }

    // MARK: - Where they live

    /// The view the lights are laid out in, moving them there first if that is
    /// not where they currently are.
    ///
    /// Windowed, that is AppKit's titlebar and nothing moves: the titlebar is
    /// what groups the three — hovering one shows all three glyphs — and that
    /// is not worth trading away for a corner they already sit in. Fullscreen
    /// there is no titlebar left in the window to group them, so the strip
    /// takes them and §3.1's row keeps its lights.
    private func container(for window: NSWindow, holding buttons: [NSButton]) -> NSView? {
        guard window.styleMask.contains(.fullScreen), let root = window.contentView else {
            sendHome(buttons)
            return buttons.first?.superview
        }
        let strip = strip ?? {
            let new = TrafficLightStrip()
            self.strip = new
            return new
        }()
        // AppKit's titlebar is empty in here — its lights are in the strip —
        // and it is what slides down under the menu bar as a band of plain
        // window colour over the top bar. Hidden until the lights go home.
        naturalSuperview?.superview?.alphaValue = 0
        // Above everything, every pass: the chrome is rebuilt on a layout
        // switch and a strip left behind it is three lights under a sidebar.
        if strip.superview !== root || root.subviews.last !== strip {
            root.addSubview(strip, positioned: .above, relativeTo: nil)
        }
        strip.frame = Self.stripFrame(
            in: root.bounds,
            natural: natural.first ?? .zero,
            buttonHeight: buttons.first?.frame.height ?? 0,
            inset: Tokens.Metric.trafficLightInset
        )
        for button in buttons where button.superview !== strip { strip.addSubview(button) }
        return strip
    }

    /// Where the strip stands so that the lights, at AppKit's own origins
    /// inside it, land `inset` from the window's top and leading edges — the
    /// windowed placement.
    ///
    /// The strip moves rather than the lights because AppKit keeps resetting
    /// them in fullscreen, each button on its own, to its origin in the
    /// titlebar — on every reveal of the menu bar among other times. Placed
    /// anywhere else, the one it had just reset stood nine points off its
    /// neighbours until this put it back: a staircase, for a frame or two, each
    /// time the pointer went to the top of the screen. At its own origin a
    /// reset moves it nowhere.
    nonisolated static func stripFrame(
        in root: NSRect,
        natural first: CGPoint,
        buttonHeight: CGFloat,
        inset: CGFloat
    ) -> NSRect {
        let height = first.y + buttonHeight + inset
        return NSRect(
            x: root.minX + inset - first.x,
            y: root.maxY - height,
            width: root.width,
            height: height
        )
    }

    /// Hands the buttons back to AppKit's titlebar and takes the strip down.
    /// Called on every windowed pass rather than on the exit notification alone,
    /// because AppKit restores the titlebar after posting it — and a set of
    /// lights that came home one frame late is a set that visibly jumped.
    private func sendHome(_ buttons: [NSButton]) {
        guard let titlebar = naturalSuperview else { return }
        titlebar.superview?.alphaValue = 1
        for button in buttons where button.superview !== titlebar { titlebar.addSubview(button) }
        strip?.removeFromSuperview()
        strip = nil
    }

    private static func buttons(of window: NSWindow) -> [NSButton] {
        buttonTypes.compactMap { window.standardWindowButton($0) }
    }
}
