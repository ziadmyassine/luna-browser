import Foundation
import WebKit

/// Luna's extensions (§16): one ``ExtensionHost`` per Space, the installed
/// set, and the API a future Extensions UI calls. There is no UI here, and
/// nothing a web page can reach — every entry point is Luna's own.
///
/// State lives in three places and this keeps them agreeing: the database
/// (installed, enabled per Space, grants per Space), the folders under the
/// library root, and the contexts loaded into each Space's controller.
@MainActor
public final class ExtensionManager {

    public weak var browser: (any ExtensionBrowser)? {
        didSet { for host in hosts.values { host.browser = browser } }
    }

    /// Set by the UI when it exists. Until then every decision that needs a
    /// person gets the safe answer — see ``ExtensionUI``.
    public weak var ui: (any ExtensionUI)? {
        didSet { for host in hosts.values { host.ui = ui } }
    }

    private let store: BrowserStore
    private let library: ExtensionLibrary
    private var hosts: [UUID: ExtensionHost] = [:]
    private var installed: [String: Installed] = [:]

    private struct Installed {
        var record: ExtensionRecord
        var spaces: [UUID: ExtensionSpaceRecord]
        var details: ExtensionDetails?
    }

    /// The gap between one context load and the next at launch. Loading them
    /// together failed some workers and WebKit never retried (§4, Search); the
    /// spike held with 400 ms and each background awaited in between.
    static let launchStagger: Duration = .milliseconds(400)

    public init(store: BrowserStore, library: ExtensionLibrary) {
        self.store = store
        self.library = library
    }

    // MARK: - Spaces

    /// The Space's controller, made on first use. The session hands it to every
    /// web view it builds in that Space.
    public func controller(forSpace spaceID: UUID, dataStore: WKWebsiteDataStore) -> WKWebExtensionController {
        host(forSpace: spaceID, dataStore: dataStore).controller
    }

    private func host(forSpace spaceID: UUID, dataStore: WKWebsiteDataStore) -> ExtensionHost {
        if let existing = hosts[spaceID] { return existing }
        let host = ExtensionHost(spaceID: spaceID, dataStore: dataStore)
        host.browser = browser
        host.ui = ui
        host.onGrantsChanged = { [weak self] id, grants in self?.remember(grants, for: id, inSpace: spaceID) }
        hosts[spaceID] = host
        host.sync()
        return host
    }

    /// Reads what is installed and loads it, one context at a time, spaced
    /// out. Call once, after the first window is on screen (§4).
    public func start(spaces: [(id: UUID, dataStore: WKWebsiteDataStore)]) async {
        try? FileManager.default.removeItem(at: library.root.appending(path: ".staging"))
        for (record, rows) in (try? await store.installedExtensions()) ?? [] {
            var details: ExtensionDetails?
            if let directory = try? library.directory(for: record.id) { details = await Self.details(directory) }
            installed[record.id] = Installed(
                record: record,
                spaces: Dictionary(rows.map { ($0.spaceID, $0) }) { first, _ in first },
                details: details
            )
        }
        for space in spaces {
            let host = host(forSpace: space.id, dataStore: space.dataStore)
            for (id, entry) in installed.sorted(by: { $0.value.record.installedAt < $1.value.record.installedAt }) {
                guard let row = entry.spaces[space.id], row.isEnabled else { continue }
                await load(id, into: host, grants: row.grants)
                try? await Task.sleep(for: Self.launchStagger)
            }
        }
    }

    /// A Space is being deleted: its contexts go, and so does the extension
    /// storage under its controller. Its database rows cascade with the Space.
    public func removeSpace(_ spaceID: UUID) async {
        guard let host = hosts.removeValue(forKey: spaceID) else { return }
        host.tearDown()
        await host.removeStoredData(of: nil)
        for id in installed.keys { installed[id]?.spaces[spaceID] = nil }
    }

    /// Unloads every context, for a session going away. The hosts stay, so a
    /// web view built afterwards still gets its Space's controller.
    public func tearDown() {
        for host in hosts.values { host.tearDown() }
    }

    /// The browser's windows or tabs changed shape.
    public func sync() {
        for host in hosts.values { host.sync() }
    }

    public func tabDidChange(_ id: UUID, state: TabState) {
        for host in hosts.values { host.tabDidChange(id, state: state) }
    }

    // MARK: - Listing

    /// Every installed extension, oldest install first.
    public var extensions: [ExtensionInfo] {
        installed.values.sorted { $0.record.installedAt < $1.record.installedAt }.map { entry in
            ExtensionInfo(
                id: entry.record.id,
                source: entry.record.source,
                details: entry.details,
                enabledSpaces: Set(entry.spaces.values.filter(\.isEnabled).map(\.spaceID)),
                grants: entry.spaces.mapValues(\.grants)
            )
        }
    }

    /// The extension's action as it stands in `tab` — or its default, for nil.
    /// Nil when it is not running in that Space.
    public func action(for id: String, tab: UUID?, inSpace spaceID: UUID) -> WKWebExtension.Action? {
        guard let host = hosts[spaceID], let context = host.contexts[id] else { return nil }
        return context.action(for: tab.flatMap(host.tabAdapter))
    }

    /// What pressing the extension's button does: WebKit runs the action and,
    /// if it has one, asks ``ExtensionUI/presentPopup(for:extensionID:spaceID:)``.
    public func performAction(for id: String, tab: UUID?, inSpace spaceID: UUID) {
        guard let host = hosts[spaceID], let context = host.contexts[id] else { return }
        context.performAction(for: tab.flatMap(host.tabAdapter))
    }

    // MARK: - Install

    /// Unpacks and reads a folder, `.zip` or `.crx` for the install prompt.
    /// Nothing is installed until ``install(_:granting:inSpace:)``.
    public func prepareInstall(from file: URL) async throws -> ExtensionInstallRequest {
        try await request(for: try await library.stage(file))
    }

    /// The same for the Chrome Web Store's current build of `webStoreID`.
    public func prepareInstall(webStoreID: String) async throws -> ExtensionInstallRequest {
        try await request(for: try await library.stageFromWebStore(id: webStoreID))
    }

    private func request(for staged: StagedExtension) async throws -> ExtensionInstallRequest {
        do {
            let webExtension = try await WKWebExtension(resourceBaseURL: staged.directory)
            return ExtensionInstallRequest(
                id: staged.id,
                source: staged.source,
                details: ExtensionDetails(webExtension, directory: staged.directory),
                isUpdate: installed[staged.id] != nil,
                staged: staged
            )
        } catch {
            await library.discard(staged)
            throw error
        }
    }

    public func cancelInstall(_ request: ExtensionInstallRequest) async {
        await library.discard(request.staged)
    }

    /// Installs with the user's answer, enabled in `spaceID` only (§3.1).
    /// Whatever the request listed and `granting` leaves out is recorded as refused.
    /// An update keeps every other Space's answers and reloads it where it runs.
    public func install(_ request: ExtensionInstallRequest, granting: ExtensionGrants, inSpace spaceID: UUID) async throws {
        for host in hosts.values { host.unload(request.id) }
        let directory = try await library.commit(request.staged)
        var grants = granting
        grants.deniedPermissions.formUnion(Set(request.details.permissions).subtracting(granting.grantedPermissions))
        grants.deniedPatterns.formUnion(Set(request.details.hostPatterns).subtracting(granting.grantedPatterns))
        let record = installed[request.id]?.record ?? ExtensionRecord(id: request.id, source: request.source)
        let row = ExtensionSpaceRecord(extensionID: request.id, spaceID: spaceID, isEnabled: true, grants: grants)
        try await store.saveExtension(record, in: row)

        var entry = installed[request.id] ?? Installed(record: record, spaces: [:])
        entry.spaces[spaceID] = row
        entry.details = await Self.details(directory)
        installed[request.id] = entry
        for (space, row) in entry.spaces where row.isEnabled {
            guard let host = hosts[space] else { continue }
            await load(request.id, into: host, grants: row.grants)
        }
    }

    /// Removes it everywhere, with what it stored under each Space's controller.
    public func uninstall(_ id: String) async throws {
        guard installed.removeValue(forKey: id) != nil else { throw ExtensionError.unknownExtension }
        for host in hosts.values {
            await host.removeStoredData(of: id)
            host.unload(id)
        }
        try await store.deleteExtension(id: id)
        try await library.remove(id)
    }

    // MARK: - Per Space (§16.6)

    /// Turning an extension on in a Space it has never run in carries over the
    /// answers the user gave at install: the consent was to the extension, and
    /// the prompt would ask the same questions again.
    public func setEnabled(_ enabled: Bool, extension id: String, inSpace spaceID: UUID) async throws {
        guard let entry = installed[id] else { throw ExtensionError.unknownExtension }
        let inherited = (entry.spaces.values.first(where: \.isEnabled) ?? entry.spaces.values.first)?.grants
        var row = entry.spaces[spaceID]
            ?? ExtensionSpaceRecord(extensionID: id, spaceID: spaceID, isEnabled: false, grants: inherited ?? ExtensionGrants())
        guard row.isEnabled != enabled else { return }
        row.isEnabled = enabled
        try await store.saveExtensionSpace(row)
        installed[id]?.spaces[spaceID] = row
        guard let host = hosts[spaceID] else { return }
        if enabled { await load(id, into: host, grants: row.grants) } else { host.unload(id) }
    }

    /// Replaces the answers for one extension in one Space: a grant, a
    /// revocation, or both. A running context takes them at once.
    public func setGrants(_ grants: ExtensionGrants, extension id: String, inSpace spaceID: UUID) async throws {
        guard installed[id] != nil else { throw ExtensionError.unknownExtension }
        var row = installed[id]?.spaces[spaceID]
            ?? ExtensionSpaceRecord(extensionID: id, spaceID: spaceID, isEnabled: false, grants: grants)
        row.grants = grants
        try await store.saveExtensionSpace(row)
        installed[id]?.spaces[spaceID] = row
        hosts[spaceID]?.apply(grants, to: id)
    }

    /// Unloads and loads again in every Space it runs in — what a developer
    /// wants after editing an unpacked copy, and what recovers a wedged one.
    public func reload(_ id: String) async {
        guard let entry = installed[id] else { return }
        for (space, row) in entry.spaces where row.isEnabled {
            guard let host = hosts[space] else { continue }
            await load(id, into: host, grants: row.grants)
        }
    }

    // MARK: - Plumbing

    private func load(_ id: String, into host: ExtensionHost, grants: ExtensionGrants) async {
        guard let directory = try? library.directory(for: id) else { return }
        do {
            try await host.load(id, from: directory, grants: grants)
        } catch {
            NSLog("Luna: extension %@ did not load in Space %@: %@", id, host.spaceID.uuidString, error.localizedDescription)
        }
    }

    private func remember(_ grants: ExtensionGrants, for id: String, inSpace spaceID: UUID) {
        guard var row = installed[id]?.spaces[spaceID] else { return }
        row.grants = grants
        installed[id]?.spaces[spaceID] = row
        let store = store
        Task { try? await store.saveExtensionSpace(row) }
    }

    private static func details(_ directory: URL) async -> ExtensionDetails? {
        guard let webExtension = try? await WKWebExtension(resourceBaseURL: directory) else { return nil }
        return ExtensionDetails(webExtension, directory: directory)
    }
}
