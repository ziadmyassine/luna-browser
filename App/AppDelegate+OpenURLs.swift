//
//  AppDelegate+OpenURLs.swift
//  Luna
//
//  A web link or an HTML file another app hands to Luna — Finder, Mail,
//  `open -a Luna` — opens as a tab. `Info.plist` has claimed `http` and `https`
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

    /// Only what `Info.plist` claims: web links, and files that are HTML.
    /// Anything else that reaches here was meant for another app.
    static func pages(in urls: [URL]) -> [URL] {
        urls.filter { url in
            if url.isFileURL {
                return UTType(filenameExtension: url.pathExtension)?.conforms(to: .html) ?? false
            }
            return ["http", "https"].contains(url.scheme?.lowercased())
        }
    }

    /// Launched to open something while another Luna is already running.
    ///
    /// This Mac has several copies of the app on disk — a release build, a
    /// debug build, old ones in the Trash — and LaunchServices opens a file
    /// "with Luna" in whichever copy it resolves, starting it if that is not
    /// the one running. That was a second Luna with a second window on the
    /// same database: two writers on one store. So this copy gives the pages
    /// to the running one and quits, before it has opened anything.
    ///
    /// Returns whether it did, in which case launch goes no further.
    func handOffToRunningLuna() -> Bool {
        guard let pages = linksBeforeLaunch, !pages.isEmpty,
              let bundleID = Bundle.main.bundleIdentifier,
              let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                .first(where: { $0 != .current }),
              let location = running.bundleURL
        else { return false }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open(pages, withApplicationAt: location, configuration: configuration) { _, _ in
            Task { @MainActor in NSApp.terminate(nil) }
        }
        return true
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
