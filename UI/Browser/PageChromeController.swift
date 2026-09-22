//
//  PageChromeController.swift
//  Luna
//
//  What `PageChromeBar` shows, and when it is open.
//
//  The view is the two states; this is everything that decides between them:
//  which tab it is looking at, where that tab's page has scrolled to, and
//  whether §3.2b's setting has the bar on screen at all. The rule itself is
//  `PageBarScroll`, a value with no view in it so it can be asserted rather
//  than eyeballed.
//

import AppKit
import BrowserKit

@MainActor
final class PageChromeController: WindowScoped {

    /// The bar's sidebar toggle — the one control that brings a hidden sidebar
    /// back when the pill is not in it.
    var onToggleSidebar: (() -> Void)?
    /// How far the page has to start down the pane. Zero whenever the bar is
    /// not the address bar on screen.
    var onBandHeight: ((_ height: CGFloat, _ animated: Bool) -> Void)?

    var view: NSView { bar }

    let session: BrowserSession
    let windowID: UUID
    private let bar = PageChromeBar()
    private var isActive = false
    /// The tab whose `onScroll` this controller currently holds, so it can be
    /// handed back when the selection moves.
    private var listeningTo: UUID?
    private var shownURL: URL?
    /// Whether the tab was loading last time it was heard from, so that a load
    /// starting can be told from a load going on.
    private var wasLoading = false
    /// §9.1 is standing on the pill. The bar is held open for the whole of it —
    /// the collapse rule keeps running underneath, it just does not get the bar
    /// until the user is finished.
    private var isEditing = false
    private var scroll = PageBarScroll()
    private var observations: [ObservationToken] = []

    init(session: BrowserSession, windowID: UUID) {
        self.session = session
        self.windowID = windowID
        bar.isHidden = true
        bar.onToggleSidebar = { [weak self] in self?.onToggleSidebar?() }
        // §3.2b's pill hands the address over to §9.1, which opens standing on
        // the pill rather than in the middle of the page (`CommandBarAnchor`).
        bar.onHandOff = { [weak self] anchor in
            self?.presentCommandBar?(.editCurrentURL, anchor)
        }
        bar.onBandHeight = { [weak self] height, animated in
            guard let self, isActive else { return }
            onBandHeight?(height, animated)
        }
        bar.onEditingBegan = { [weak self] in self?.isEditing = true }
        bar.onEditingEnded = { [weak self] in self?.editingEnded() }
        bar.onBack = { [weak self] in self?.session.goBack() }
        bar.onForward = { [weak self] in self?.session.goForward() }
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
    /// same two keys decide what the sidebar drops and one reader for both
    /// is what keeps them from disagreeing.
    /// Whether this bar is the address bar on screen — `⌘L`'s question.
    var isOnScreen: Bool { isActive }

    /// §20.1's `⌘L`: the same hand-off a click on the pill makes.
    func beginEditing() {
        guard isActive else { return }
        bar.pill.handOff()
    }

    func setActive(_ active: Bool, animated: Bool) {
        guard active != isActive else { return }
        isActive = active
        // Whatever was being typed went with the bar.
        isEditing = false
        // The page gives up the band, or takes it back, with the bar itself.
        onBandHeight?(active ? bar.bandHeight : 0, animated)
        if active {
            bar.isHidden = false
            // Forget whatever the last page had scrolled to: the bar comes back
            // open, and `refresh` reinstates it from the tab that is showing now.
            shownURL = nil
            wasLoading = false
            refresh()
        } else {
            stopListening()
            // §3.2c: the bar is leaving, so the line goes with it rather than
            // finishing a load the user cannot see the address of.
            bar.pill.setLoad(nil, for: nil)
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
        listen(to: activeTabID)
        let tab = windowTabs.first { $0.id == activeTabID }
        let state = activeTabID.flatMap { session.controller(for: $0)?.state }
        show(url: state?.url ?? tab?.url, isLoading: state?.isLoading ?? false)
        // §3.2c. Nil for a tab with no live web view, which is a tab that has
        // nothing to be loading.
        bar.pill.setLoad(state, for: activeTabID)
        bar.setPageColour(state?.pageBackground)
        bar.update(
            canGoBack: state?.canGoBack ?? false,
            canGoForward: state?.canGoForward ?? false,
            isLoading: state?.isLoading ?? false
        )
    }

    private func apply(_ id: UUID, _ state: TabState) {
        guard isActive, id == activeTabID else { return }
        show(url: state.url, isLoading: state.isLoading)
        bar.pill.setLoad(state, for: id)
        bar.setPageColour(state.pageBackground)
        bar.update(canGoBack: state.canGoBack, canGoForward: state.canGoForward, isLoading: state.isLoading)
    }

    /// Arriving anywhere opens the bar, whatever the last page had scrolled
    /// to: that is the moment the address is worth showing, and it is also the
    /// moment the page under it is about to be replaced.
    ///
    /// A new address is one way in. A load starting is the other, and it is
    /// needed as well — a reload, a form post and a same-address navigation all
    /// leave the URL exactly where it was, and every one of them is an arrival.
    private func show(url: URL?, isLoading: Bool) {
        bar.show(url: url)
        defer { wasLoading = isLoading }
        guard url != shownURL || (isLoading && !wasLoading) else { return }
        shownURL = url
        scroll.reset()
        bar.setCollapsed(false, animated: false)
    }

    // MARK: - Scroll

    private func listen(to id: UUID?) {
        guard id != listeningTo else { return }
        stopListening()
        guard let id, let controller = session.controller(for: id) else { return }
        listeningTo = id
        controller.onScroll = { [weak self] offset in self?.pageScrolled(to: offset) }
        controller.onTopColour = { [weak self] colour in self?.bar.setTopColour(colour) }
        // Taken rather than waited for: this tab is already scrolled to wherever
        // it was left, and the bar should wear that on the frame it appears on
        // rather than on the user's next drag.
        bar.setTopColour(controller.topColour)
    }

    /// Hands the closure back. The engine holds it strongly, and it captures
    /// `self` weakly — so a controller that went away without this would leave
    /// a live page posting into nothing, once per frame of every scroll.
    private func stopListening() {
        if let listeningTo, let controller = session.controller(for: listeningTo) {
            controller.onScroll = nil
            controller.onTopColour = nil
        }
        listeningTo = nil
        // That colour was the other tab's. The document's own background is what
        // is left, and `refresh` sets that for whichever tab is showing now — in
        // the same turn, so nothing is ever drawn in between.
        bar.setTopColour(nil)
    }

    /// One animation per state change, not one per frame — see
    /// `PageBarScroll.page(movedTo:)`, which is the whole of the rule.
    ///
    /// The rule is asked either way, so a page scrolled while the pill is open
    /// is not forgotten: it is what the bar is handed back to the moment the
    /// editing ends.
    private func pageScrolled(to offset: Double) {
        guard isActive, scroll.page(movedTo: offset), !isEditing else { return }
        bar.setCollapsed(scroll.isCollapsed, animated: true)
    }

    /// The bar goes back to whatever the page had it at.
    ///
    /// A committed address is not a special case any more: §9.1 navigates the
    /// tab itself, and the arrival opens the bar again through `show(url:)` on
    /// the same turn — so there is no window in which this could collapse the
    /// bar and be undone a frame later.
    private func editingEnded() {
        isEditing = false
        guard isActive else { return }
        bar.setCollapsed(scroll.isCollapsed, animated: true)
    }
}
