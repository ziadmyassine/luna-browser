//
//  SidebarPeek.swift
//  Luna
//
//  §7.2's hover-peek, and the answer to "where did my tabs go?" once `⌘S`
//  takes the sidebar away.
//
//  Hiding the sidebar used to leave a full-bleed page and no way back except
//  the keystroke that hid it. The peek is the way back: push the pointer
//  against the window's leading edge and the sidebar slides over the page
//  rather than pushing it, and slides away when the pointer leaves. The page
//  never moves, so nothing reflows for a glance.
//
//  Three places the pointer can be that mean "keep it open": a strip on the
//  window's leading edge, the menu bar in fullscreen, and the sidebar itself
//  once it has arrived. `SidebarPeekController` ORs them together and applies
//  §6's `hoverPeekDelay`, so sweeping across the edge on the way somewhere else
//  does not fling a sidebar out.
//

import AppKit

/// The invisible trigger strip on the window's leading edge.
///
/// It never takes a click. `hitTest` returns nil, so the page underneath
/// keeps every event; a tracking area does not need to win the hit test to
/// report enter and exit, which is the whole reason this can be a 4 pt strip
/// lying across a live web page.
///
/// A pointer that leaves the window across the strip's edge is still in it,
/// for as long as it stays out beside the strip — Dia's rule, measured: its
/// sidebar comes out anywhere to the left of its window. The strip can then be
/// narrow enough never to cover a control, and shoving the mouse left cannot
/// overshoot it.
@MainActor
final class SidebarPeekEdgeView: NSView {

    /// Off while the sidebar is showing — there is nothing to peek at, and the
    /// strip would sit on top of the sidebar's own leading edge.
    var isEnabled = false {
        didSet {
            guard isEnabled != oldValue else { return }
            if !isEnabled {
                stopWatchingBeyond()
                onPointerInside?(false)
            }
            updateTrackingAreas()
        }
    }

    /// Polls the pointer while it is outside the window beside the strip. No
    /// tracking area reaches past the window, and this runs only in that state.
    private var beyondWatch: Timer?

    /// The pointer leaving the window at all, heard on the root view. A quick
    /// shove left moves the pointer in steps wider than the strip — 30 pt in
    /// on one event, 20 pt out on the next — so the strip never saw it arrive
    /// or leave and the sidebar stayed shut. The window's own edge cannot be
    /// stepped over.
    private var windowArea: NSTrackingArea?

    var onPointerInside: ((Bool) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where area.owner === self { removeTrackingArea(area) }
        if let windowArea { superview?.removeTrackingArea(windowArea) }
        windowArea = nil
        guard isEnabled else { return }
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect]
        addTrackingArea(NSTrackingArea(rect: .zero, options: options, owner: self))
        let area = NSTrackingArea(rect: .zero, options: options, owner: self)
        superview?.addTrackingArea(area)
        windowArea = area
    }

    override func viewWillMove(toSuperview newSuperview: NSView?) {
        if let windowArea { superview?.removeTrackingArea(windowArea) }
        windowArea = nil
        super.viewWillMove(toSuperview: newSuperview)
    }

    override func mouseEntered(with event: NSEvent) {
        // Coming back into the window is not coming into the strip.
        guard event.trackingArea !== windowArea else { return }
        stopWatchingBeyond()
        onPointerInside?(true)
    }

    override func mouseExited(with event: NSEvent) {
        let beyond = superview.map { root in
            Self.isBeyond(root.convert(event.locationInWindow, from: nil), strip: frame, in: root.bounds)
        } ?? false
        if isEnabled, beyond, let window {
            onPointerInside?(true)
            return watchBeyond(in: window)
        }
        // Leaving the window any other way says nothing about the strip.
        guard event.trackingArea !== windowArea, beyondWatch == nil else { return }
        onPointerInside?(false)
    }

    /// Whether `point` is outside `bounds`, past the edge `strip` lies on and
    /// level with it. Every rect in the root view's coordinates.
    static func isBeyond(_ point: NSPoint, strip: NSRect, in bounds: NSRect) -> Bool {
        guard point.y >= strip.minY, point.y <= strip.maxY else { return false }
        let onLeading = strip.minX <= bounds.minX + 0.5
        return onLeading ? point.x < bounds.minX : point.x > bounds.maxX
    }

    private func watchBeyond(in window: NSWindow) {
        stopWatchingBeyond()
        let watch = Timer(timeInterval: Tokens.Motion.hoverPeekDelay, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let root = self.superview else { return }
                let point = root.convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
                guard !Self.isBeyond(point, strip: self.frame, in: root.bounds) else { return }
                self.stopWatchingBeyond()
                // Back over the strip is its own enter; anywhere else is out.
                if !self.frame.contains(point) { self.onPointerInside?(false) }
            }
        }
        RunLoop.main.add(watch, forMode: .common)
        beyondWatch = watch
    }

    private func stopWatchingBeyond() {
        beyondWatch?.invalidate()
        beyondWatch = nil
    }
}

/// §7.2 in fullscreen: going up to the menu bar brings the sidebar out with it.
///
/// It watches the pointer rather than a tracking area. At the top edge macOS
/// slides its own menu bar and the fullscreen titlebar over the window, and a
/// strip of Luna's under them never heard the pointer arrive. So while it is
/// on — fullscreen, sidebar hidden — it reads the pointer every
/// `hoverPeekDelay`: reaching the screen's top edge, where macOS reveals the
/// menu bar, opens the peek, and it holds for as long as the pointer is in the
/// menu bar's height.
@MainActor
final class SidebarPeekMenuBarWatch {

    weak var window: NSWindow?
    var onPointerInside: ((Bool) -> Void)?

    /// On only in fullscreen with the sidebar hidden.
    var isEnabled = false {
        didSet {
            guard isEnabled != oldValue else { return }
            if isEnabled { start() } else { stop() }
        }
    }

    private var timer: Timer?
    private var isInside = false

    /// Whether the pointer counts as up in the menu bar. Reaching the top edge
    /// is what gets it in, because that is what reveals the menu bar; the
    /// menu bar's height is what keeps it in, because that is where its menus
    /// are. A point on another display is never in it.
    static func isInMenuBar(_ point: NSPoint, wasInside: Bool, screen: NSRect, menuBarHeight: CGFloat) -> Bool {
        guard point.x >= screen.minX, point.x <= screen.maxX, point.y <= screen.maxY else { return false }
        return point.y >= screen.maxY - (wasInside ? menuBarHeight : Tokens.Metric.sidebarPeekEdgeFullScreen)
    }

    private func start() {
        let timer = Timer(timeInterval: Tokens.Motion.hoverPeekDelay, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        timer.tolerance = Tokens.Motion.hoverPeekDelay / 2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
        guard isInside else { return }
        isInside = false
        onPointerInside?(false)
    }

    private func check() {
        guard let window, window.isKeyWindow, let screen = window.screen?.frame else { return }
        let height = NSApp.mainMenu?.menuBarHeight ?? NSStatusBar.system.thickness
        let inside = Self.isInMenuBar(NSEvent.mouseLocation, wasInside: isInside, screen: screen, menuBarHeight: height)
        guard inside != isInside else { return }
        isInside = inside
        onPointerInside?(inside)
    }
}

/// ORs the hover sources and debounces them into one `isPeeking` flag.
///
/// The delay is asymmetric on purpose. Opening waits `hoverPeekDelay` so a
/// pointer crossing the edge on its way to the page does not trigger it;
/// closing waits the same again, because the pointer leaves the strip the
/// instant the sidebar arrives over it and a zero-delay close would make the
/// sidebar flicker in and straight back out.
@MainActor
final class SidebarPeekController {

    /// Called when the peek should open or close. Never called twice with the
    /// same value.
    var onChange: ((Bool) -> Void)?

    private(set) var isPeeking = false
    private var inEdge = false
    private var inSidebar = false
    private var inMenuBar = false
    private var pending: Task<Void, Never>?

    /// Turns the whole machine off — and closes an open peek — when the window
    /// is not in a state that has anything to peek at.
    var isEnabled = true {
        didSet {
            guard isEnabled != oldValue, !isEnabled else { return }
            inEdge = false
            inSidebar = false
            inMenuBar = false
            settle(to: false, immediately: true)
        }
    }

    func setPointerInEdge(_ inside: Bool) {
        inEdge = inside
        schedule()
    }

    func setPointerInSidebar(_ inside: Bool) {
        inSidebar = inside
        schedule()
    }

    func setPointerInMenuBar(_ inside: Bool) {
        inMenuBar = inside
        schedule()
    }

    private func schedule() {
        let wanted = isEnabled && (inEdge || inSidebar || inMenuBar)
        guard wanted != isPeeking else {
            pending?.cancel()
            pending = nil
            return
        }
        pending?.cancel()
        // `@MainActor` class, so the task body is main-actor too: no hop, and
        // no `@Sendable` closure reaching back into this state.
        pending = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Tokens.Motion.hoverPeekDelay))
            guard !Task.isCancelled else { return }
            self?.settle(to: wanted, immediately: false)
        }
    }

    private func settle(to peeking: Bool, immediately: Bool) {
        if immediately {
            pending?.cancel()
            pending = nil
        }
        guard peeking != isPeeking else { return }
        isPeeking = peeking
        onChange?(peeking)
    }
}
