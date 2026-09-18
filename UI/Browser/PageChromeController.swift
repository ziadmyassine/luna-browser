//
//  PageChromeController.swift
//  Luna
//
//  What `PageChromeBar` shows, and when it is open.
//
//  The view is the two states; this is everything that decides between them —
//  which tab it is looking at, where that tab's page has scrolled to, and
//  whether §3.2b's setting has the bar on screen at all.
//
//  The rule that decides between the two states is `PageBarScroll`, which is a
//  value with no view in it so it can be asserted rather than eyeballed. This
//  file is what feeds it and what it drives.
//

import AppKit
import BrowserKit

@MainActor
final class PageChromeController {

    /// The bar's sidebar toggle — the one control that brings a hidden sidebar
    /// back when the pill is not in it.
    var onToggleSidebar: (() -> Void)?
    /// Text committed in the pill, for the same URL-or-query parse the
    /// sidebar's pill commits through (§9.2).
    var onSubmitURL: ((String) -> Void)?

    var view: NSView { bar }

    private let session: BrowserSession
    private let bar = PageChromeBar()
    private var isActive = false
    /// The tab whose `onScroll` this controller currently holds, so it can be
    /// handed back when the selection moves.
    private var listeningTo: UUID?
    private var shownURL: URL?
    private var scroll = PageBarScroll()
    private var observations: [ObservationToken] = []

    init(session: BrowserSession) {
        self.session = session
        bar.isHidden = true
        bar.onToggleSidebar = { [weak self] in self?.onToggleSidebar?() }
        bar.onSubmitURL = { [weak self] text in self?.onSubmitURL?(text) }
        bar.onTyping = { [weak self] text in self?.suggest(text) }
        bar.onBack = { [weak self] in self?.session.goBack() }
        bar.onReloadOrStop = { [weak self] isLoading in
            guard let self else { return }
            if isLoading { session.stop() } else { session.reload() }
        }
        // Registered, not assigned: the sidebar and the top bar are both already
        // on these, and a `var` closure is last-writer-wins.
        observations = [
            session.addChangeObserver { [weak self] in self?.refresh() },
            session.addTabStateObserver { [weak self] id, state in self?.apply(id, state) }
        ]
    }

    // MARK: - §3.2b's setting

    /// Shows or hides the whole bar. Called with the layout and the placement
    /// already resolved — this does not read `Settings` itself, because the
    /// same two keys decide what the *sidebar* drops and one reader for both
    /// is what keeps them from disagreeing.
    func setActive(_ active: Bool, animated: Bool) {
        guard active != isActive else { return }
        isActive = active
        if active {
            bar.isHidden = false
            // Forget whatever the last page had scrolled to: the bar comes back
            // open, and `refresh` reinstates it from the tab that is showing now.
            shownURL = nil
            refresh()
        } else {
            stopListening()
        }
        guard animated else {
            Tokens.Motion.immediately { bar.alphaValue = active ? 1 : 0 }
            bar.isHidden = !active
            return
        }
        Tokens.Motion.animate(Tokens.Motion.layoutSwitch) { _ in
            self.bar.animator().alphaValue = active ? 1 : 0
        } completion: { [bar] in
            MainActor.assumeIsolated { if bar.alphaValue == 0 { bar.isHidden = true } }
        }
    }

    // MARK: - The session

    private func refresh() {
        guard isActive else { return }
        listen(to: session.activeTabID)
        let tab = session.tabs.first { $0.id == session.activeTabID }
        let state = session.activeTabID.flatMap { session.controller(for: $0)?.state }
        show(url: state?.url ?? tab?.url)
        bar.setPageColour(state?.pageBackground)
        bar.update(canGoBack: state?.canGoBack ?? false, isLoading: state?.isLoading ?? false)
    }

    private func apply(_ id: UUID, _ state: TabState) {
        guard isActive, id == session.activeTabID else { return }
        show(url: state.url)
        bar.setPageColour(state.pageBackground)
        bar.update(canGoBack: state.canGoBack, isLoading: state.isLoading)
    }

    /// A new address opens the bar, whatever the last page had scrolled to.
    /// Arriving somewhere is exactly the moment the address is worth showing,
    /// and the page underneath is at its own top.
    private func show(url: URL?) {
        bar.show(url: url)
        guard url != shownURL else { return }
        shownURL = url
        scroll.reset()
        bar.setCollapsed(false, animated: false)
    }

    // MARK: - §3.4's completions

    /// Asks the engine for what is being typed in the pill.
    ///
    /// **`SearchSuggestions` and nothing else**, which is the object that owns
    /// the one network call in the query path and says what leaves the Mac. The
    /// debounce, the cache and the cancellation are all its; this only hands
    /// over the query and hands back the answer, and drops an answer that
    /// arrives after the user has moved on.
    private func suggest(_ text: String) {
        let typed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty, CommandBarURL.direct(from: typed) == nil else {
            SearchSuggestions.shared.cancel()
            bar.showSuggestions([])
            return
        }
        if let cached = SearchSuggestions.shared.cached(for: typed) { bar.showSuggestions(cached) }
        SearchSuggestions.shared.request(typed) { [weak self] phrases in
            self?.bar.showSuggestions(phrases)
        }
    }

    // MARK: - Scroll

    private func listen(to id: UUID?) {
        guard id != listeningTo else { return }
        stopListening()
        guard let id, let controller = session.controller(for: id) else { return }
        listeningTo = id
        controller.onScroll = { [weak self] offset in self?.pageScrolled(to: offset) }
    }

    /// Hands the closure back. The engine holds it strongly, and it captures
    /// `self` weakly — so a controller that went away without this would leave
    /// a live page posting into nothing, once per frame of every scroll.
    private func stopListening() {
        if let listeningTo { session.controller(for: listeningTo)?.onScroll = nil }
        listeningTo = nil
    }

    /// One animation per state change, not one per frame — see
    /// `PageBarScroll.page(movedTo:)`, which is the whole of the rule.
    private func pageScrolled(to offset: Double) {
        guard isActive, scroll.page(movedTo: offset) else { return }
        bar.setCollapsed(scroll.isCollapsed, animated: true)
    }
}
