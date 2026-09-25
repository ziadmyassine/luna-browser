//
//  BrowserSession+Engine.swift
//  Luna
//
//  Everything WebKit asks the coordinator for. `TabController` is every
//  `WKNavigationDelegate` / `WKUIDelegate` callback; this is the short list it
//  cannot answer itself because answering needs AppKit or the tab list (§4.2).
//
//  Split from `BrowserSession.swift`: the coordinator's own API is one file and
//  its engine obligations another, so neither grows into the 4,000-line manager
//  §33 warns about.
//

import AppKit
import BrowserKit
import WebKit

// MARK: - Controllers and hibernation (§19.2)

extension BrowserSession {

    /// The tab's controller, cold if it did not have one. Creating a
    /// `TabController` costs no web view and no process — `activate()` is what
    /// does, and only `activateTab` / `webView(for:)` call it.
    func ensureController(for tab: Tab) -> TabController {
        if let existing = controllers[tab.id] { return existing }
        let controller = TabController(
            id: tab.id,
            dataStore: dataStore(forSpace: tab.spaceID),
            favicons: favicons,
            webExtensionController: extensionController(forSpace: tab.spaceID)
        )
        controller.delegate = self
        relayScrollProgress(of: controller)
        controller.restore(interactionState: tab.interactionState, fallbackURL: tab.url)
        // §3.4a: a muted tab that went cold comes back muted. The controller is new, so
        // it starts at the default and has to be told.
        controller.isMuted = mutedTabIDs.contains(tab.id)
        controllers[tab.id] = controller
        return controller
    }

    /// Hibernates the tab and drops its controller entirely: for a tab that is
    /// going away, or changing profile, rather than one merely going cold.
    func discardController(_ id: UUID) {
        guard let controller = controllers.removeValue(forKey: id) else { return }
        controller.hibernate()
        cacheSession(of: controller)
        controller.delegate = nil
    }

    /// §19.2: the active tab plus the last three stay awake, and so does
    /// anything making noise. Everything else loses its web view — and with it
    /// its WebContent process — while keeping its title, icon and blob.
    /// §19.2's budget, applied the moment a new web view is created.
    ///
    /// Delegated to the lifecycle pass rather than reimplemented here: this used
    /// to hibernate anything outside MRU-4 instantly, with no grace period and
    /// no exemption for unsaved form input — so typing into a fifth tab and
    /// switching away could drop what you typed. One policy, one place.
    func enforceLiveTabBudget() {
        TabLifecycle.enforceBudget(in: self)
    }

    func promote(_ id: UUID) {
        recentTabs.removeAll { $0 == id }
        recentTabs.insert(id, at: 0)
    }

    /// Moves a freshly captured session blob onto the `Tab`, where it survives
    /// the controller going away.
    func cacheSession(of controller: TabController) {
        guard var tab = tab(controller.id),
              let state = controller.captureInteractionState(),
              state != tab.interactionState
        else { return }
        tab.interactionState = state
        write(tab)
    }

    func noteVisit(_ url: URL, title: String, tabID: UUID) {
        // `about:` and `luna:` are chrome, not places the user went. Letting
        // them in would put the New Tab page and the archive into history,
        // and then into the Command Bar's suggestions (§9.2).
        guard recordedURL[tabID] != url, let scheme = url.scheme,
              scheme != "about", scheme != InternalPages.scheme else { return }
        recordedURL[tabID] = url
        let kind = pendingVisitKind.removeValue(forKey: tabID) ?? .link
        let store = store
        let space = activeSpaceID
        Task { try? await store.recordVisit(url: url, title: title, kind: kind, at: Date(), inSpace: space) }
    }

    func noteFavicon(_ png: Data?, tabID: UUID) {
        faviconPNG[tabID] = png
        guard var tab = tab(tabID), let host = tab.url.host(), tab.faviconKey != host else { return }
        tab.faviconKey = host
        write(tab)
    }

    /// A child opened by `target="_blank"` or `window.open` (§6.5). WebKit
    /// performs the pending navigation itself once the view is returned, so
    /// nothing here may load.
    func adoptPopup(from parent: UUID, url: URL?, configuration: WKWebViewConfiguration) -> WKWebView? {
        let spaceID = tab(parent)?.spaceID ?? activeSpaceID
        let child = Tab(
            spaceID: spaceID,
            kind: .today,
            url: url ?? Self.blankPage,
            parentTabID: parent,
            order: list.nextOrder(kind: .today, in: spaceID)
        )
        // Newest-first, like any other new tab — a popup that opened off the
        // bottom of the scroll would be the one tab the user cannot see.
        persistAll(list.insert(child, at: openIndex(for: .today)))
        // The popup's configuration already carries the controller; this one
        // is for the view the tab builds after it has been hibernated.
        let controller = TabController(
            id: child.id,
            dataStore: dataStore(forSpace: spaceID),
            favicons: favicons,
            webExtensionController: extensionController(forSpace: spaceID)
        )
        controller.delegate = self
        relayScrollProgress(of: controller)
        controllers[child.id] = controller
        let webView = controller.activate(with: configuration)
        activeTabBySpace[spaceID] = child.id
        promote(child.id)
        enforceLiveTabBudget()
        notifyChange()
        return webView
    }
}

// MARK: - WebKit's callbacks

extension BrowserSession: TabControllerDelegate {

    func tabController(_ controller: TabController, didChange state: TabState) {
        let id = controller.id
        if var tab = tab(id) {
            var changed = false
            if let url = state.url, tab.url != url {
                // A different site is a different mark. `faviconPNG` is this
                // session's answer for the tab and it outlives the page it was
                // fetched for, so leaving it in place is what carried the last
                // site's icon onto the new one until the fetch landed — a tab
                // strip showing Google's G on a page that is not Google's. The
                // §4.7 fallback (host → cache) takes over, and it is keyed on
                // the URL being assigned right here.
                if url.host() != tab.url.host() { faviconPNG[id] = nil }
                tab.url = url
                changed = true
            }
            if !state.title.isEmpty, tab.title != state.title {
                tab.title = state.title
                changed = true
            }
            if tab.themeColor != state.themeColor {
                tab.themeColor = state.themeColor
                changed = true
            }
            if changed { write(tab) }
        }

        // §6.2: cache the session blob outside the web view at every
        // settled load. `interactionState` reads back nil once the WebContent
        // process is gone, so capturing it only on hibernate loses exactly the
        // case §19.3 has to recover from.
        if !state.isLoading, let url = state.url {
            cacheSession(of: controller)
            noteVisit(url, title: state.title, tabID: id)
        }

        notifyTabState(id, state)
    }

    func tabController(
        _ controller: TabController,
        wantsNewTabFor url: URL?,
        configuration: WKWebViewConfiguration
    ) -> WKWebView? {
        adoptPopup(from: controller.id, url: url, configuration: configuration)
    }

    func tabController(_ controller: TabController, didStartDownload download: WKDownload) {
        guard let onDownload else {
            // WebKit asks for a destination immediately and `WKDownload.delegate`
            // is weak: a download nobody owns stalls in silence, so refuse it
            // out loud instead.
            download.cancel()
            return
        }
        onDownload(download)
    }

    func tabController(_ controller: TabController, didFailWith error: any Error) {
        // §19.3 already retried and gave up; the page keeps whatever it last
        // painted. A user-facing error surface is §18's, not the coordinator's.
        NSLog("Luna: tab %@ failed: %@", controller.id.uuidString, error.localizedDescription)
    }

    @discardableResult
    func tabController(_ controller: TabController, wantsToOpenExternally url: URL) -> Bool {
        NSWorkspace.shared.open(url)
    }

    func tabController(_ controller: TabController, didUpdateFavicon png: Data?) {
        noteFavicon(png, tabID: controller.id)
        guard let live = self.controller(for: controller.id) else { return }
        notifyTabState(controller.id, live.state)
    }

    func tabControllerDidRecoverFromProcessTermination(_ controller: TabController) {
        notifyChange()
    }

    // MARK: - JavaScript dialogs
    //
    // `prompt()` is deliberately left at the protocol's default (cancel): its
    // accessory text field needs a width, and there is no metric token for one.
    // Asking for the token beats inventing the number (contract rule 2).

    func tabController(_ controller: TabController, runJavaScriptAlert message: String) async {
        _ = await present(message, confirmable: false)
    }

    func tabController(_ controller: TabController, runJavaScriptConfirm message: String) async -> Bool {
        await present(message, confirmable: true)
    }

    private func present(_ message: String, confirmable: Bool) async -> Bool {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: NSLocalizedString("OK", comment: "JavaScript dialog accept"))
        if confirmable {
            alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "JavaScript dialog cancel"))
        }
        guard let window = hostWindow else { return alert.runModal() == .alertFirstButtonReturn }
        return await alert.beginSheetModal(for: window) == .alertFirstButtonReturn
    }
}
