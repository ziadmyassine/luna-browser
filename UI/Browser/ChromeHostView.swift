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

    private var sidebar: NSView?
    private var topBar: NSView?

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

    /// §30.1: dragging the chrome moves the window. `ContentCardView` returns
    /// false for the same reason — a web page is not a drag handle. Controls
    /// inside the sidebar and the bar override this themselves.
    override var mouseDownCanMoveWindow: Bool { true }
}
