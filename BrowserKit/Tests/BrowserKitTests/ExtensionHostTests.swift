import Foundation
import Testing
import WebKit
@testable import BrowserKit

/// §16.1 against a real `WKWebExtensionController`: the fixture extension's
/// service worker asks `tabs.query({})` and opens a tab carrying the count, so
/// one URL arriving proves the worker ran, the adapters answered, and
/// `openNewTab` reached the browser.
@Suite("Extension host (§16.1)", .serialized)
@MainActor
struct ExtensionHostTests {

    static let fixture = ExtensionInstallTests.fixtures.appending(path: "FixtureExtension")

    /// WebKit keeps no grants across launches; these are Luna's, applied
    /// before `load`, and a later set replaces them outright.
    @Test func appliesGrantsAndRevokesThem() async throws {
        let context = WKWebExtensionContext(for: try await WKWebExtension(resourceBaseURL: Self.fixture))
        let pattern = try WKWebExtension.MatchPattern(string: "https://example.com/*")

        ExtensionGrants(grantedPermissions: ["storage"], grantedPatterns: ["https://example.com/*"]).apply(to: context)
        #expect(context.permissionStatus(for: .storage) == .grantedExplicitly)
        #expect(context.permissionStatus(for: pattern) == .grantedExplicitly)

        ExtensionGrants(deniedPermissions: ["storage"]).apply(to: context)
        #expect(context.permissionStatus(for: .storage) == .deniedExplicitly)
        #expect(context.permissionStatus(for: pattern) != .grantedExplicitly)
    }

    @Test func installsRunsAndComesBackAfterARelaunch() async throws {
        let (store, spaceID) = try await makeTemporaryStoreWithSpace()
        let library = ExtensionLibrary(root: temporaryDirectory())
        let dataStore = WKWebsiteDataStore(forIdentifier: UUID())
        defer { Self.remove(dataStore) }

        do {
            let browser = FakeBrowser(space: spaceID, tabCount: 2)
            let manager = ExtensionManager(store: store, library: library)
            manager.browser = browser
            _ = manager.controller(forSpace: spaceID, dataStore: dataStore)

            let request = try await manager.prepareInstall(from: Self.fixture)
            // The prompt lists every host pattern, not only the permissions.
            #expect(request.details.permissions.contains("storage"))
            #expect(request.details.hostPatterns == ["https://example.com/*"])
            #expect(!request.isUpdate)
            try await manager.install(request, granting: request.grantingEverything, inSpace: spaceID)

            try await waitUntil { browser.opened.contains { $0.query == "luna-fixture=2" } }
            let info = try #require(manager.extensions.first)
            #expect(info.details?.name == "Luna Fixture")
            #expect(info.enabledSpaces == [spaceID])
            #expect(info.grants[spaceID]?.grantedPermissions == ["storage"])
            manager.tearDown()
        }

        // The next launch: nothing in memory, grants and enablement from the
        // database, and the worker has to start again — the §4 trap is that
        // a registration left from the last run silently keeps it from doing so.
        let browser = FakeBrowser(space: spaceID, tabCount: 3)
        let manager = ExtensionManager(store: store, library: library)
        manager.browser = browser
        await manager.start(spaces: [(spaceID, dataStore)])
        try await waitUntil { browser.opened.contains { $0.query == "luna-fixture=3" } }

        // Uninstalling takes what it stored with it. WebKit keeps listing an
        // emptied record, so it is the size that says so.
        let controller = manager.controller(forSpace: spaceID, dataStore: dataStore)
        let id = try #require(manager.extensions.first?.id)
        func stored() async -> Int {
            await controller.dataRecords(ofTypes: WKWebExtensionController.allExtensionDataTypes)
                .filter { $0.uniqueIdentifier == id }.map(\.totalSizeInBytes).reduce(0, +)
        }
        #expect(await stored() > 0)
        try await manager.uninstall(id)
        #expect(await stored() == 0)
        manager.tearDown()
    }

    /// A new install runs in the Space it was installed from and nowhere else
    /// until the user says so (docs/EXTENSIONS.md §3.1).
    @Test func enablesANewInstallInItsOwnSpaceOnly() async throws {
        let (store, spaceA) = try await makeTemporaryStoreWithSpace()
        let spaceB = try await store.insertSpace(named: "Work")
        let manager = ExtensionManager(store: store, library: ExtensionLibrary(root: temporaryDirectory()))
        let request = try await manager.prepareInstall(from: Self.fixture)
        var refusing = request.grantingEverything
        refusing.grantedPatterns = []
        try await manager.install(request, granting: refusing, inSpace: spaceA)

        let info = try #require(manager.extensions.first)
        #expect(info.enabledSpaces == [spaceA])
        #expect(info.grants[spaceA]?.deniedPatterns == ["https://example.com/*"])

        try await manager.setEnabled(true, extension: request.id, inSpace: spaceB)
        let both = try #require(manager.extensions.first)
        #expect(both.enabledSpaces == [spaceA, spaceB])
        #expect(both.grants[spaceB] == both.grants[spaceA], "enabling elsewhere carries the install's answers")

        try await manager.uninstall(request.id)
        #expect(manager.extensions.isEmpty)
        #expect(try await store.installedExtensions().isEmpty)
    }

    private static func remove(_ dataStore: WKWebsiteDataStore) {
        guard let identifier = dataStore.identifier else { return }
        let background = ExtensionHost.backgroundStoreIdentifier(forSpaceStore: identifier)
        Task { @MainActor in
            for id in [identifier, background] { try? await WKWebsiteDataStore.remove(forIdentifier: id) }
        }
    }
}

@MainActor
private func waitUntil(seconds: Double = 20, _ condition: () -> Bool) async throws {
    let deadline = Date().addingTimeInterval(seconds)
    while !condition() {
        guard Date() < deadline else {
            Issue.record("timed out after \(seconds) s")
            return
        }
        try await Task.sleep(for: .milliseconds(100))
    }
}

/// One window in one Space, holding `tabCount` hibernated tabs.
@MainActor
private final class FakeBrowser: ExtensionBrowser {
    let space: UUID
    let window = UUID()
    var tabs: [Tab]
    var active: UUID?
    var opened: [URL] = []

    init(space: UUID, tabCount: Int) {
        self.space = space
        tabs = (0..<tabCount).map { Tab(spaceID: space, url: URL(string: "https://example.org/\($0)")!) }
        active = tabs.first?.id
    }

    func extensionWindows(inSpace space: UUID) -> (ids: [UUID], focused: UUID?) {
        space == self.space ? ([window], window) : ([], nil)
    }

    func extensionTabs(inSpace space: UUID) -> [Tab] { space == self.space ? tabs : [] }
    func activeTabID(inWindow window: UUID) -> UUID? { active }
    func controller(for id: UUID) -> TabController? { nil }
    func activateTab(_ id: UUID) { active = id }
    func closeTab(_ id: UUID) { tabs.removeAll { $0.id == id } }
    func loadURL(_ url: URL, inTab id: UUID) {}

    func openExtensionTab(url: URL?, inSpace space: UUID, configuration: WKWebViewConfiguration?, activate: Bool) -> UUID? {
        let tab = Tab(spaceID: space, url: url ?? URL(string: "about:blank")!)
        tabs.append(tab)
        if let url { opened.append(url) }
        return tab.id
    }
}
