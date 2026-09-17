//
//  CommandBarController.swift
//  Luna
//
//  §9.1's behaviour and §9.7's budget. "Everything is one keystroke away" is this
//  file's job, and the keystroke it has to keep up with is the *next* one.
//
//  **§9.7, and the shape of everything below.** Local results must be on screen
//  within one frame — 16 ms — of the keystroke. So `inputDidChange` does exactly
//  one thing synchronously: run `CommandBarRanking.merge` over arrays that are
//  already in memory (open tabs, Spaces, the adaptive table, the typed string
//  itself) and hand them to the list. Nothing on that path awaits, opens a
//  database connection, or touches the disk. The `BrowserStore` query is issued
//  as a task and merges in when it lands — and per §9.7 it is not allowed to move
//  a row the user is standing on: once ↓ or ↑ has been pressed, late results may
//  only be appended.
//
//  **The field is never rewritten asynchronously.** §9.4's autofill runs on the
//  synchronous pass only. A list row moving a frame after you stopped typing is
//  survivable; the text under your caret changing is not.
//
//  §9.6: there is no networking here. See `CommandBarModel`'s header, and
//  `CommandBarPrivacyTests`, which enforces it.
//

import AppKit
import BrowserKit

/// `⌘T` and `⌘L` (§9.1, §20.1), plus the pills that hand off to the bar.
///
/// The mode carries two separate things, and conflating them is what made the
/// New Tab page open a *second* empty tab: what the field starts with, and
/// which tab a chosen result lands in.
enum CommandBarMode: Equatable {
    /// `⌘T`: empty. Choosing a result opens a new tab.
    case newTab
    /// `⌘L`: prefilled with the current URL and selected. Choosing a result
    /// navigates the tab you are already on.
    case editCurrentURL
    /// A pill handing off to the bar — the top bar's (§4) or the New Tab page's
    /// (§30.19). Starts from whatever was typed into it, and navigates the tab
    /// you are already standing on, because that is the tab you meant to fill.
    case search(String)
}

extension CommandBarMode {

    /// Whether a chosen result opens a **new** tab or navigates the current one.
    /// This is the half of the mode that was wrong: the New Tab page's pill ran
    /// as `.newTab`, so committing left the empty page behind and opened a
    /// second tab next to it.
    var opensNewTab: Bool { self == .newTab }

    /// What the field starts with. `currentURL` is only read when the mode
    /// actually wants it.
    func prefill(currentURL: () -> String) -> String {
        switch self {
        case .newTab: ""
        case .editCurrentURL: currentURL()
        case let .search(text): text
        }
    }
}

@MainActor
final class CommandBarController: NSObject, CommandBarInputDelegate {

    /// The actions `BrowserSession` has no method for yet: §9.2's app commands,
    /// which live in the app and the sidebar, and `.unarchiveTab`. Wire it where
    /// the session is built.
    var onExternalAction: ((CommandBarAction) -> Void)?

    private let session: BrowserSession
    private let adaptive: AdaptiveHistory

    private let resultsView = CommandBarResultsView(frame: .zero)
    private var panel: CommandBarPanel?
    private var mode: CommandBarMode = .newTab

    /// Everything local, snapshotted when the bar opens — never rebuilt per
    /// keystroke (§9.7).
    private var sources = CommandBarSources()

    /// A query that resolves after a newer one started must be dropped, not
    /// merged (§9.7).
    private var generation = 0

    /// True once the user has moved the highlight with ↓/↑. From that moment
    /// asynchronous results may only be appended (§9.7).
    private var selectionIsUserDriven = false

    /// One `AdaptiveHistory` per `BrowserStore` — see its header.
    init(session: BrowserSession, adaptive: AdaptiveHistory) {
        self.session = session
        self.adaptive = adaptive
        super.init()
        resultsView.onActivate = { [weak self] result in self?.commit(result) }
    }

    var isPresented: Bool { panel != nil }

    // MARK: - §9.1 presentation

    func present(_ mode: CommandBarMode, in window: NSWindow) {
        guard let root = window.contentView else { return }
        if panel != nil { dismiss() }
        self.mode = mode
        selectionIsUserDriven = false
        refreshSources()

        let panel = CommandBarPanel(frame: root.bounds, resultsView: resultsView)
        panel.onBackgroundClick = { [weak self] in self?.dismiss() }
        panel.field.inputDelegate = self
        root.addSubview(panel, positioned: .above, relativeTo: nil)
        self.panel = panel

        // Before `begin`: the selected-suffix machinery needs the field editor,
        // which only exists once the field is first responder.
        window.makeFirstResponder(panel.field)
        let prefill = mode.prefill { self.currentURLText }
        panel.field.begin(
            with: prefill,
            placeholder: mode == .editCurrentURL ? "Edit address" : "Search or enter address",
            selectAll: true
        )

        runQuery(prefill)
        panel.animateIn()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidResignKey),
            name: NSWindow.didResignKeyNotification,
            object: window
        )
    }

    func dismiss() {
        guard let panel else { return }
        NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: nil)
        let window = panel.window
        panel.removeFromSuperview()
        self.panel = nil
        generation += 1 // Orphan any query still in flight.
        // Hand the keyboard back to the page, or the user is typing into nothing.
        if let id = session.activeTabID, let content = session.webView(for: id) {
            window?.makeFirstResponder(content)
        }
    }

    @objc private func windowDidResignKey(_ notification: Notification) {
        dismiss()
    }

    // MARK: - §9.7 the query pipeline

    private func refreshSources() {
        // §9.2: every Space plus the archive, not just the active Space.
        sources.tabs = session.allTabs(includeArchived: true)
        sources.spaces = Dictionary(uniqueKeysWithValues: session.spaces.map { ($0.id, $0) })
        sources.adaptive = adaptive.snapshot
        sources.history = []

        // The adaptive table is read once per launch. The bar is already usable
        // while this runs; on every open but the first it is a no-op.
        Task { [weak self] in
            await self?.adaptive.loadIfNeeded()
            guard let self, self.isPresented, let field = self.panel?.field else { return }
            self.sources.adaptive = self.adaptive.snapshot
            self.runQuery(field.typedText)
        }
    }

    /// The whole of §9.7's synchronous half. No `await`, no I/O.
    func inputDidChange(_ typed: String) {
        selectionIsUserDriven = false
        runQuery(typed)
    }

    private func runQuery(_ typed: String) {
        generation += 1
        let token = generation

        sources.history = []
        let local = CommandBarRanking.merge(query: typed, sources: sources, limit: CommandBarMetrics.visibleRows)
        apply(local, appendOnly: false)
        // §9.4, synchronous pass only — see the file header.
        panel?.field.applyAutofill(CommandBarRanking.autofill(query: typed, results: local))

        Task { [weak self] in
            guard let session = self?.session else { return }
            let hits = await session.search(typed, limit: CommandBarMetrics.historyLimit)
            // Checked on the far side of the await as well as the near one: the
            // user kept typing while SQLite was working, and this may now be an
            // answer to a question nobody is asking.
            guard let self, token == self.generation, self.panel?.field.typedText == typed else { return }
            self.sources.history = hits
            self.apply(
                CommandBarRanking.merge(query: typed, sources: self.sources, limit: CommandBarMetrics.visibleRows),
                appendOnly: self.selectionIsUserDriven
            )
        }
    }

    private func apply(_ new: [CommandBarResult], appendOnly: Bool) {
        let rows: [CommandBarResult]
        let selection: String?
        if appendOnly {
            rows = CommandBarRanking.appendingWithoutReordering(onScreen: resultsView.results, incoming: new)
            selection = resultsView.selectedID
        } else {
            rows = new
            selection = new.first?.id
        }
        resultsView.setResults(Array(rows.prefix(CommandBarMetrics.visibleRows)), selecting: selection)
        announce(count: resultsView.results.count)
    }

    /// §21.1: the result count on every change, so a VoiceOver user is not left
    /// arrowing through a list whose size they have no way to know.
    private func announce(count: Int) {
        guard let body = panel?.body else { return }
        NSAccessibility.post(
            element: body,
            notification: .announcementRequested,
            userInfo: [
                .announcement: count == 1 ? "1 result" : "\(count) results",
                .priority: NSAccessibilityPriorityLevel.medium.rawValue
            ]
        )
    }

    // MARK: - Keyboard

    func inputDidMoveSelection(by offset: Int) {
        guard !resultsView.results.isEmpty else { return }
        selectionIsUserDriven = true
        let ids = resultsView.results.map(\.id)
        let current = resultsView.selectedID.flatMap(ids.firstIndex(of:)) ?? 0
        // Clamped, not wrapped: ↓ at the bottom should feel like a wall, not
        // teleport the highlight back to the top of a list you just read.
        resultsView.select(id: ids[min(max(current + offset, 0), ids.count - 1)])
        if let body = panel?.body {
            NSAccessibility.post(element: body, notification: .selectedChildrenChanged)
        }
    }

    func inputDidCancel() {
        dismiss()
    }

    func inputDidCommit() {
        guard let result = resultsView.selectedResult else { return }
        commit(result)
    }

    // MARK: - Acting

    private func commit(_ result: CommandBarResult) {
        // §9.3: the lesson is keyed on what the user *typed*, never on the string
        // autofill completed for them — otherwise the ranker teaches itself.
        if let url = result.url, let typed = panel?.field.typedText {
            adaptive.record(typed: typed, url: url)
        }
        // Dismiss before acting: the action can move first responder, focus the
        // page or open a window, and none of that should happen underneath a
        // panel that is still on screen.
        dismiss()
        perform(result.action)
    }

    private func perform(_ action: CommandBarAction) {
        switch action {
        case let .activateTab(id):
            session.activateTab(id)
        case let .open(url):
            // §9.1: `⌘L` and a pill both edit *this* tab's address; only `⌘T`
            // asks for a new one. A new tab is the only sensible answer when
            // there is no tab to edit.
            if mode.opensNewTab {
                _ = session.newTab(url: url, kind: .today)
            } else if let id = session.activeTabID, let controller = session.controller(for: id) {
                controller.load(url)
            } else {
                _ = session.newTab(url: url, kind: .today)
            }
        case .unarchiveTab, .command:
            onExternalAction?(action)
        }
    }

    private var currentURLText: String {
        guard let id = session.activeTabID, let url = session.controller(for: id)?.state.url else { return "" }
        return url.absoluteString
    }
}
