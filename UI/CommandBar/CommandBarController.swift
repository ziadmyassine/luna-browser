//
//  CommandBarController.swift
//  Luna
//
//  §9.1's behaviour and §9.7's budget. "Everything is one keystroke away" is this
//  file's job, and the keystroke it has to keep up with is the next one.
//
//  §9.7, and the shape of everything below. Local results must be on screen
//  within one frame — 16 ms — of the keystroke. So `inputDidChange` does exactly
//  one thing synchronously: run `CommandBarRanking.merge` over arrays that are
//  already in memory (open tabs, Spaces, the adaptive table, the typed string
//  itself) and hand them to the list. Nothing on that path awaits, opens a
//  database connection, or touches the disk. The `BrowserStore` query is issued
//  as a task and merges in when it lands — and per §9.7 it is not allowed to move
//  a row the user is standing on: once ↓ or ↑ has been pressed, late results may
//  only be appended.
//
//  The field is never rewritten asynchronously. §9.4's autofill runs on the
//  synchronous pass only. A list row moving a frame after you stopped typing is
//  survivable; the text under your caret changing is not.
//
//  §9.6: there is no networking here, and `CommandBarPrivacyTests` enforces
//  that by grep. §3.4's suggestions are fetched by `SearchSuggestions` over in
//  `Features/Search` and arrive as a plain `[String]` — a third pass over the
//  same merge, after the synchronous one and the history one, under exactly the
//  same rule: it may not move a row the user is standing on.
//

import AppKit
import BrowserKit

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
    /// The pill the open bar is standing in, if it grew out of one. Held so
    /// dismissal can give it back — see `present(_:in:from:)`.
    private var anchor: CommandBarAnchor?

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
        // §4.7's icons. An open tab's is in memory — it may be a page Luna
        // fetched this launch and never wrote out — and everything else comes
        // from the on-disk cache by host.
        resultsView.iconProvider = { [weak self] result in self?.favicon(for: result) }
    }

    var isPresented: Bool { panel != nil }

    /// One decoded icon per host, for the life of the window. §9.7 is a
    /// per-keystroke budget and the list is rebuilt on every one of them, so
    /// without this eight rows cost eight cache lookups and eight
    /// `NSImage(data:)` decodes per character typed — on the main thread,
    /// inside the 16 ms the local results are supposed to land in.
    private var icons: [String: NSImage] = [:]

    private func favicon(for result: CommandBarResult) -> NSImage? {
        if case let .activateTab(id) = result.action, let image = session.favicon(for: id) {
            return image
        }
        guard let host = result.url?.host() else { return nil }
        if let cached = icons[host] { return cached }
        guard let data = FaviconService.shared.favicon(forHost: host), let image = NSImage(data: data) else {
            return nil
        }
        icons[host] = image
        return image
    }

    /// Where the page is inside the window, so §9.1's panel sits over the page
    /// rather than over the window. Set by the assembly seam; without it the
    /// bar falls back to centring on the window.
    var contentRegion: (() -> NSRect)?

    // MARK: - §9.1 presentation

    /// - Parameter anchor: the address pill the bar should grow out of (§3.2,
    ///   §3.2b), or nil for `⌘T`'s panel over the page.
    ///
    ///   The pill goes away for the duration. The bar stands exactly where
    ///   it was, at its width and its corner, showing what it was showing — so
    ///   leaving the pill underneath would be the address drawn twice on the
    ///   same 34 pt, once behind glass.
    func present(_ mode: CommandBarMode, in window: NSWindow, from anchor: CommandBarAnchor? = nil) {
        guard let root = window.contentView else { return }
        if panel != nil { dismiss() }
        self.mode = mode
        self.anchor = anchor
        selectionIsUserDriven = false
        refreshSources()

        let panel = CommandBarPanel(frame: root.bounds, resultsView: resultsView, anchor: anchor)
        panel.contentRegion = contentRegion
        panel.onBackgroundClick = { [weak self] in self?.dismiss() }
        panel.onOpened = { [weak self] in self?.showDeferredRows() }
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
        panel.prepareToOpen()
        // In the same turn as `prepareToOpen`, so it is the same commit.
        // The pill going and the bar arriving are one swap at one corner: the
        // screen holds the frame it has until the panel is drawn, and what it
        // draws next is the same capsule in the same place with a caret in it.
        // Hidden a turn earlier — which is where it used to be — that corner
        // of the chrome is empty for as long as the panel takes to build.
        anchor?.view.isHidden = true
        openWhenReady()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidResignKey),
            name: NSWindow.didResignKeyNotification,
            object: window
        )
    }

    /// True between `prepareToOpen` and the moment the bar actually opens —
    /// see `openWhenReady`. The bar is standing at the pill's size for all of
    /// it, so there is nothing to see while it lasts.
    private var isWaitingToOpen = false

    /// The bar opens once, with the list it is going to have.
    ///
    /// Two things happen between the click and a settled list, and neither is
    /// free: the panel's first composite (65 ms, measured — see
    /// `prepareToOpen`) and the store's answer to the opening query (about 9 ms
    /// of SQLite, which cannot start until the main thread lets go of it).
    /// Opening before both have landed is the reported defect: the morph
    /// began on a list built from open tabs alone, the history arrived halfway
    /// through, and the rows re-ranked under it.
    ///
    /// So the bar stands at the pill's own size and waits for whichever comes
    /// first: the opening query landing, the first keystroke, or
    /// `openDeadline`. The deadline is the honest half — a store that is busy
    /// must not be able to hold the bar shut — and on a warm store, where the
    /// query lands about 6 ms after the panel is drawn, it never fires.
    private func openWhenReady() {
        isWaitingToOpen = true
        DispatchQueue.main.asyncAfter(deadline: .now() + CommandBarMetrics.openDeadline) { [weak self] in
            self?.openBar()
        }
    }

    /// Opens it, at most once per presentation.
    private func openBar() {
        guard isWaitingToOpen, let panel else { return }
        isWaitingToOpen = false
        panel.animateIn()
    }

    func dismiss() {
        guard let panel else { return }
        isWaitingToOpen = false
        NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: nil)
        let window = panel.window
        panel.removeFromSuperview()
        self.panel = nil
        // The pill is its own again — and whatever opened for the bar's sake
        // hears about it: §3.2b's bar was held open for the typing.
        if let anchor {
            anchor.view.isHidden = false
            self.anchor = nil
            anchor.onDismiss?()
        }
        generation += 1 // Orphan any query still in flight.
        deferredRows = nil
        SearchSuggestions.shared.cancel()
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
        // §9 / D-S8: a row from another Space has to say whose cookies it is,
        // and the Space colour does not. Without this the rows still stay apart
        // per Profile — `CommandBarRanking` derives that from `Space.profileID`
        // — but they lose the Profile's name off their badge.
        sources.profiles = session.profiles
        sources.adaptive = adaptive.snapshot
        sources.history = []

        // The adaptive table is read once per launch. The bar is already usable
        // while this runs; on every open but the first it is a no-op.
        Task { [weak self] in
            await self?.adaptive.loadIfNeeded()
            guard let self, self.isPresented, let field = self.panel?.field else { return }
            self.sources.adaptive = self.adaptive.snapshot
            // Only when it could change the answer. `adaptiveRows` is
            // skipped for an empty query and an empty table matches no prefix,
            // so on `⌘T` this was a second full merge and a second trip to
            // SQLite — 9 ms of store query, measured, on the first open of
            // every session — for a list that came back byte for byte the
            // same, in the middle of opening the bar.
            guard !self.adaptive.snapshot.isEmpty, !field.typedText.isEmpty else { return }
            self.runQuery(field.typedText)
        }
    }

    /// The whole of §9.7's synchronous half. No `await`, no I/O.
    func inputDidChange(_ typed: String) {
        selectionIsUserDriven = false
        runQuery(typed)
        // Somebody typed into a bar that has not finished opening. Whatever
        // `openWhenReady` was waiting for, it is answering a question the user
        // has already moved past.
        openBar()
    }

    private func runQuery(_ typed: String) {
        generation += 1
        let token = generation

        // §9.1's mark, before the ranking: what the string is does not depend
        // on what the search finds, and the glyph should not wait on SQLite.
        panel?.showMark(for: typed)

        sources.history = []
        sources.suggestions = SearchSuggestions.shared.cached(for: typed) ?? []
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
            self.remerge(typed)
            // The list the bar will open with is now complete.
            self.openBar()
        }

        // §3.4. Nothing is asked for while the query still reads as an address:
        // a half-typed hostname is not a search, and sending it would be sending
        // a site the user is about to visit to an engine they did not ask.
        guard CommandBarURL.direct(from: typed) == nil else {
            SearchSuggestions.shared.cancel()
            return
        }
        SearchSuggestions.shared.request(typed) { [weak self] phrases in
            guard let self, token == self.generation, self.panel?.field.typedText == typed else { return }
            self.sources.suggestions = phrases
            self.remerge(typed)
        }
    }

    /// A later source has landed. Same merge, same §9.7 rule.
    private func remerge(_ typed: String) {
        apply(
            CommandBarRanking.merge(query: typed, sources: sources, limit: CommandBarMetrics.visibleRows),
            appendOnly: selectionIsUserDriven
        )
    }

    /// Results that landed while the bar was opening, shown the moment it has.
    private var deferredRows: ([CommandBarResult], String?)?

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
        let visible = Array(rows.prefix(CommandBarMetrics.visibleRows))
        // Not while the bar is opening. Replacing the list rebuilds eight
        // row views and re-draws them under live glass, on the thread running
        // the bar's own 0.18 s animation. The bar now waits for the store
        // before it opens (`openWhenReady`), so what still lands in this window
        // is the slow half — the engine's suggestions, over the network.
        guard panel?.isOpening != true else {
            deferredRows = (visible, selection)
            return
        }
        resultsView.setResults(visible, selecting: selection)
        announce(count: resultsView.results.count)
    }

    /// The bar has opened: add whatever landed while it was opening, without
    /// moving what is already there.
    ///
    /// §9.7's no-reorder rule is written for the user's cursor, and this is the
    /// same rule one step earlier: a list that re-ranks itself the instant the
    /// bar settles is a list nobody can read, whether or not a highlight has
    /// been moved yet. The rows the bar opened with keep their places; a late
    /// arrival takes the first free one, and takes none at all when the list is
    /// already full. The next keystroke re-ranks everything anyway.
    private func showDeferredRows() {
        guard let (rows, _) = deferredRows else { return }
        deferredRows = nil
        apply(rows, appendOnly: true)
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
        // §9.3: the lesson is keyed on what the user typed, never on the string
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
            // §9.1: `⌘L` and a pill both edit this tab's address; only `⌘T`
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
