import Foundation
import WebKit

/// One Luna tab as a Space's extensions see it. One object per tab for as long
/// as the tab is open, because WebKit compares tabs by identity.
///
/// Everything is read live from the browser. A hibernated tab answers with its
/// stored title and URL and no web view, which keeps it asleep
/// (docs/EXTENSIONS.md §3.6).
@MainActor
final class ExtensionTab: NSObject, WKWebExtensionTab {

    let id: UUID
    private weak var host: ExtensionHost?

    init(id: UUID, host: ExtensionHost) {
        self.id = id
        self.host = host
    }

    private var browser: (any ExtensionBrowser)? { host?.browser }
    private var tab: Tab? {
        guard let host else { return nil }
        return host.browser?.extensionTabs(inSpace: host.spaceID).first { $0.id == id }
    }
    private var live: TabController? { browser?.controller(for: id) }

    func window(for context: WKWebExtensionContext) -> (any WKWebExtensionWindow)? {
        host?.primaryWindowAdapter
    }

    func indexInWindow(for context: WKWebExtensionContext) -> Int {
        host?.snapshot.tabs.firstIndex(of: id) ?? 0
    }

    func parentTab(for context: WKWebExtensionContext) -> (any WKWebExtensionTab)? {
        tab?.parentTabID.flatMap { host?.tabAdapter($0) }
    }

    func webView(for context: WKWebExtensionContext) -> WKWebView? { live?.webView }

    func title(for context: WKWebExtensionContext) -> String? {
        live.map(\.state.title).flatMap { $0.isEmpty ? nil : $0 } ?? tab?.title
    }

    func url(for context: WKWebExtensionContext) -> URL? { live?.state.url ?? tab?.url }

    func isPinned(for context: WKWebExtensionContext) -> Bool { tab.map { $0.kind != .today } ?? false }

    func isLoadingComplete(for context: WKWebExtensionContext) -> Bool { !(live?.state.isLoading ?? false) }

    func isPlayingAudio(for context: WKWebExtensionContext) -> Bool { live?.state.isPlayingAudio ?? false }

    func isMuted(for context: WKWebExtensionContext) -> Bool { live?.isMuted ?? false }

    func isSelected(for context: WKWebExtensionContext) -> Bool { host?.snapshot.activeTab == id }

    /// `activeTab`: a click on the extension's button is the consent.
    func shouldGrantPermissionsOnUserGesture(for context: WKWebExtensionContext) -> Bool { true }

    func activate(for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        browser?.activateTab(id)
        completionHandler(nil)
    }

    func close(for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        browser?.closeTab(id)
        completionHandler(nil)
    }

    func loadURL(_ url: URL, for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        browser?.loadURL(url, inTab: id)
        completionHandler(nil)
    }

    func reload(fromOrigin: Bool, for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        if fromOrigin { live?.webView?.reloadFromOrigin() } else { live?.reload() }
        completionHandler(nil)
    }

    func goBack(for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        live?.goBack()
        completionHandler(nil)
    }

    func goForward(for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        live?.goForward()
        completionHandler(nil)
    }
}

/// One browser window standing in the Space. Only the first of them holds the
/// Space's tabs — see ``ExtensionSnapshot/tabs``.
@MainActor
final class ExtensionWindow: NSObject, WKWebExtensionWindow {

    let id: UUID
    private weak var host: ExtensionHost?

    init(id: UUID, host: ExtensionHost) {
        self.id = id
        self.host = host
    }

    private var holdsTabs: Bool { host?.snapshot.primaryWindow == id }

    func tabs(for context: WKWebExtensionContext) -> [any WKWebExtensionTab] {
        guard holdsTabs, let host else { return [] }
        return host.snapshot.tabs.compactMap { host.tabAdapter($0) }
    }

    func activeTab(for context: WKWebExtensionContext) -> (any WKWebExtensionTab)? {
        guard holdsTabs, let active = host?.snapshot.activeTab else { return nil }
        return host?.tabAdapter(active)
    }

    func windowType(for context: WKWebExtensionContext) -> WKWebExtension.WindowType { .normal }

    func windowState(for context: WKWebExtensionContext) -> WKWebExtension.WindowState { .normal }

    func isPrivate(for context: WKWebExtensionContext) -> Bool { false }
}
