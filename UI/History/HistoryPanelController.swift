//
//  HistoryPanelController.swift
//  Luna
//
//  Presents §6.4's panel, asks the store for the pages to put in it, and opens
//  the one chosen.
//
//  History is the store's, not the session's: every visit the Space has made,
//  far more than memory holds. So the list is a query — the newest pages when
//  the field is empty, a search of titles and addresses through the Command
//  Bar's index as it is typed — and only the Space you are in, as with its
//  cookie jar (§9.2).
//
//  The pop-out stands on the button that opened it, so this takes the anchor
//  view rather than a content region. The two buttons, §3.5's and its twin in
//  §4's action capsule, are at opposite ends of the window, so the caller says
//  which way the pop-out grows.
//

import AppKit
import BrowserKit

@MainActor
final class HistoryPanelController: PopoutController {

    /// How many pages the list holds. The newest few hundred is what a glance
    /// at history is for; anything older is found by searching for it.
    static let limit = 300

    private let session: BrowserSession
    /// Set by `toggle(in:from:edge:)` before the panel is built.
    private var edge: PopoutEdge = .above
    /// The query in flight. A newer keystroke cancels it, so a slow answer to an
    /// old query never lands over the answer to the current one.
    private var loading: Task<Void, Never>?

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
        let panel = HistoryPanel(frame: root.bounds, edge: edge)
        // §4.7's on-disk cache by host: most of these pages have no tab, and
        // that cache is where their icons are.
        panel.iconProvider = { [weak session] entry in
            guard !entry.host.isEmpty,
                  let data = session?.favicons.favicon(forHost: entry.host)
            else { return nil }
            return NSImage(data: data)
        }
        panel.onFilter = { [weak self] text in self?.load(text) }
        panel.onChoose = { [weak self] entry in self?.open(entry.url) }
        return panel
    }

    override func panelDidAppear(_ panel: PopoutPanelView) {
        guard let panel = panel as? HistoryPanel else { return }
        panel.focusFilter()
        load("")
    }

    override func panelDidDisappear() {
        loading?.cancel()
        loading = nil
    }

    // MARK: - Behaviour

    private func load(_ text: String) {
        loading?.cancel()
        let query = text.trimmingCharacters(in: .whitespaces)
        loading = Task { [weak self, session] in
            let pages = await session.browsingHistory(matching: query, limit: Self.limit)
            guard !Task.isCancelled, let panel = self?.presented as? HistoryPanel else { return }
            panel.setEntries(pages.map(Self.entry))
        }
    }

    /// The page, in the tab that already has it if there is one — a second
    /// copy of a page that is open is a tab the user then has to find and
    /// close — and in a new tab otherwise.
    private func open(_ url: URL) {
        let key = CommandBarURL.dedupeKey(url)
        if let tab = session.tabsInActiveSpace(includeArchived: false)
            .first(where: { CommandBarURL.dedupeKey($0.url) == key }) {
            session.activateTab(tab.id)
        } else {
            session.newTab(url: url)
        }
        dismiss()
    }

    // MARK: - Model

    /// The host and the time are two strings, not one: the row sets them as
    /// separate labels so that the one which has to give way is the host. See
    /// `HistoryTimestamp`.
    private static func entry(_ page: HistoryHit) -> HistoryEntry {
        let host = page.url.host() ?? page.url.absoluteString
        return HistoryEntry(
            id: UUID(),
            title: page.title.isEmpty ? CommandBarURL.displayForm(of: page.url) : page.title,
            subtitle: host,
            when: page.lastVisit.map { HistoryTimestamp.string(for: $0) } ?? "",
            host: page.url.host() ?? "",
            url: page.url
        )
    }
}
