//
//  ChromeHostView.swift
//  Luna
//
//  The one view `BrowserWindowController` hosts as "the chrome". It holds both
//  layouts — the sidebar (§3) and the top bar (§4) — and cross-fades between
//  them while the window controller animates the frame around it.
//
//  Why one host instead of swapping the window's chrome view: the window
//  controller re-anchors the traffic lights inside its own layout transaction
//  (§4.1), and swapping the view would need a second pass over that geometry.
//  One host means the switch is a fade inside a frame that is already
//  animating, and the lights never move twice.
//

import AppKit

/// Holds the sidebar and the top bar, shows one of them.
@MainActor
final class ChromeHostView: NSView {

    /// Fired when the sidebar becomes the visible layout, before the fade.
    ///
    /// **`NSTableView` does not survive being hidden.** While the top bar is
    /// showing, the sidebar is `isHidden` inside a host that is 52 pt tall, so
    /// the list has no visible rect and AppKit releases every row view it was
    /// recycling. Unhiding restores the frame but not the rows — the list came
    /// back empty, which is exactly what "the website tabs on the left are
    /// gone" was. The list reloads on this.
    var onShowSidebar: (() -> Void)?

    /// The pointer arrived on, or left, whichever layout is showing. §7.2's
    /// hover-peek keeps the hidden sidebar out for as long as this is true —
    /// the edge strip that summoned it is underneath the sidebar by then, so
    /// it cannot be the one to answer.
    var onPointerInside: ((Bool) -> Void)?

    /// §7.2: the chrome is floating **over the page** rather than sitting in
    /// its own column of the window.
    ///
    /// The window's glass is behind the content card, not in front of it, so a
    /// peeked sidebar had nothing under it at all — the page showed straight
    /// through the gaps between its rows. This puts the chrome plane back: the
    /// same `.sidebar` material, with the opaque backdrop forced on, because
    /// glass cannot see in-window content and a peek is nothing but in-window
    /// content (`Glass.setOpaqueBackdrop`).
    var isPeeking = false {
        didSet {
            guard isPeeking != oldValue else { return }
            updateBackdrop(animated: true)
        }
    }

    private var sidebar: NSView?
    private var topBar: NSView?
    /// Built the first time the sidebar peeks, and never for a window whose
    /// sidebar is simply on — where the window's own glass is already there and
    /// a second plane would double §2's tint.
    private var backdrop: NSView?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        // The host is a 280 pt column in one layout and a 52 pt row in the
        // other; mid-animation it is neither, and the contents must not paint
        // outside it.
        layer?.masksToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its views in code")
    }

    /// Takes both layouts up front. Neither is rebuilt on a switch: they keep
    /// their scroll position, their selection and their hover state.
    func install(sidebar: NSView, topBar: NSView) {
        for view in [sidebar, topBar] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
            NSLayoutConstraint.activate([
                view.topAnchor.constraint(equalTo: topAnchor),
                view.leadingAnchor.constraint(equalTo: leadingAnchor),
                view.trailingAnchor.constraint(equalTo: trailingAnchor),
                view.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
        }
        self.sidebar = sidebar
        self.topBar = topBar
        apply(showingTopBar: false, animated: false)
    }

    /// Call this immediately before `BrowserWindowController.setChromeState` so
    /// the fade and the frame run on the same tick and the same §6 spec.
    func setLayout(_ state: ChromeState) {
        if case .topBar = state {
            apply(showingTopBar: true, animated: true)
        } else {
            apply(showingTopBar: false, animated: true)
        }
    }

    private func apply(showingTopBar: Bool, animated: Bool) {
        let incoming = showingTopBar ? topBar : sidebar
        let outgoing = showingTopBar ? sidebar : topBar
        incoming?.isHidden = false
        if !showingTopBar { onShowSidebar?() }
        guard animated else {
            incoming?.alphaValue = 1
            outgoing?.alphaValue = 0
            outgoing?.isHidden = true
            return
        }
        Tokens.Motion.animate(Tokens.Motion.layoutSwitch) { _ in
            incoming?.animator().alphaValue = 1
            outgoing?.animator().alphaValue = 0
        } completion: { [self] in
            // A view at alpha 0 still hit-tests, so the hidden layout would
            // keep eating clicks. Hiding it is the only thing that stops that.
            // Re-read rather than capture — `NSView` is not `Sendable` — and
            // check the alpha, because a second toggle may have landed first.
            MainActor.assumeIsolated {
                let faded = showingTopBar ? self.sidebar : self.topBar
                if faded?.alphaValue == 0 { faded?.isHidden = true }
            }
        }
    }

    private func updateBackdrop(animated: Bool) {
        let target: CGFloat = isPeeking ? 1 : 0
        guard let view = backdrop ?? (target > 0 ? makeBackdrop() : nil) else { return }
        guard animated else {
            view.alphaValue = target
            return
        }
        // The same spec the slide runs on, so the plane arrives with the
        // sidebar rather than fading in behind it.
        Tokens.Motion.animate(Tokens.Motion.sidebarCollapse) { context in
            context.allowsImplicitAnimation = true
            view.animator().alphaValue = target
        }
    }

    private func makeBackdrop() -> NSView {
        let view = Glass.apply(.sidebar, to: self)
        Glass.setOpaqueBackdrop(true, on: self)
        view.alphaValue = 0
        backdrop = view
        return view
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where area.owner === self { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) { onPointerInside?(true) }
    override func mouseExited(with event: NSEvent) { onPointerInside?(false) }

    /// §30.1: dragging the chrome moves the window. `ContentCardView` returns
    /// false for the same reason — a web page is not a drag handle. Controls
    /// inside the sidebar and the bar override this themselves.
    override var mouseDownCanMoveWindow: Bool { true }
}
