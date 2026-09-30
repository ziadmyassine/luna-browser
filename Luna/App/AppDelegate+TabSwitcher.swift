//
//  AppDelegate+TabSwitcher.swift
//  Luna
//
//  `⌃⇥`'s wiring: one switcher per window, and the one event monitor that
//  feeds whichever window is in front.
//
//  A monitor rather than a menu item, for two reasons. The switch ends when
//  `⌃` comes up, and a key equivalent hears the press and never the release.
//  And the page usually has the keyboard: a `WKWebView` is sent `⌃⇥` before
//  any menu is asked, and a local monitor sees it before either.
//

import AppKit

extension AppDelegate {

    func wireTabSwitcher(in window: BrowserWindow) {
        window.tabSwitcher = TabSwitcherController(session: window.session, windowID: window.id)
    }

    /// Once, at launch. The monitor lives as long as the app.
    func installTabSwitcherKeys() {
        tabSwitcherMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self, self.routeTabSwitcherKey(event) else { return event }
            return nil
        }
    }

    /// - Returns: true when the event was the switcher's and must go no further.
    private func routeTabSwitcherKey(_ event: NSEvent) -> Bool {
        guard let front, let host = front.controller.window, event.window === host,
              let switcher = front.tabSwitcher
        else { return false }
        guard let key = TabSwitcherKey.reading(
            event.type,
            keyCode: event.keyCode,
            modifiers: event.modifierFlags,
            isEngaged: switcher.isEngaged
        ) else { return false }
        // The Command Bar has the keyboard while it is up, and a tab changing
        // underneath it would leave it answering for a page that has gone.
        if !switcher.isEngaged, front.commandBar?.isPresented == true { return false }
        let taken = switcher.handle(key, in: host)
        // The release of `⌃` still goes on to AppKit, which keeps its own
        // record of which modifiers are down.
        return taken && event.type == .keyDown
    }
}
