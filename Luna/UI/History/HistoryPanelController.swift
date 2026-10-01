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
//  Deleting (§11.3) is asked of the session and answered by loading the list
//  again; the row menu and the two questions it can ask are in
//  `HistoryMenu.swift`.
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
    /// What the field holds, so a delete can ask the same question again.
    private var query = ""
    /// The newest delete, which waits for any before it. Tests await it.
    private(set) var deleting: Task<Void, Never>?

    /// Asks which span Clear History… clears, nil for Cancel. A seam, so a test
    /// can answer without a modal loop.
    var askClearRange: @MainActor (_ spaceName: String) -> HistoryClearRange? = HistoryMenu.askClearRange(spaceName:)
    /// Asks before forgetting a site, which signs the Space out of it.
    var confirmForget: @MainActor (_ site: String, _ spaceName: String) -> Bool = HistoryMenu.confirmForget(site:spaceName:)

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
            guard let session else { return nil }
            if !entry.host.isEmpty, let data = session.favicons.favicon(forHost: entry.host) {
                return NSImage(data: data)
            }
            // History is the Space's own (§6.4), so its monograms wear its colour.
            let gradient = session.space(session.activeSpaceID)?.gradient ?? Tokens.Gradient.neutral
            return SiteMonogram.image(for: entry.url, on: gradient)
        }
        panel.onFilter = { [weak self] text in self?.load(text) }
        panel.onChoose = { [weak self] entry in self?.open(entry.url) }
        panel.onDelete = { [weak self] pages in self?.delete(pages) }
        panel.menuProvider = { [weak self] pages in self.map { HistoryMenu.build(for: pages, controller: $0) } }
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
        query = text.trimmingCharacters(in: .whitespaces)
        loading = Task { [weak self, session, query] in
            let pages = await session.browsingHistory(matching: query, limit: Self.limit)
            guard !Task.isCancelled, let panel = self?.presented as? HistoryPanel else { return }
            let now = Date()
            panel.setEntries(pages.map { Self.entry($0, now: now) })
        }
    }

    // MARK: - Deleting (§11.3)

    func delete(_ pages: [HistoryEntry]) {
        run { session in await session.deleteHistory(of: pages.map(\.url)) }
    }

    /// History ▸ Clear History…, and the row menu's. Works with the pop-out
    /// closed too: the menu bar's item does not open it.
    func clearHistory() {
        guard let range = askClearRange(spaceName) else { return }
        run { session in await session.clearHistory(range) }
    }

    /// The site's pages and its website data, in this Space.
    func forgetSite(_ site: String) {
        guard confirmForget(site, spaceName) else { return }
        run { session in await session.forgetSite(site) }
    }

    private var spaceName: String {
        session.space(session.activeSpaceID)?.name ?? ""
    }

    /// Runs one delete after the last, then asks for the list again.
    private func run(_ work: @escaping (BrowserSession) async -> Void) {
        let previous = deleting
        deleting = Task { [weak self, session] in
            await previous?.value
            await work(session)
            guard let self, isPresented else { return }
            load(query)
            await loading?.value
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
    private static func entry(_ page: HistoryHit, now: Date) -> HistoryEntry {
        let host = page.url.host() ?? page.url.absoluteString
        return HistoryEntry(
            id: UUID(),
            title: page.title.isEmpty ? CommandBarURL.displayForm(of: page.url) : page.title,
            subtitle: host,
            when: page.lastVisit.map { HistoryTimestamp.string(for: $0) } ?? "",
            host: page.url.host() ?? "",
            url: page.url,
            day: page.lastVisit.map { HistoryTimestamp.day(for: $0, now: now) } ?? ""
        )
    }
}
