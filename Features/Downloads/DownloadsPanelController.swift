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
        toggle(in: window, from: anchor)
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
    }

    private func reload() {
        (presented as? DownloadsPanel)?.setItems(manager.items)
    }
}
