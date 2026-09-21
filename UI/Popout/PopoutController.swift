//
//  PopoutController.swift
//  Luna
//
//  Putting a `PopoutPanelView` up and taking it down again: the sheet goes into
//  the window's content view, the anchor is read live so a resize under an open
//  pop-out moves it with the button, and `esc` closes it from anywhere in the
//  app rather than only from whatever has focus inside it.
//
//  Subclasses build the panel and fill it. Everything below is the part History
//  and Downloads were doing identically.
//

import AppKit

@MainActor
class PopoutController: NSObject {

    private(set) var presented: PopoutPanelView?
    private var escapeMonitor: Any?

    var isPresented: Bool { presented != nil }

    /// Builds the pop-out for this presentation. Subclasses fill the panel's
    /// `body` and wire its callbacks; the anchor, the escape key and the
    /// dismissal are handled here.
    func makePanel(in root: NSView) -> PopoutPanelView {
        fatalError("PopoutController subclasses build their own panel")
    }

    /// Called once the panel is in the tree, before it animates in.
    func panelDidAppear(_ panel: PopoutPanelView) {}

    /// Called when the pop-out is dismissed, for whatever the subclass was
    /// holding on its behalf.
    ///
    /// At the start of the closing animation rather than the end of it: from
    /// the moment the user asked for it to go, it is not a surface anybody is
    /// updating — a list that re-sorted itself while it was folding away would
    /// be answering a question that has been withdrawn.
    func panelDidDisappear() {}

    // MARK: - Presentation

    func toggle(in window: NSWindow, from anchor: NSView) {
        if isPresented { dismiss() } else { present(in: window, from: anchor) }
    }

    func present(in window: NSWindow, from anchor: NSView) {
        guard let root = window.contentView else { return }
        if presented != nil { dismiss() }

        let panel = makePanel(in: root)
        // Weak on both sides — the panel outlives neither, but it is the panel
        // that is holding this closure.
        panel.anchorRect = { [weak panel, weak anchor] in
            guard let panel, let anchor, anchor.window != nil else { return .zero }
            return panel.convert(anchor.bounds, from: anchor)
        }
        panel.onBackgroundClick = { [weak self] in self?.dismiss() }
        root.addSubview(panel, positioned: .above, relativeTo: nil)
        presented = panel

        panelDidAppear(panel)
        panel.animateIn()
        installEscapeMonitor()
    }

    /// Closes the pop-out: gone at once as far as the rest of the app is
    /// concerned, and on screen for as long as it takes to fold back into its
    /// button (`PopoutPanelView.animateOut`).
    ///
    /// The two are separate on purpose. `isPresented` answers "is there a
    /// pop-out open", which stops being true the moment the user closes it —
    /// `toggle` must open a new one rather than find this one still there, and
    /// §5.0's list must be free to put itself up again for a download that
    /// lands during the animation. The view that is still fading is nobody's
    /// business but this method's, which is why it takes no callers with it.
    func dismiss() {
        guard let panel = presented else { return }
        presented = nil
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        escapeMonitor = nil
        // It is closing, so it no longer answers the click that closes it.
        panel.onBackgroundClick = nil
        panelDidDisappear()
        panel.animateOut()
    }

    /// `esc` closes the pop-out from anywhere in it, not only from a field —
    /// a field handles its own first, because it has a query to clear.
    private func installEscapeMonitor() {
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // 53 is `esc`. `charactersIgnoringModifiers` is empty for it.
            guard event.keyCode == 53, let self, isPresented else { return event }
            MainActor.assumeIsolated { self.dismiss() }
            return nil
        }
    }
}
