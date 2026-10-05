//
//  PageChromeController.swift
//  Luna
//
//  What `PageChromeBar` shows: which tab it is looking at, that tab's colour
//  under the bar, and whether §3.2b's setting has the bar on screen at all.
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
    /// The tab whose `onTopColour` this controller currently holds, so it can be
    /// handed back when the selection moves.
    private var listeningTo: UUID?
    /// And the controller holding it. A tab gets a new one when its page is
    /// put away and opened again, and the id alone would not notice.
    private weak var listenedController: TabController?
    private var observations: [ObservationToken] = []
    private var extensionObserver: (any NSObjectProtocol)?

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
        wireExtensions()
    }

    // MARK: - §16.4

    private func wireExtensions() {
        bar.onExtension = { [weak self] id, anchor in
            guard let self else { return }
            ExtensionsCenter.shared.perform(id, in: session, window: windowID, from: anchor)
        }
        bar.onExtensions = { [weak self] anchor in
            guard let self else { return }
            ExtensionsPopout.present(from: anchor, session: session, windowID: windowID)
        }
        extensionObserver = NotificationCenter.default.addObserver(
            forName: ExtensionsCenter.didChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshExtensions() }
        }
    }

    /// The pins for the tab on screen, in the Space on screen.
    private func refreshExtensions() {
        let center = ExtensionsCenter.shared
        bar.showsExtensions = center.serves(session)
        bar.extensionPins = center.pinnedItems(in: session, window: windowID)
        bar.layoutSubtreeIfNeeded()
        center.addShelfAnchor(bar.extensionsAnchor, forWindow: windowID)
    }

    // MARK: - §3.2b's setting

    /// Shows or hides the whole bar. Called with the layout and the placement
    /// already resolved — this does not read `Settings` itself, because the
    /// same two keys decide what the sidebar drops and one reader for both
    /// is what keeps them from disagreeing.
    /// Whether this bar is the address bar on screen — `⌘L`'s question.
    var isOnScreen: Bool { isActive }

    /// What the bar's sidebar toggle will do, for VoiceOver to say.
    func setSidebarShown(_ shown: Bool) {
        bar.setSidebarShown(shown)
    }

    /// §20.1's `⌘L`: the same hand-off a click on the pill makes.
    func beginEditing() {
        guard isActive else { return }
        bar.pill.handOff()
    }

    /// §20.2's Site Settings…: the pop-out a click on the pill's glyph opens.
    func openSiteMenu() {
        guard isActive else { return }
        bar.pill.onSiteMenu?()
    }

    func setActive(_ active: Bool, animated: Bool) {
        guard active != isActive else { return }
        isActive = active
        // The page gives up the band, or takes it back, with the bar itself.
        onBandHeight?(active ? bar.bandHeight : 0, animated)
        if active {
            bar.isHidden = false
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
        bar.show(url: state?.url ?? tab?.url)
        // §3.2c. Nil for a tab with no live web view, which is a tab that has
        // nothing to be loading.
        bar.pill.setLoad(state, for: activeTabID)
        bar.pill.showsReading = URLPillView.showsReading(for: state)
        bar.pill.isEdited = state?.isEdited ?? false
        bar.setPageColour(state?.pageBackground)
        bar.update(
            canGoBack: state?.canGoBack ?? false,
            canGoForward: state?.canGoForward ?? false,
            isLoading: state?.isLoading ?? false
        )
        refreshExtensions()
    }

    private func apply(_ id: UUID, _ state: TabState) {
        guard isActive, id == activeTabID else { return }
        // A tab's page can be made without a session change: at launch the
        // window asks for the selected tab's web view, and that builds its
        // controller after `refresh` had found none. Its first state is the
        // first news of it, and without this the bar never heard the page's
        // colour until the selection moved.
        listen(to: id)
        bar.show(url: state.url)
        bar.pill.setLoad(state, for: id)
        bar.pill.showsReading = URLPillView.showsReading(for: state)
        bar.pill.isEdited = state.isEdited
        bar.setPageColour(state.pageBackground)
        bar.update(canGoBack: state.canGoBack, canGoForward: state.canGoForward, isLoading: state.isLoading)
    }

    // MARK: - The colour under the bar

    private func listen(to id: UUID?) {
        let controller = id.flatMap { session.controller(for: $0) }
        guard id != listeningTo || controller !== listenedController else { return }
        stopListening()
        guard let id, let controller else { return }
        listeningTo = id
        listenedController = controller
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
        listenedController?.onTopColour = nil
        listenedController = nil
        listeningTo = nil
        // That colour was the other tab's. The document's own background is what
        // is left, and `refresh` sets that for whichever tab is showing now — in
        // the same turn, so nothing is ever drawn in between.
        bar.setTopColour(nil)
    }
}
