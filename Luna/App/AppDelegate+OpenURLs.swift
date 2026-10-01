//
//  AppDelegate+OpenURLs.swift
//  Luna
//
//  A web link or a file another app hands to Luna — Finder, Mail,
//  `open -a Luna`, or a drop on the window (`WindowDrop`) — opens as a tab. The files are `LocalFileTypes`. `Info.plist` has claimed `http` and `https`
//  all along, and with nothing here to take the link, macOS passed it on to the
//  default browser. It claims HTML documents too now; before it did, a file
//  opened "with Luna" was dropped here and nothing opened at all.
//

import AppKit
import UniformTypeIdentifiers

extension AppDelegate {

    func application(_ application: NSApplication, open urls: [URL]) {
        let pages = Self.pages(in: urls)
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

    /// Only what `Info.plist` claims: web links, and the files in
    /// `LocalFileTypes`. Anything else that reaches here was meant for another app.
    static func pages(in urls: [URL]) -> [URL] {
        urls.filter { url in
            if url.isFileURL { return LocalFileTypes.opens(url) }
            return ["http", "https"].contains(url.scheme?.lowercased())
        }
    }

    /// Launched while another Luna is already running (§19.7).
    ///
    /// This Mac has several copies of the app on disk — a release build, a
    /// debug build, old ones in the Trash — and LaunchServices opens a file
    /// "with Luna" in whichever copy it resolves, starting it if that is not
    /// the one running; `open -n` starts a second one outright. A second Luna
    /// is a second window on the same database, and its open failed with
    /// SQLite's "database is locked" and a window with no chrome. So this copy
    /// gives the running one its pages, or just brings it forward, and quits
    /// before it has opened anything.
    ///
    /// Not under XCTest: the test host has a database of its own
    /// (`databaseURL`) and must run beside the Luna in use.
    ///
    /// Returns whether it did, in which case launch goes no further.
    func handOffToRunningLuna() -> Bool {
        guard !Self.isRunningTests,
              let bundleID = Bundle.main.bundleIdentifier,
              let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                .first(where: { $0 != .current && !$0.isTerminated }),
              let location = running.bundleURL
        else { return false }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        let quit: @Sendable (NSRunningApplication?, (any Error)?) -> Void = { _, _ in
            Task { @MainActor in NSApp.terminate(nil) }
        }
        if let pages = linksBeforeLaunch, !pages.isEmpty {
            NSWorkspace.shared.open(pages, withApplicationAt: location, configuration: configuration, completionHandler: quit)
        } else {
            NSWorkspace.shared.openApplication(at: location, configuration: configuration, completionHandler: quit)
        }
        return true
    }

    /// Each link a tab in the window, the last one on screen, and the window
    /// brought forward — the user just asked to see it.
    ///
    /// From another app, the front window even when it is private, as Safari
    /// does: it is the window the user was last in, and a link landing in some
    /// other window behind it is a link they have to go looking for. A drop
    /// (`WindowDrop`) opens in the window it landed on.
    /// - Parameter landing: where in the list they go — §6.6's mark, for a
    ///   drop — or nil for where a new tab opens.
    func open(_ pages: [URL], in window: BrowserWindow, at landing: SidebarDestination? = nil) {
        // The session's verbs act on its key window, and the tabs belong in
        // this one's Space.
        window.session.setKeyWindow(window.id)
        let tabs = window.session.openTabs(pages, at: landing)
        if let last = tabs.last { window.session.activateTab(last) }
        window.controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}
