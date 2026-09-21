//
//  HistoryPanelController.swift
//  Luna
//
//  Presents §6.4's panel, filters it, and puts a chosen tab back.
//
//  The archive is already in memory — `BrowserSession.archived` is a view over
//  the same table the tab list reads (§11.1) — so filtering is a `contains` over
//  an array the session is holding anyway. No query, no debounce, no store.
//
//  §6.4's panel is a pop-out from the button that opens it — see
//  `HistoryPanel`'s header for why it is no longer centred over the page — so
//  this takes the anchor view rather than a content region.
//
//  There are two such buttons now: §3.5's, at the foot of the sidebar, and its
//  twin in §4's action capsule. They are at opposite ends of the window, so the
//  caller says which way the pop-out grows and `PopoutController` does the
//  rest.
//

import AppKit
import BrowserKit

@MainActor
final class HistoryPanelController: PopoutController {

    private let session: BrowserSession
    private var entries: [HistoryEntry] = []
    /// Set by `toggle(in:from:edge:)` before the panel is built.
    private var edge: PopoutEdge = .above

    init(session: BrowserSession) {
        self.session = session
        super.init()
    }

    // MARK: - Presentation

    /// - Parameters:
    ///   - anchor: the History button. The pop-out stands on it.
    ///   - edge: which way it grows — up from the sidebar's foot, down from the
    ///     top bar's capsule.
    func toggle(in window: NSWindow, from anchor: NSView, edge: PopoutEdge) {
        self.edge = edge
        toggle(in: window, from: anchor)
    }

    override func makePanel(in root: NSView) -> PopoutPanelView {
        entries = session.archived.map(Self.entry)
        let panel = HistoryPanel(frame: root.bounds, edge: edge)
        // The live session first — an archived tab that was open this launch
        // still has its icon in memory — then §4.7's on-disk cache by host,
        // which is where every other archived tab's icon lives.
        panel.iconProvider = { [weak session] entry in
            if let image = session?.favicon(for: entry.id) { return image }
            guard !entry.host.isEmpty,
                  let data = FaviconService.shared.favicon(forHost: entry.host)
            else { return nil }
            return NSImage(data: data)
        }
        panel.onFilter = { [weak self] text in self?.filter(text) }
        panel.onChoose = { [weak self] id in self?.restore(id) }
        return panel
    }

    override func panelDidAppear(_ panel: PopoutPanelView) {
        guard let panel = panel as? HistoryPanel else { return }
        panel.setEntries(entries)
        panel.focusFilter()
    }

    override func panelDidDisappear() {
        entries = []
    }

    // MARK: - Behaviour

    private func filter(_ text: String) {
        guard let panel = presented as? HistoryPanel else { return }
        let needle = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return panel.setEntries(entries) }
        panel.setEntries(entries.filter { $0.searchText.contains(needle) })
    }

    private func restore(_ id: UUID) {
        session.unarchiveTab(id)
        dismiss()
    }

    // MARK: - Model

    /// The host and the time are two strings, not one: the row sets them as
    /// separate labels so that the one which has to give way is the host. See
    /// `HistoryTimestamp`.
    private static func entry(_ tab: Tab) -> HistoryEntry {
        let host = tab.url.host() ?? tab.url.absoluteString
        let title = tab.title.isEmpty ? host : tab.title
        return HistoryEntry(
            id: tab.id,
            title: title,
            subtitle: host,
            when: tab.archivedAt.map { HistoryTimestamp.string(for: $0) } ?? "",
            host: tab.url.host() ?? "",
            searchText: (title + " " + host).lowercased()
        )
    }
}
