import CryptoKit
import Foundation
import WebKit

/// One Space's extensions (§16.1): its `WKWebExtensionController`, the contexts
/// loaded into it, and what they are told about the Space's windows and tabs.
///
/// Every Space has one from the moment its first web view is built, whether or
/// not anything is installed — about 1 MB and no processes (docs/EXTENSIONS.md
/// §3.2). The controller has to be on a web view's configuration before the
/// view exists, so one attached later would mean rebuilding every tab.
@MainActor
public final class ExtensionHost: NSObject {

    public let spaceID: UUID
    public let controller: WKWebExtensionController
    let backgroundStore: WKWebsiteDataStore

    weak var browser: (any ExtensionBrowser)?
    weak var ui: (any ExtensionUI)?
    /// A runtime prompt was answered; the manager persists the new grants.
    var onGrantsChanged: ((String, ExtensionGrants) -> Void)?

    private(set) var contexts: [String: WKWebExtensionContext] = [:]
    /// Internal only because the delegate is next door and updates grants.
    var loaded: [String: (directory: URL, grants: ExtensionGrants)] = [:]
    private var hasClearedWorkers = false
    private var lastRecovery: [String: Date] = [:]
    private var errorObserver: (any NSObjectProtocol)?

    private(set) var snapshot = ExtensionSnapshot()
    private var tabAdapters: [UUID: ExtensionTab] = [:]
    private var windowAdapters: [UUID: ExtensionWindow] = [:]
    private var tabProperties: [UUID: TabProperties] = [:]

    /// A failed background is retried at most this often (§4: a failed worker
    /// stays failed unless the host reloads it).
    static let recoveryInterval: TimeInterval = 60
    /// `loadBackgroundContent` has been seen never to call back (§4, Ora with
    /// Bitwarden); after this long it is treated as failed.
    static let backgroundTimeout: Duration = .seconds(8)

    /// - Parameter dataStore: the Space's own, identified store. Its identifier
    ///   names the controller's storage, so it has to be the same every launch.
    init(spaceID: UUID, dataStore: WKWebsiteDataStore) {
        self.spaceID = spaceID
        let identifier = dataStore.identifier ?? UUID()
        backgroundStore = WKWebsiteDataStore(forIdentifier: Self.backgroundStoreIdentifier(forSpaceStore: identifier))

        // All of it before `init`: `controller.configuration` hands back a copy.
        let configuration = WKWebExtensionController.Configuration(identifier: identifier)
        configuration.defaultWebsiteDataStore = dataStore
        // Background pages register their workers in this store, not in
        // `defaultWebsiteDataStore`. Its own store is what lets launch clear
        // stale registrations without touching the sites' workers (§4).
        let extensionPages = WKWebViewConfiguration()
        extensionPages.websiteDataStore = backgroundStore
        extensionPages.applicationNameForUserAgent = WebViewFactory.extensionApplicationNameForUserAgent
        configuration.webViewConfiguration = extensionPages
        controller = WKWebExtensionController(configuration: configuration)
        super.init()
        controller.delegate = self
        errorObserver = NotificationCenter.default.addObserver(
            forName: WKWebExtensionContext.errorsDidUpdateNotification, object: nil, queue: .main
        ) { [weak self] note in
            nonisolated(unsafe) let object = note.object
            MainActor.assumeIsolated { self?.errorsDidUpdate(object as? WKWebExtensionContext) }
        }
    }

    /// Unloads everything and stops watching for failed backgrounds.
    func tearDown() {
        for id in Array(contexts.keys) { unload(id) }
        if let errorObserver { NotificationCenter.default.removeObserver(errorObserver) }
        errorObserver = nil
    }

    /// Where a Space's background pages keep their data: a store of their own,
    /// derived from the Space's so it needs no column. `ProfileStore` keeps and
    /// removes it alongside the Space's, or the orphan sweep would delete it.
    public nonisolated static func backgroundStoreIdentifier(forSpaceStore identifier: UUID) -> UUID {
        var bytes = Array(SHA256.hash(data: Data("luna.extensions.background".utf8) + withUnsafeBytes(of: identifier.uuid) {
            Data($0)
        }).prefix(16))
        // RFC 9562's version-5 bits, so it reads as the name-based UUID it is.
        bytes[6] = bytes[6] & 0x0F | 0x50
        bytes[8] = bytes[8] & 0x3F | 0x80
        return bytes.withUnsafeBufferPointer { NSUUID(uuidBytes: $0.baseAddress) as UUID }
    }

    // MARK: - Contexts

    /// Loads `id` from `directory` with `grants` applied first — WebKit keeps no
    /// grants across launches, so they are always Luna's to re-apply.
    func load(_ id: String, from directory: URL, grants: ExtensionGrants) async throws {
        if !hasClearedWorkers {
            hasClearedWorkers = true
            await clearWorkerRegistrations()
        }
        let context = try await attach(id, from: directory, grants: grants)
        if context.webExtension.hasBackgroundContent, await !Self.startBackground(context) {
            await recover(id)
        }
    }

    func unload(_ id: String) {
        guard let context = contexts.removeValue(forKey: id) else { return }
        try? controller.unload(context)
        loaded[id] = nil
    }

    /// New grants on a loaded context, replacing the old ones outright so a
    /// revocation takes effect too.
    func apply(_ grants: ExtensionGrants, to id: String) {
        guard let context = contexts[id] else { return }
        grants.apply(to: context)
        loaded[id]?.grants = grants
    }

    private func attach(_ id: String, from directory: URL, grants: ExtensionGrants) async throws -> WKWebExtensionContext {
        unload(id)
        let context = WKWebExtensionContext(for: try await WKWebExtension(resourceBaseURL: directory))
        // Both fixed, or the extension's storage moves every launch (§3.3).
        context.uniqueIdentifier = id
        context.baseURL = URL(string: "webkit-extension://\(id)/")!
        context.isInspectable = WebViewFactory.isWebInspectorEnabled
        grants.apply(to: context)
        try controller.load(context)
        contexts[id] = context
        loaded[id] = (directory, grants)
        return context
    }

    /// The §4 trap: a service-worker registration left from the last launch
    /// is reused and never started, silently. The store-wide removal is the
    /// only one that works — `dataRecords(ofTypes:)` does not list
    /// `webkit-extension://` origins — and it is safe because this store holds
    /// nothing but extension pages.
    private func clearWorkerRegistrations() async {
        await backgroundStore.removeData(ofTypes: [WKWebsiteDataTypeServiceWorkerRegistrations], modifiedSince: .distantPast)
    }

    /// Unload, clear the registrations, load again. Once a minute at most, and
    /// a second failure is left for the next error to retry.
    func recover(_ id: String) async {
        guard let entry = loaded[id] else { return }
        if let last = lastRecovery[id], Date().timeIntervalSince(last) < Self.recoveryInterval { return }
        lastRecovery[id] = Date()
        unload(id)
        await clearWorkerRegistrations()
        guard let context = try? await attach(id, from: entry.directory, grants: entry.grants) else { return }
        _ = await Self.startBackground(context)
    }

    private func errorsDidUpdate(_ context: WKWebExtensionContext?) {
        guard let context, contexts[context.uniqueIdentifier] === context else { return }
        let failed = context.errors.contains {
            ($0 as NSError).domain == WKWebExtensionContext.errorDomain
                && ($0 as NSError).code == WKWebExtensionContext.Error.backgroundContentFailedToLoad.rawValue
        }
        guard failed else { return }
        Task { await recover(context.uniqueIdentifier) }
    }

    /// True once the background has loaded; false on an error or no answer in time.
    static func startBackground(_ context: WKWebExtensionContext) async -> Bool {
        await withCheckedContinuation { continuation in
            let once = Once(continuation)
            context.loadBackgroundContent { error in
                MainActor.assumeIsolated { once.resume(error == nil) }
            }
            Task { @MainActor in
                try? await Task.sleep(for: backgroundTimeout)
                once.resume(false)
            }
        }
    }

    /// A continuation two callers race to resume.
    @MainActor
    private final class Once {
        private var continuation: CheckedContinuation<Bool, Never>?
        init(_ continuation: CheckedContinuation<Bool, Never>) { self.continuation = continuation }
        func resume(_ value: Bool) {
            continuation?.resume(returning: value)
            continuation = nil
        }
    }
}

// MARK: - Windows and tabs

extension ExtensionHost {

    private struct TabProperties: Equatable {
        var title: String
        var url: URL?
        var isLoading: Bool
    }

    /// Re-reads the Space's windows and tabs and tells WebKit what changed.
    /// Called on every structural change; a change that moved nothing costs
    /// one comparison.
    func sync() {
        guard let browser else { return }
        let windows = browser.extensionWindows(inSpace: spaceID)
        var next = ExtensionSnapshot(windows: windows.ids, focused: windows.focused)
        next.tabs = browser.extensionTabs(inSpace: spaceID).map(\.id)
        next.activeTab = next.primaryWindow.flatMap(browser.activeTabID(inWindow:)).flatMap {
            next.tabs.contains($0) ? $0 : nil
        }
        let events = ExtensionSnapshot.events(from: snapshot, to: next)
        snapshot = next
        for event in events { deliver(event) }
    }

    private func deliver(_ event: ExtensionSnapshot.Event) {
        switch event {
        case .openWindow(let id):
            controller.didOpenWindow(windowAdapter(id))
        case .focusWindow(let id):
            controller.didFocusWindow(id.map(windowAdapter))
        case .closeTab(let id):
            tabProperties[id] = nil
            if let tab = tabAdapters.removeValue(forKey: id) { controller.didCloseTab(tab, windowIsClosing: false) }
        case .closeWindow(let id):
            if let window = windowAdapters.removeValue(forKey: id) { controller.didCloseWindow(window) }
        case .openTab(let id), .moveTab(let id, _, _), .activateTab(let id, _):
            if let tab = tabAdapter(id) { deliver(event, about: tab) }
        }
    }

    private func deliver(_ event: ExtensionSnapshot.Event, about tab: ExtensionTab) {
        switch event {
        case .openTab:
            controller.didOpenTab(tab)
        case let .moveTab(_, from, oldWindow):
            controller.didMoveTab(tab, from: from, in: oldWindow.flatMap { windowAdapters[$0] })
        case let .activateTab(_, previous):
            controller.didActivateTab(tab, previousActiveTab: previous.flatMap { tabAdapters[$0] })
        default:
            break
        }
    }

    /// Title, URL and loading, as the tab reports them. Hibernating changes
    /// none of the three, so it reaches no extension.
    func tabDidChange(_ id: UUID, state: TabState) {
        guard let tab = tabAdapters[id] else { return }
        let now = TabProperties(title: state.title, url: state.url, isLoading: state.isLoading)
        let old = tabProperties.updateValue(now, forKey: id)
        guard let old, old != now else { return }
        var changed: WKWebExtension.TabChangedProperties = []
        if old.title != now.title { changed.insert(.title) }
        if old.url != now.url { changed.insert(.URL) }
        if old.isLoading != now.isLoading { changed.insert(.loading) }
        controller.didChangeTabProperties(changed, for: tab)
    }

    /// The adapter for a tab the Space shows, made on first use and kept until it closes.
    func tabAdapter(_ id: UUID) -> ExtensionTab? {
        if let existing = tabAdapters[id] { return existing }
        guard snapshot.tabs.contains(id) else { return nil }
        let tab = ExtensionTab(id: id, host: self)
        tabAdapters[id] = tab
        return tab
    }

    func windowAdapter(_ id: UUID) -> ExtensionWindow {
        if let existing = windowAdapters[id] { return existing }
        let window = ExtensionWindow(id: id, host: self)
        windowAdapters[id] = window
        return window
    }

    var primaryWindowAdapter: ExtensionWindow? { snapshot.primaryWindow.map(windowAdapter) }
}

extension ExtensionGrants {

    /// Sets the context's four grant tables to exactly these, with no expiry.
    @MainActor
    func apply(to context: WKWebExtensionContext) {
        func permissions(_ names: Set<String>) -> [WKWebExtension.Permission: Date] {
            Dictionary(uniqueKeysWithValues: names.map { (WKWebExtension.Permission(rawValue: $0), Date.distantFuture) })
        }
        func patterns(_ strings: Set<String>) -> [WKWebExtension.MatchPattern: Date] {
            let parsed = strings.compactMap { try? WKWebExtension.MatchPattern(string: $0) }
            return Dictionary(parsed.map { ($0, Date.distantFuture) }) { first, _ in first }
        }
        context.grantedPermissions = permissions(grantedPermissions)
        context.deniedPermissions = permissions(deniedPermissions)
        context.grantedPermissionMatchPatterns = patterns(grantedPatterns)
        context.deniedPermissionMatchPatterns = patterns(deniedPatterns)
    }
}
