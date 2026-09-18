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

import AppKit
import BrowserKit

@MainActor
final class HistoryPanelController: NSObject {

    private let session: BrowserSession
    private var panel: HistoryPanel?
    private var entries: [HistoryEntry] = []
    private var monitor: Any?

    init(session: BrowserSession) {
        self.session = session
        super.init()
    }

    var isPresented: Bool { panel != nil }

    // MARK: - Presentation

    func toggle(in window: NSWindow) {
        if isPresented { dismiss() } else { present(in: window) }
    }

    func present(in window: NSWindow) {
        guard let root = window.contentView else { return }
        if panel != nil { dismiss() }
        entries = session.archived.map(Self.entry)

        let panel = HistoryPanel(frame: root.bounds)
        panel.contentRegion = contentRegion
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
        panel.onBackgroundClick = { [weak self] in self?.dismiss() }
        panel.onFilter = { [weak self] text in self?.filter(text) }
        panel.onChoose = { [weak self] id in self?.restore(id) }
        root.addSubview(panel, positioned: .above, relativeTo: nil)
        self.panel = panel

        panel.setEntries(entries)
        panel.animateIn()
        panel.focusFilter()
        installEscapeMonitor()
    }

    func dismiss() {
        panel?.removeFromSuperview()
        panel = nil
        entries = []
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    /// Where the page is inside the window, so the panel sits over the page and
    /// not over the window. Set by the assembly seam, like the Command Bar's.
    var contentRegion: (() -> NSRect)?

    // MARK: - Behaviour

    private func filter(_ text: String) {
        let needle = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return panel?.setEntries(entries) ?? () }
        panel?.setEntries(entries.filter { $0.searchText.contains(needle) })
    }

    private func restore(_ id: UUID) {
        session.unarchiveTab(id)
        dismiss()
    }

    /// `esc` closes the panel from anywhere in it, not only from the field —
    /// the field handles its own because it has a query to clear first.
    private func installEscapeMonitor() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // 53 is `esc`. `charactersIgnoringModifiers` is empty for it.
            guard event.keyCode == 53, let self, isPresented else { return event }
            MainActor.assumeIsolated { self.dismiss() }
            return nil
        }
    }

    // MARK: - Model

    private static func entry(_ tab: Tab) -> HistoryEntry {
        let host = tab.url.host() ?? tab.url.absoluteString
        let title = tab.title.isEmpty ? host : tab.title
        let when = tab.archivedAt.map(formatter.string(from:)) ?? ""
        return HistoryEntry(
            id: tab.id,
            title: title,
            subtitle: when.isEmpty ? host : "\(host) · \(when)",
            host: tab.url.host() ?? "",
            searchText: (title + " " + host).lowercased()
        )
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
