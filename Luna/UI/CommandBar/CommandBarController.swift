//
//  CommandBarController.swift
//  Luna
//
//  §9.1's behaviour and §9.7's budget: "everything is one keystroke away", and
//  the keystroke it has to keep up with is the next one.
//
//  Local results must be on screen within one frame of the keystroke, so
//  `inputDidChange` does one thing synchronously: `CommandBarRanking.merge`
//  over arrays already in memory. Nothing on that path awaits or touches the
//  disk. The `BrowserStore` query and §3.4's suggestions (`SearchSuggestions`)
//  merge in when they land, and may not move a row the user is standing on.
//  The field is never rewritten asynchronously — §9.4's autofill runs on the
//  synchronous pass only: a row moving a frame late is survivable, the text
//  under the caret changing is not. §9.6: no networking here, which
//  `CommandBarPrivacyTests` enforces by grep.
//

import AppKit
import QuartzCore
import BrowserKit

@MainActor
final class CommandBarController: NSObject, CommandBarInputDelegate, WindowScoped {

    /// The actions `BrowserSession` has no method for yet: §9.2's app commands,
    /// which live in the app and the sidebar, and `.unarchiveTab`. Wire it where
    /// the session is built.
    var onExternalAction: ((CommandBarAction) -> Void)?

    let session: BrowserSession
    let windowID: UUID
    private let adaptive: AdaptiveHistory

    private let resultsView = CommandBarResultsView(frame: .zero)
    private var panel: CommandBarPanel?
    private var mode: CommandBarMode = .newTab
    /// The pill the open bar is standing in, if it grew out of one. Held so
    /// dismissal can give it back — see `present(_:in:from:)`.
    private var anchor: CommandBarAnchor?
    /// Watching for `CommandBarAnchor.onDoubleClick`'s second click.
    private var secondClickMonitor: Any?
    /// The second click came: the bar is folding so the anchor can be renamed.
    private var foldsForDoubleClick = false

    /// Everything local, snapshotted when the bar opens — never rebuilt per
    /// keystroke (§9.7).
    private var sources = CommandBarSources()

    /// A query that resolves after a newer one started must be dropped, not
    /// merged (§9.7).
    private var generation = 0

    /// The history search for the newest query. Cancelled when a newer one
    /// starts, which interrupts SQLite: dropping a stale answer on arrival is
    /// not enough when every keystroke's search still runs to the end, and a
    /// word typed quickly had them queued up on every reader the pool has.
    private var historyTask: Task<Void, Never>?

    /// The query whose history answer is in the list, or nil while the newest
    /// one's is still out. `BudgetTests.testCommandBarKeystroke` stops its
    /// second clock on it: an answer that changes no visible row still lands.
    private(set) var historyAnswered: String?

    /// True once the user has moved the highlight with ↓/↑. From that moment
    /// asynchronous results may only be appended (§9.7).
    private var selectionIsUserDriven = false

    /// One `AdaptiveHistory` per `BrowserStore` — see its header.
    init(session: BrowserSession, windowID: UUID, adaptive: AdaptiveHistory) {
        self.session = session
        self.windowID = windowID
        self.adaptive = adaptive
        super.init()
        resultsView.onActivate = { [weak self] result in self?.commit(result) }
        // §4.7's icons. An open tab's is in memory — it may be a page Luna
        // fetched this launch and never wrote out — and everything else comes
        // from the on-disk cache by host.
        resultsView.iconProvider = { [weak self] result in self?.favicon(for: result) }
        // The one source that never changes: §2's register is compiled in, so
        // unlike the tabs and the adaptive table it is not worth re-reading on
        // every open.
        sources.settings = SettingsSectionRegistry.commandBarEntries
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
        guard let data = session.favicons.favicon(forHost: host), let image = NSImage(data: data) else {
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
        if mode.opensNewTab { prepareNewTab() }
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
        // Hidden a turn earlier, that corner of the chrome is empty for as long
        // as the panel takes to build.
        anchor?.view.isHidden = true
        openWhenReady()
        watchForSecondClick(on: anchor)

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
    /// Two things happen between the click and a settled list, neither free:
    /// the panel's first composite (65 ms measured, see `prepareToOpen`) and
    /// the store's answer to the opening query (about 9 ms of SQLite, which
    /// cannot start until the main thread lets go of it). Opened before both
    /// have landed, the morph began on a list of open tabs alone, the history
    /// arrived halfway through, and the rows re-ranked under it.
    ///
    /// So the bar stands at the pill's size and waits for whichever comes
    /// first: the opening query landing, the first keystroke, or
    /// `openDeadline`. The deadline stops a busy store holding the bar shut,
    /// and on a warm store it never fires.
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

    /// Closes the bar: gone at once as far as the rest of the app is
    /// concerned, and on screen for the 0.18 s it takes to fold back into
    /// whatever it came out of (`CommandBarPanel.animateOut`).
    ///
    /// The keyboard goes back to the page on this line rather than at the end
    /// of the animation. A field that is still first responder while the bar
    /// is folding away is a field that eats the next keystroke, and the bar
    /// has been dismissed — what the user types next belongs to the page.
    func dismiss() {
        guard let panel else { return }
        isWaitingToOpen = false
        NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: nil)
        let window = panel.window
        self.panel = nil
        // The pill is its own again — and whatever opened for the bar's sake
        // hears about it: §3.2b's bar was held open for the typing. Both at
        // the end of the fold, so the glass closes back down onto the pill
        // instead of the two being on the same line together.
        stopWatchingForSecondClick()
        let renaming = foldsForDoubleClick
        foldsForDoubleClick = false
        if let anchor {
            self.anchor = nil
            panel.onClosed = { [weak self] in
                // Unless the bar was reopened on that same pill while this one
                // was closing, in which case the pill is spoken for and this
                // is a stale ending.
                guard self?.anchor?.view !== anchor.view else { return }
                anchor.view.isHidden = false
                anchor.onDismiss?()
                if renaming { anchor.onDoubleClick?() }
            }
        }
        // A double-click's bar goes at once. It has been open for a fraction
        // of a second, nobody was reading it, and the fold stood between the
        // second click and the rename field for the fold's whole length.
        if renaming { panel.closeAtOnce() } else { panel.animateOut() }
        generation += 1 // Orphan any query still in flight.
        historyTask?.cancel()
        historyTask = nil
        deferredRows = nil
        SearchSuggestions.shared.cancel()
        session.topHit.cancel()
        // Hand the keyboard back to the page, or the user is typing into nothing.
        // Not to a rename: the tab's name field has it, and a page given focus
        // on the way there took it straight back and ended the rename.
        if !renaming, let id = activeTabID, let content = session.webView(for: id) {
            window?.makeFirstResponder(content)
        }
    }

    @objc private func windowDidResignKey(_ notification: Notification) {
        dismiss()
    }

    // MARK: - §9.7 the query pipeline

    private func refreshSources() {
        // §9.2: the Space you are in, its archive included, and no other. The
        // Space is the cookie jar since `v7`, so a row from the Space next door
        // is a page signed in as somebody else.
        sources.tabs = session.tabsInActiveSpace(includeArchived: true)
        sources.activeSite = session.activeSite
        sources.adaptive = adaptive.snapshot
        sources.history = []
        // Not in `init` with the settings register: a shortcut can be rebound
        // and a command can stop applying — Back with nothing behind it — so
        // this one is asked again each time the bar opens.
        sources.shortcuts = BrowserCommand.commandBarEntries

        // The adaptive table is read once per Space. The bar is already usable
        // while this runs; on every open but the first in a Space it is a no-op.
        let space = activeSpaceID
        Task { [weak self] in
            await self?.adaptive.loadIfNeeded(inSpace: space)
            guard let self, self.isPresented, let field = self.panel?.field else { return }
            self.sources.adaptive = self.adaptive.snapshot
            // Only when it could change the answer. `adaptiveRows` is
            // skipped for an empty query and an empty table matches no prefix,
            // so on `⌘T` it would be a second full merge and a second trip to
            // SQLite — 9 ms of store query, measured, on the first open of
            // every session — for a list that comes back byte for byte the
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
        historyAnswered = nil
        sources.suggestions = SearchSuggestions.shared.cached(for: typed) ?? []
        let local = CommandBarRanking.merge(query: typed, sources: sources, limit: CommandBarMetrics.visibleRows)
        apply(local, appendOnly: false)
        // §9.4, synchronous pass only — see the file header.
        panel?.field.applyAutofill(CommandBarRanking.autofill(query: typed, results: local))

        historyTask?.cancel()
        historyTask = Task { [weak self] in
            guard let session = self?.session else { return }
            let hits = await session.search(typed, limit: CommandBarMetrics.historyLimit)
            // Checked on the far side of the await as well as the near one: the
            // user kept typing while SQLite was working, and this may now be an
            // answer to a question nobody is asking.
            guard let self, token == self.generation, self.panel?.field.typedText == typed else { return }
            self.sources.history = hits
            self.remerge(typed)
            self.historyAnswered = typed
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
        // the bar's own 0.18 s animation. The bar waits for the store
        // before it opens (`openWhenReady`), so what still lands in this window
        // is the slow half — the engine's suggestions, over the network.
        guard panel?.isOpening != true else {
            deferredRows = (visible, selection)
            return
        }
        resultsView.setResults(visible, selecting: selection)
        announce(count: resultsView.results.count)
        preloadTopHit()
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
            adaptive.record(typed: typed, url: url, inSpace: activeSpaceID)
        }
        // Taken before `dismiss`, which lets go of a preload nobody chose.
        let preloaded = session.topHit.take(result.url, inSpace: session.activeSpaceID)
        // Dismiss before acting: the action can move first responder, focus the
        // page or open a window, and none of that should happen underneath a
        // panel that is still on screen.
        dismiss()
        perform(result.action, preloaded: preloaded)
    }

    private func perform(_ action: CommandBarAction, preloaded: TabController? = nil) {
        switch action {
        case let .activateTab(id):
            activateTab(id)
        case let .open(url):
            // §9.1: `⌘L` and a pill both edit this tab's address; only `⌘T`
            // asks for a new one. A new tab is the only sensible answer when
            // there is no tab to edit.
            if !mode.opensNewTab, let id = activeTabID, let controller = session.controller(for: id) {
                preloaded?.hibernate()
                controller.load(url)
            } else {
                _ = session.newTab(url: url, kind: .today, adopting: preloaded)
            }
        case let .copy(answer):
            copy(answer)
        case .unarchiveTab, .command, .runCommand, .openSettings:
            onExternalAction?(action)
        }
    }

    private var currentURLText: String {
        guard let id = activeTabID, let url = session.controller(for: id)?.state.url else { return "" }
        return url.absoluteString
    }
}

// MARK: - §4's double-click, on a bar that opened on the first click

extension CommandBarController {

    /// The second half of a double-click on the anchor. It lands on the bar,
    /// which is standing where the anchor was, so it is caught here before the
    /// bar's field can take it as a word selection.
    fileprivate func watchForSecondClick(on anchor: CommandBarAnchor?) {
        guard let anchor, anchor.onDoubleClick != nil else { return }
        // Timed on the clock here rather than on the event's own timestamp,
        // which is not promised to be on the same base as any clock the app
        // can read — compared with one, it ended the watch before it began.
        let deadline = CACurrentMediaTime() + NSEvent.doubleClickInterval
        let view = anchor.view
        secondClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self, weak view] event in
            let caught = MainActor.assumeIsolated { () -> Bool in
                guard let self, let view else { return false }
                return self.foldForSecondClick(event, on: view, before: deadline)
            }
            return caught ? nil : event
        }
    }

    /// Whether `event` is that second click, and if so, the fold it starts.
    private func foldForSecondClick(_ event: NSEvent, on view: NSView, before deadline: TimeInterval) -> Bool {
        guard CACurrentMediaTime() <= deadline else {
            stopWatchingForSecondClick()
            return false
        }
        guard event.clickCount >= 2, event.window === view.window,
              view.bounds.contains(view.convert(event.locationInWindow, from: nil))
        else { return false }
        foldsForDoubleClick = true
        dismiss()
        return true
    }

    fileprivate func stopWatchingForSecondClick() {
        if let secondClickMonitor { NSEvent.removeMonitor(secondClickMonitor) }
        secondClickMonitor = nil
    }
}

// MARK: - The new tab, started before Return

extension CommandBarController {

    /// A new tab is a Return away: its web view can be starting now.
    fileprivate func prepareNewTab() {
        WebViewFactory.prepareSpare(
            dataStore: session.dataStore(forSpace: activeSpaceID),
            webExtensionController: session.extensionController(forSpace: activeSpaceID)
        )
    }

    /// Hands the session the page Return would open, when it is a site the
    /// user has been to and the field is completing its address — the one
    /// guess good enough to spend a load on (`TopHitPreload`). The loading
    /// itself is the session's: nothing in the bar touches the network.
    fileprivate func preloadTopHit() {
        guard mode.opensNewTab || activeTabID == nil,
              let top = resultsView.results.first, top.id == resultsView.selectedID,
              top.source == .history || top.source == .adaptive,
              case let .open(url) = top.action,
              let typed = panel?.field.typedText,
              CommandBarRanking.autofill(query: typed, results: [top]) != nil
        else {
            session.topHit.cancel()
            return
        }
        let page = contentRegion?().size ?? panel?.window?.contentView?.bounds.size ?? .zero
        session.topHit.want(url, inSpace: activeSpaceID, size: page, session: session)
    }
}

// MARK: - §21.1 VoiceOver, and a quick answer copied

extension CommandBarController {

    /// Return on a sum or a conversion: the answer goes on the clipboard, and
    /// the toast says so, since nothing else on screen changes.
    fileprivate func copy(_ answer: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(answer, forType: .string)
        PageToast.answerCopied(answer).show()
    }

    /// §21.1: the result count on every change, so a VoiceOver user is not left
    /// arrowing through a list whose size they have no way to know.
    fileprivate func announce(count: Int) {
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
}
