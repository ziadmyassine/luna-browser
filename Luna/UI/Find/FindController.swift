//
//  FindController.swift
//  Luna
//
//  §18.1: find in page, one per window. Which page the field searches, what
//  it searches for, and the order the searches run in; the search itself is
//  `TabController.find` (BrowserKit), and the capsule is `FindBarView`.
//
//  The field belongs to the page it was opened over. Switching tabs closes it
//  rather than carrying it across: a field kept open over a tab it never
//  searched shows a count for a page that is not on screen. The query outlives
//  it — ⌘F on the next tab, or after Escape, starts from the same words. A
//  page that changes under an open field (a link, a reload) keeps the field
//  and the query and loses the count, which belonged to the page that went;
//  Return searches the new one. Searching on arrival would scroll a page the
//  user has not looked at yet down to a match.
//
//  The query is also the Mac's find pasteboard, which every app shares, so
//  ⌘E here and ⌘G in another app agree — except in a private window, which
//  reads it and never writes it.
//

import AppKit
import BrowserKit

@MainActor
final class FindController: WindowScoped {

    let session: BrowserSession
    let windowID: UUID
    private let surface: ControlSurfaceView
    private let isPrivate: Bool
    /// `NSPasteboard(name: .find)`, but a test's own.
    var findPasteboard = NSPasteboard(name: .find)

    /// The capsule on screen, or nil while the field is closed. A fresh one
    /// each time: the old one may still be on its way up.
    private(set) var bar: FindBarView?
    var isOpen: Bool { bar != nil }
    private(set) var query = ""
    private(set) var result: FindResult?
    /// The tab the field was opened over, and its page without the fragment
    /// — a jump to an anchor is the same page.
    private var tabID: UUID?
    private var page: URL?

    /// One search at a time, in order: each moves the page's selection, which
    /// the next one starts from. Typing replaces what is waiting rather than
    /// queueing behind it; steps (Return, ⌘G) queue, so three presses are
    /// three matches.
    private struct Search {
        let query: String
        let backwards: Bool
        let fresh: Bool
    }
    private var waiting: [Search] = []
    private var running: Task<Void, Never>?
    private var observations: [ObservationToken] = []

    init(session: BrowserSession, windowID: UUID, surface: ControlSurfaceView, isPrivate: Bool) {
        self.session = session
        self.windowID = windowID
        self.surface = surface
        self.isPrivate = isPrivate
        observations = [
            session.addChangeObserver { [weak self] in self?.followSelection() },
            session.addTabStateObserver { [weak self] id, state in self?.follow(id, state) }
        ]
    }

    /// There is a page in front to search.
    var canFind: Bool {
        activeTabID.flatMap { session.controller(for: $0)?.webView } != nil
    }

    /// ⌘G has words to look for: this window's, or the ones another app last
    /// searched for.
    var hasQuery: Bool {
        !query.isEmpty || !(findPasteboard.string(forType: .string) ?? "").isEmpty
    }

    // MARK: - The commands

    /// ⌘F. Opens the field over the page in front, or, open, puts the caret
    /// back in it with the query selected so typing replaces it.
    func open(focusing: Bool = true) {
        if !isOpen {
            guard let tab = activeTabID, let controller = session.controller(for: tab), controller.webView != nil
            else { return }
            if query.isEmpty { query = findPasteboard.string(forType: .string) ?? "" }
            let bar = makeBar()
            bar.query = query
            bar.show(nil)
            bar.setPageColour(Self.colourUnder(controller))
            self.bar = bar
            tabID = tab
            page = Self.page(controller.state.url)
            surface.showFindBar(bar)
            if !query.isEmpty { search(Search(query: query, backwards: false, fresh: true)) }
        }
        if focusing { bar?.focusField(selectingAll: true) }
    }

    /// Escape, the close button, or a tab switch. The page gets the keyboard
    /// back if the field had it. The last match stays selected, as it does in
    /// every Mac find: that selection is the one mark the search left.
    func close() {
        guard let bar else { return }
        let hadFocus = bar.hasFocus
        self.bar = nil
        tabID = nil
        page = nil
        result = nil
        waiting.removeAll()
        remember(query)
        surface.hideFindBar()
        if hadFocus { focusPage() }
    }

    /// ⌘G, Return and the down chevron. With nothing to look for this is ⌘F;
    /// with the field closed it opens on the last query without taking the
    /// keyboard, so the count it lands on is there to read.
    func findNext() { step(backwards: false) }

    /// ⇧⌘G, Shift-Return and the up chevron.
    func findPrevious() { step(backwards: true) }

    /// ⌘E: `text` becomes the query, and the field shows it on the match it
    /// came from.
    func useSelection(_ text: String) {
        query = text
        remember(text)
        guard let bar else { return open(focusing: false) }
        bar.query = text
        waiting.removeAll()
        search(Search(query: text, backwards: false, fresh: true))
    }

    /// ⌘E with nothing selected in a field: the page's selection, if it has one.
    func useSelectionFromPage() {
        guard let controller = activeTabID.flatMap({ session.controller(for: $0) }) else { return }
        Task { [weak self] in
            guard let text = await controller.selectedText() else { return NSSound.beep() }
            self?.useSelection(text)
        }
    }

    // MARK: - Searching

    private func step(backwards: Bool) {
        if query.isEmpty { query = findPasteboard.string(forType: .string) ?? "" }
        guard !query.isEmpty else { return open() }
        if !isOpen { open(focusing: false) }
        guard isOpen else { return }
        remember(query)
        search(Search(query: query, backwards: backwards, fresh: false))
    }

    private func queryChanged(_ text: String) {
        query = text
        waiting.removeAll()
        guard !text.isEmpty else {
            result = nil
            bar?.show(nil)
            return
        }
        search(Search(query: text, backwards: false, fresh: true))
    }

    private func search(_ search: Search) {
        waiting.append(search)
        runNext()
    }

    private func runNext() {
        guard running == nil, !waiting.isEmpty else { return }
        let search = waiting.removeFirst()
        guard let tabID, let controller = session.controller(for: tabID), controller.webView != nil else {
            return waiting.removeAll()
        }
        running = Task { [weak self] in
            let found = await controller.find(search.query, backwards: search.backwards, fromMatchStart: search.fresh)
            self?.finish(search, with: found)
        }
    }

    private func finish(_ search: Search, with found: FindResult) {
        running = nil
        // A search for words since typed over, or for a field since closed,
        // has nothing left to say.
        if let bar, search.query == query {
            result = found
            bar.show(found)
            if !search.fresh, let text = FindBarView.countText(for: found) { announce(text, from: bar) }
        }
        runNext()
    }

    /// Stepping says where it landed; typing does not, or VoiceOver would
    /// read a count over every letter.
    private func announce(_ text: String, from bar: FindBarView) {
        NSAccessibility.post(
            element: bar, notification: .announcementRequested,
            userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.medium.rawValue]
        )
    }

    // MARK: - The page under it

    /// What the page shows under the bar, which is where the capsule sits: the
    /// bar's own rule (`PageChromeBar.refreshPlane`). The document's background
    /// alone is the wrong question on a page that paints its colour on a
    /// wrapper, a dark site over a white `body`, and put light glass on it.
    static func colourUnder(_ controller: TabController) -> NSColor? {
        (controller.topColour ?? controller.state.pageBackground).map(NSColor.init)
    }

    private func followSelection() {
        guard isOpen, activeTabID != tabID else { return }
        let hadFocus = bar?.hasFocus ?? false
        close()
        // The new tab's page is put in the window by another observer of the
        // same change, which may run after this one.
        if hadFocus { Task { @MainActor [weak self] in self?.focusPage() } }
    }

    private func follow(_ id: UUID, _ state: TabState) {
        guard let bar, id == tabID else { return }
        if let controller = session.controller(for: id) { bar.setPageColour(Self.colourUnder(controller)) }
        let now = Self.page(state.url)
        guard now != page else { return }
        page = now
        result = nil
        waiting.removeAll()
        bar.show(nil)
    }

    private func focusPage() {
        guard let webView = activeTabID.flatMap({ session.controller(for: $0)?.webView }),
              let window = surface.window, webView.window === window else { return }
        if let page = webView as? LunaWebView { page.takeFocus() } else { window.makeFirstResponder(webView) }
    }

    private static func page(_ url: URL?) -> URL? {
        guard let url, var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        parts.fragment = nil
        return parts.url ?? url
    }

    private func remember(_ text: String) {
        guard !isPrivate, !text.isEmpty, findPasteboard.string(forType: .string) != text else { return }
        findPasteboard.clearContents()
        findPasteboard.setString(text, forType: .string)
    }

    private func makeBar() -> FindBarView {
        let bar = FindBarView()
        bar.onQueryChange = { [weak self] text in self?.queryChanged(text) }
        bar.onNext = { [weak self] in self?.findNext() }
        bar.onPrevious = { [weak self] in self?.findPrevious() }
        bar.onClose = { [weak self] in self?.close() }
        return bar
    }
}
