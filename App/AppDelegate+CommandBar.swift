//
//  AppDelegate+CommandBar.swift
//  Luna
//
//  §9's bar: the one object behind ⌘T, ⌘L and the top bar's pill. Split out of
//  `AppDelegate.swift` for its type body length.
//
//  Two of the three things here exist because the bar deliberately does not
//  reach outside itself. `perform` is the short list of results it cannot
//  carry out — they change the window or the store rather than the page — and
//  `editLocation` is ⌘L arriving at a layout that owns a URL field, where the
//  bar is the fallback rather than the answer.
//

import AppKit
import BrowserKit

extension AppDelegate {

    /// `⌘T` and `⌘L` (§9.1). The bar is one object shared by both entry points
    /// and by the top bar's pill.
    func wireCommandBar(in window: BrowserWindow) {
        let session = window.session
        // One per `BrowserStore`, so a §5.6 window — which has a store of its
        // own — gets one of its own too, and types nothing into the real one.
        let adaptive = window.isPrivate ? AdaptiveHistory(store: session.store) : sharedAdaptiveHistory(session)
        let bar = CommandBarController(session: session, windowID: window.id, adaptive: adaptive)
        window.commandBar = bar
        let controller = window.controller
        // §9.1: the bar belongs over the page, not over the window.
        bar.contentRegion = { [weak controller] in controller?.contentFrame ?? .zero }
        // The results the bar cannot perform itself (§9.2).
        bar.onExternalAction = { [weak self] action in self?.perform(action) }
        // Weak: the bar holds the session, so a strong capture here is a cycle.
        session.setCommandBar({ [weak bar, weak controller] mode, anchor in
            guard let bar, let host = controller?.window else { return }
            bar.present(mode, in: host, from: anchor)
        }, inWindow: window.id)
    }

    /// §9.3's use counts. Exactly one per `BrowserStore`: two of them would bump
    /// divergent counts against the same `inputHistory` rows.
    private func sharedAdaptiveHistory(_ session: BrowserSession) -> AdaptiveHistory {
        let history = adaptive ?? AdaptiveHistory(store: session.store)
        adaptive = history
        return history
    }

    private func perform(_ action: CommandBarAction) {
        switch action {
        case let .unarchiveTab(id):
            // Not resuming the session: a row in §9's list is a place to go,
            // not a tab to pick up where it was left. See `unarchiveTab`.
            session?.unarchiveTab(id, resumingSession: false)
        case .command(.toggleSidebar):
            toggleSidebar()
        case .command(.newSpace):
            guard let session else { return }
            Task { try? await session.createSpace(name: String(localized: "New Space")) }
        case let .openSettings(section):
            showSettings(section: section)
        case .activateTab, .open:
            // The bar performs these itself; they never reach here.
            break
        }
    }

    /// `⌘L`: the pill expands in place when a layout owns one (§3.2, §4), and
    /// falls back to the Command Bar's edit mode when none is installed.
    func editLocation() {
        guard let session else { return }
        if let focus = session.focusURLField {
            focus()
        } else if let bar = commandBar, let window = browserWindow?.window {
            bar.present(.editCurrentURL, in: window)
        }
    }
}
