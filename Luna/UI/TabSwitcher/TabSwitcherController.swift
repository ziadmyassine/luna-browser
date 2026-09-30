//
//  TabSwitcherController.swift
//  Luna
//
//  `⌃⇥`: hold `⌃`, press `⇥` to move through the tabs you have been using,
//  let go to go there. `⌃⇧⇥` moves back, Escape stays where you were.
//
//  One per window. The keystrokes arrive from the app's event monitor
//  (`AppDelegate+TabSwitcher.swift`), already read into `TabSwitcherKey`s.
//
//  The panel waits `revealDelay` before it appears, so a quick `⌃⇥` flicks to
//  the last tab without anything flashing up. The order is fixed when the
//  switch starts: the list does not re-rank under a held key.
//

import AppKit
import BrowserKit
import WebKit

@MainActor
final class TabSwitcherController: NSObject, WindowScoped {

    let session: BrowserSession
    let windowID: UUID

    /// The tabs being switched between, fixed when `⌃⇥` went down. Empty
    /// whenever no switch is under way.
    private var order: [UUID] = []
    private var index = 0
    private var view: TabSwitcherView?
    private var panel: NSPanel?
    private weak var window: NSWindow?
    /// Watches for a click outside the panel while it is up.
    private var clickMonitor: Any?
    /// Bumped whenever a switch ends, so a reveal or a picture that arrives
    /// late for an old one is dropped.
    private var generation = 0

    init(session: BrowserSession, windowID: UUID) {
        self.session = session
        self.windowID = windowID
        super.init()
    }

    /// True from `⌃⇥` until the switch ends, whether or not the panel has
    /// appeared yet.
    var isEngaged: Bool { !order.isEmpty }

    /// Whether the panel has appeared. A quick tap ends before it does.
    var isShowing: Bool { panel != nil }

    /// - Returns: whether the key was the switcher's to take.
    @discardableResult
    func handle(_ key: TabSwitcherKey, in window: NSWindow) -> Bool {
        switch key {
        case .forward, .backward:
            let offset = key == .forward ? 1 : -1
            guard isEngaged else { return engage(stepping: offset, in: window) }
            move(by: offset)
            // A second press is someone looking for a tab, not flicking back
            // to the last one, so the panel does not wait any longer.
            reveal()
            return true
        case .up, .down:
            guard isEngaged else { return false }
            if let view {
                index = view.grid.vertical(from: index, down: key == .down, count: order.count)
                view.select(index)
                announce()
            }
            return true
        case .commit:
            guard isEngaged else { return false }
            commit()
            return true
        case .cancel:
            guard isEngaged else { return false }
            end()
            return true
        case .swallow:
            return isEngaged
        }
    }

    /// Stops a switch without going anywhere. The window's close path calls it.
    func cancel() {
        guard isEngaged else { return }
        end()
    }

    // MARK: - A switch

    private func engage(stepping offset: Int, in window: NSWindow) -> Bool {
        let order = TabSwitcherOrder.tabs(
            windowTabs,
            recent: session.recentTabs,
            live: Set(session.controllers.compactMap { $0.value.webView == nil ? nil : $0.key }),
            active: activeTabID
        )
        guard !order.isEmpty else { return false }
        self.order = order
        self.window = window
        index = TabSwitcherOrder.step(from: 0, by: offset, count: order.count)
        generation += 1
        let started = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + TabSwitcherMetrics.revealDelay) { [weak self] in
            guard let self, self.generation == started else { return }
            self.reveal()
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidResignKey),
            name: NSWindow.didResignKeyNotification,
            object: window
        )
        return true
    }

    private func move(by offset: Int) {
        index = TabSwitcherOrder.step(from: index, by: offset, count: order.count)
        view?.select(index)
        announce()
    }

    private func commit() {
        let chosen = order[index]
        end()
        if chosen != activeTabID { activateTab(chosen) }
    }

    private func end() {
        generation += 1
        order = []
        NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: nil)
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
        view = nil
        if let panel {
            self.panel = nil
            // Out the way it came in — see `Motion.fadePanelOut`.
            Tokens.Motion.fadePanelOut(panel)
        }
    }

    /// Another window or app took the keyboard, and with it the `⌃` release
    /// this switch was waiting for.
    @objc private func windowDidResignKey(_ notification: Notification) {
        cancel()
    }

    // MARK: - The panel

    private func reveal() {
        guard isEngaged, panel == nil, let window else { return }
        let view = TabSwitcherView(items: order.map(item))
        view.onPick = { [weak self] picked in
            guard let self, self.order.indices.contains(picked) else { return }
            self.index = picked
            self.commit()
        }
        view.select(index)
        let panel = TabSwitcherView.panel(holding: view, over: window)
        panel.alphaValue = 0
        window.addChildWindow(panel, ordered: .above)
        panel.orderFront(nil)
        self.view = view
        self.panel = panel
        // §6's `popoverIn`, the fade every panel over the page arrives on.
        // Instant under Reduce Motion, which `animate` checks.
        Tokens.Motion.animate(Tokens.Motion.popoverIn) { _ in
            panel.animator().alphaValue = 1
        }
        installClickMonitor()
        loadPictures()
        announce()
    }

    /// A click anywhere but the panel is "never mind", as a click beside
    /// every panel in Luna is. It still lands where it was aimed.
    private func installClickMonitor() {
        clickMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            guard let self, let panel = self.panel, event.window !== panel else { return event }
            self.cancel()
            return event
        }
    }

    private func item(for id: UUID) -> TabSwitcherItem {
        let tab = session.tab(id)
        // §3.4a's order: a name the user gave the tab, then the page's live
        // title, then the stored one, then the host for a page with none.
        let live = session.controller(for: id)?.state.title ?? ""
        let page = live.isEmpty ? (tab?.title ?? "") : live
        let named = tab?.customTitle ?? page
        let title = named.isEmpty ? (tab?.url.host() ?? tab?.url.absoluteString ?? "") : named
        return TabSwitcherItem(id: id, title: title, favicon: session.favicon(for: id))
    }

    /// A fresh picture of every tab with a page loaded, and §6.8's stored one
    /// for the rest. Taken now rather than read from disk where possible: the
    /// stored picture is from when the tab was last left, and the tab you are
    /// on has none at all.
    private func loadPictures() {
        let started = generation
        for (position, id) in order.enumerated() {
            let webView = session.controller(for: id)?.webView
            Task { [weak self, session] in
                var image: NSImage?
                if let webView, webView.bounds.width > 1, webView.bounds.height > 1 {
                    let configuration = WKSnapshotConfiguration()
                    configuration.snapshotWidth = NSNumber(value: Double(TabSwitcherMetrics.pictureWidth))
                    // A tab that is not on screen has no screen update coming,
                    // and the default waits for one.
                    configuration.afterScreenUpdates = false
                    image = try? await webView.takeSnapshot(configuration: configuration)
                }
                if image == nil { image = await TabLifecycle.snapshot(of: id, in: session) }
                guard let self, self.generation == started, let image else { return }
                self.view?.setPicture(image, at: position)
            }
        }
    }

    /// VoiceOver cannot follow a highlight it is not focused on, and the
    /// keyboard never leaves the page, so the card is read out as it moves.
    private func announce() {
        guard let view, order.indices.contains(index) else { return }
        let title = view.cards[index].accessibilityLabel() ?? ""
        let text = String(localized: "\(title), \(index + 1) of \(order.count)")
        NSAccessibility.post(
            element: view,
            notification: .announcementRequested,
            userInfo: [
                .announcement: text,
                .priority: NSAccessibilityPriorityLevel.high.rawValue
            ]
        )
    }
}
