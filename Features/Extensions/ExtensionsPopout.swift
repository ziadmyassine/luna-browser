//
//  ExtensionsPopout.swift
//  Luna
//
//  Puts §16.4's pop-out up from a window's extensions button and keeps it
//  live while it is open: a pin, a badge or an extension switched off
//  elsewhere changes the rows under the pointer.
//

import AppKit
import BrowserKit

@MainActor
final class ExtensionsPopoutController: PopoutController {

    private var edge: PopoutEdge = .below
    private weak var session: BrowserSession?
    private var windowID: UUID?
    private weak var anchor: NSView?
    private var observer: (any NSObjectProtocol)?

    func toggle(in window: NSWindow, from anchor: NSView, edge: PopoutEdge, session: BrowserSession, windowID: UUID) {
        self.edge = edge
        self.session = session
        self.windowID = windowID
        self.anchor = anchor
        toggle(in: window, from: anchor)
    }

    private var items: [ExtensionShelfItem] {
        guard let session, let windowID else { return [] }
        return ExtensionsCenter.shared.allItems(in: session, window: windowID)
    }

    override func makePanel(in root: NSView) -> PopoutPanelView {
        let panel = ExtensionsPanel(frame: root.bounds, edge: edge, items: items)
        panel.onRun = { [weak self] id in self?.run(id) }
        panel.onPin = { id, pinned in ExtensionsCenter.shared.setPinned(pinned, id) }
        panel.onSwitch = { [weak self] id, isOn in self?.setOn(isOn, id) }
        panel.onManage = { [weak self] in
            self?.dismiss()
            (NSApp.delegate as? AppDelegate)?.showSettings(section: ExtensionsSection.id)
        }
        return panel
    }

    override func panelDidAppear(_ panel: PopoutPanelView) {
        observer = NotificationCenter.default.addObserver(
            forName: ExtensionsCenter.didChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
        panel.window?.makeFirstResponder(panel)
    }

    override func panelDidDisappear() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
    }

    private func reload() {
        (presented as? ExtensionsPanel)?.setItems(items)
    }

    /// Closes first, then runs: the extension's popup opens on the button the
    /// pop-out came from, and two panels on one button is one too many.
    private func run(_ id: String) {
        guard let session, let windowID, let anchor else { return }
        dismiss()
        ExtensionsCenter.shared.perform(id, in: session, window: windowID, from: anchor)
    }

    private func setOn(_ isOn: Bool, _ id: String) {
        guard let session, let windowID else { return }
        let space = session.activeSpaceID(inWindow: windowID)
        Task { try? await ExtensionsCenter.shared.setEnabled(isOn, id, inSpace: space) }
    }
}

/// The entry point every surface's extensions button calls, as `SiteMenu` is
/// for §3.2's site settings.
@MainActor
enum ExtensionsPopout {

    static let controller = ExtensionsPopoutController()

    /// - Parameter aligned: a view to line the pop-out's leading edge up
    ///   with — the sidebar's search bar, which the button sits in.
    static func present(from anchor: NSView, session: BrowserSession, windowID: UUID, alignedTo aligned: NSView? = nil) {
        guard let window = anchor.window else { return }
        controller.alignsLeadingEdgeTo = aligned
        let edge: PopoutEdge = anchor.convert(anchor.bounds, to: nil).midY > window.contentLayoutRect.midY
            ? .below
            : .above
        controller.toggle(in: window, from: anchor, edge: edge, session: session, windowID: windowID)
    }

    static func closeAll() {
        guard controller.isPresented else { return }
        controller.dismiss()
    }
}
