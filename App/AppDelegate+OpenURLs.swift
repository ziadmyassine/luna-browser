//
//  AppDelegate+OpenURLs.swift
//  Luna
//
//  A web link another app hands to Luna — Finder, Mail, `open -a Luna` — opens
//  as a tab. `Info.plist` has claimed `http` and `https` all along, and with
//  nothing here to take the link, macOS passed it on to the default browser.
//

import AppKit

extension AppDelegate {

    func application(_ application: NSApplication, open urls: [URL]) {
        let pages = Self.webPages(in: urls)
        guard !pages.isEmpty else { return }
        // A link that launched Luna arrives before the session is restored,
        // and there is no window to put it in until then.
        guard let window = front, linksBeforeLaunch == nil else {
            linksBeforeLaunch = (linksBeforeLaunch ?? []) + pages
            return
        }
        open(pages, in: window)
    }

    /// The links that arrived while Luna was starting, once it can take them.
    func openLinksFromLaunch() {
        let pages = linksBeforeLaunch ?? []
        linksBeforeLaunch = nil
        guard !pages.isEmpty, let window = front else { return }
        open(pages, in: window)
    }

    /// Only what `Info.plist` claims. Anything else that reaches here was
    /// meant for another app.
    static func webPages(in urls: [URL]) -> [URL] {
        urls.filter { ["http", "https"].contains($0.scheme?.lowercased()) }
    }

    /// Each link a tab in the front window, the last one on screen, and the
    /// window brought forward — the user just asked to see it.
    ///
    /// The front window even when it is private, as Safari does: it is the
    /// window the user was last in, and a link landing in some other window
    /// behind it is a link they have to go looking for.
    private func open(_ pages: [URL], in window: BrowserWindow) {
        // The session's verbs act on its key window, and the tabs belong in
        // this one's Space.
        window.session.setKeyWindow(window.id)
        let tabs = pages.map { window.session.newTab(url: $0) }
        if let last = tabs.last { window.session.activateTab(last) }
        window.controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}
