//
//  SidebarPeek.swift
//  Luna
//
//  §7.2's hover-peek, and the answer to "where did my tabs go?" once `⌘S`
//  takes the sidebar away.
//
//  Hiding the sidebar used to leave the user with a full-bleed page and no
//  way back to it except the keystroke that hid it. The peek is the way back:
//  push the pointer against the window's leading edge and the sidebar slides
//  **over** the page — it does not push it — and slides away again when the
//  pointer leaves. The page never moves, so nothing reflows for a glance.
//
//  Two views, because the pointer is in one of two places and both of them
//  mean "keep it open": a 4 pt strip on the window's leading edge, and the
//  sidebar itself once it has arrived. `SidebarPeekController` is the little
//  state machine that ORs them together and applies §6's `hoverPeekDelay`, so
//  that sweeping the pointer across the edge on the way somewhere else does
//  not fling a sidebar out.
//

import AppKit

/// The invisible trigger strip on the window's leading edge.
///
/// **It never takes a click.** `hitTest` returns nil, so the page underneath
/// keeps every event; a tracking area does not need to win the hit test to
/// report enter and exit, which is the whole reason this can be a 4 pt strip
/// lying across a live web page.
@MainActor
final class SidebarPeekEdgeView: NSView {

    /// Off while the sidebar is showing — there is nothing to peek at, and the
    /// strip would sit on top of the sidebar's own leading edge.
    var isEnabled = false {
        didSet {
            guard isEnabled != oldValue else { return }
            if !isEnabled { onPointerInside?(false) }
            updateTrackingAreas()
        }
    }

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
        guard isEnabled else { return }
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) { onPointerInside?(true) }
    override func mouseExited(with event: NSEvent) { onPointerInside?(false) }
}

/// ORs the two hover sources and debounces them into one `isPeeking` flag.
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
    private var pending: Task<Void, Never>?

    /// Turns the whole machine off — and closes an open peek — when the window
    /// is not in a state that has anything to peek at.
    var isEnabled = true {
        didSet {
            guard isEnabled != oldValue, !isEnabled else { return }
            inEdge = false
            inSidebar = false
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

    private func schedule() {
        let wanted = isEnabled && (inEdge || inSidebar)
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
