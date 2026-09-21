//
//  DownloadsPanelController.swift
//  Luna
//
//  Puts §15.3's list up as a pop-out and keeps it live while it is open.
//
//  `DownloadManager.onChange` is installed only for as long as the panel is on
//  screen — that is what keeps the progress KVO from costing anything when
//  nobody is watching, and it is the one piece of behaviour worth carrying over
//  from the `NSPanel` this replaces.
//

import AppKit

@MainActor
final class DownloadsPanelController: PopoutController {

    private let manager: DownloadManager
    /// Set by `toggle(in:from:edge:)` before the panel is built.
    private var edge: PopoutEdge = .below
    /// §5.0's countdown, live only while the list is one this put up.
    private var countdown: Timer?

    init(manager: DownloadManager) {
        self.manager = manager
        super.init()
    }

    /// - Parameters:
    ///   - anchor: the Downloads button. The pop-out stands on it.
    ///   - edge: which way it grows — down from the top bar's capsule, up from
    ///     the foot of the sidebar.
    func toggle(in window: NSWindow, from anchor: NSView, edge: PopoutEdge) {
        self.edge = edge
        // A press claims the panel: whatever put it up, from here on it is the
        // user's and it stays until they are done with it.
        stopCountdown()
        toggle(in: window, from: anchor)
    }

    /// §5.0 — the list, opened by a download starting rather than by a press,
    /// so it says how far the file has got and then goes away by itself.
    ///
    /// It counts down, and §5's four seconds are the same four seconds. A
    /// panel that stood open over the page after every download would be a
    /// charge on the whole feature; a glance is what the arriving file is
    /// worth. Hovering it stops the clock, for the reason §5's popover stops
    /// its own.
    ///
    /// A panel that is already up is left exactly as it is. The user may
    /// have opened it themselves and be reading it, and a download landing is
    /// not a reason to re-animate a surface under their pointer — the new row
    /// appears in the list either way.
    func announce(in window: NSWindow, from anchor: NSView, edge: PopoutEdge) {
        guard !isPresented else { return }
        self.edge = edge
        present(in: window, from: anchor)
        presented?.onHoverChanged = { [weak self] hovering in
            hovering ? self?.stopCountdown() : self?.startCountdown()
        }
        startCountdown()
    }

    private func startCountdown() {
        stopCountdown()
        let timer = Timer(timeInterval: Tokens.Motion.downloadsAutoDismiss, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss() }
        }
        // `.common`, not `.default`: a countdown that quietly stops while the
        // user scrolls the page is a panel that never leaves.
        RunLoop.main.add(timer, forMode: .common)
        countdown = timer
    }

    private func stopCountdown() {
        countdown?.invalidate()
        countdown = nil
    }

    override func makePanel(in root: NSView) -> PopoutPanelView {
        let panel = DownloadsPanel(frame: root.bounds, edge: edge)
        panel.onOpen = { [weak self] item in self?.manager.open(item) }
        panel.onReveal = { [weak self] item in self?.manager.reveal(item) }
        panel.onRetry = { [weak self] item in self?.manager.retry(item) }
        panel.onClear = { [weak self] in self?.manager.clearCompleted() }
        return panel
    }

    override func panelDidAppear(_ panel: PopoutPanelView) {
        guard let panel = panel as? DownloadsPanel else { return }
        panel.setItems(manager.items)
        manager.onChange = { [weak self] in self?.reload() }
        panel.window?.makeFirstResponder(panel)
    }

    override func panelDidDisappear() {
        manager.onChange = nil
        stopCountdown()
    }

    private func reload() {
        (presented as? DownloadsPanel)?.setItems(manager.items)
    }
}
