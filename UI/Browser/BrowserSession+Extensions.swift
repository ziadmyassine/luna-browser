//
//  BrowserSession+Extensions.swift
//  Luna
//
//  §16.1's seam between the session and `ExtensionManager`: which controller
//  a Space's web views are built with, and the session answering for its
//  windows and tabs as `ExtensionBrowser`. The host itself is in BrowserKit.
//

import BrowserKit
import WebKit

extension BrowserSession {

    /// The Space's extension controller, for every web view built in it. Nil
    /// in a private session and for a Space that no longer exists.
    func extensionController(forSpace spaceID: UUID) -> WKWebExtensionController? {
        guard let extensions, space(spaceID) != nil else { return nil }
        return extensions.controller(forSpace: spaceID, dataStore: dataStore(forSpace: spaceID))
    }

    /// Loads what is installed, one extension at a time. After the first
    /// window is on screen (docs/EXTENSIONS.md §4): loading them together
    /// failed some workers for good.
    func startExtensions() {
        guard let extensions else { return }
        let spaces = spaces.map { (id: $0.id, dataStore: dataStore(forSpace: $0.id)) }
        Task {
            await extensions.start(spaces: spaces)
            // The icons and badges the chrome drew before this were for no
            // extensions at all.
            ExtensionsCenter.shared.announce()
        }
    }
}

extension BrowserSession: ExtensionBrowser {

    /// Sorted by id, which is arbitrary but stable: the first window holds the
    /// Space's tabs, and a dictionary's order would hand them to a different
    /// window on every change.
    func extensionWindows(inSpace space: UUID) -> (ids: [UUID], focused: UUID?) {
        let ids = windowFocus.filter { $0.value.spaceID == space }.keys.sorted { $0.uuidString < $1.uuidString }
        return (ids, ids.contains(keyWindowID) ? keyWindowID : nil)
    }

    /// A saved row whose page was closed (§3.4b) has no page to show an extension.
    func extensionTabs(inSpace space: UUID) -> [Tab] {
        list[space].filter { !$0.isDormant }
    }

    func loadURL(_ url: URL, inTab id: UUID) {
        guard let tab = tab(id) else { return }
        ensureController(for: tab).load(url)
    }

    /// A tab an extension asked for, placed where a new tab goes. An
    /// extension's own page is built from `configuration`; a web page is left
    /// cold unless it is to be shown, like any tab nobody is looking at.
    func openExtensionTab(url: URL?, inSpace spaceID: UUID, configuration: WKWebViewConfiguration?, activate: Bool) -> UUID? {
        guard space(spaceID) != nil else { return nil }
        let tab = Tab(
            spaceID: spaceID,
            kind: .today,
            url: url ?? Self.blankPage,
            order: list.nextOrder(kind: .today, in: spaceID)
        )
        persistAll(list.insert(tab, at: openIndex(for: .today)))
        if let configuration, let url {
            let controller = ensureController(for: tab)
            controller.activate(with: configuration)
            controller.load(url)
        }
        if activate { activateTab(tab.id) } else { notifyChange() }
        return tab.id
    }
}
