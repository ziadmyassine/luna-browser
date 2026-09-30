import Foundation
import Testing
import WebKit
@testable import BrowserKit

/// The shim (docs/EXTENSIONS.md §9) and native messaging (§5), against a real
/// `WKWebExtensionController`. The probe's worker calls APIs WebKit lacks and
/// a native host that echoes, and reports each answer by opening a tab whose
/// address carries it.
@Suite("Extension shim and native messaging", .serialized)
@MainActor
struct ExtensionShimTests {

    // MARK: - Writing the shim in

    @Test func preparingAddsTheShimAndRecordsWhatItAdded() throws {
        let folder = try Self.write(manifest: Self.plainManifest, background: "self.ran = true;")
        try ExtensionShim.prepare(folder)

        let written = try Data(contentsOf: folder.appending(path: "manifest.json"))
        let manifest = try #require(try JSONSerialization.jsonObject(with: written) as? [String: Any])
        #expect((manifest["permissions"] as? [String])?.contains("nativeMessaging") == true)
        #expect(ExtensionShim.addedPermissions(in: folder) == ["nativeMessaging"], "the extension never asked for it")
        let worker = try String(contentsOf: folder.appending(path: "background.js"), encoding: .utf8)
        #expect(worker.hasPrefix(ExtensionShim.marker))
        #expect(worker.hasSuffix("self.ran = true;"), "the extension's own code is kept, after the shim")
        #expect(FileManager.default.fileExists(atPath: folder.appending(path: ExtensionShim.file).path))

        // A second pass with the same shim changes nothing: the worker carries one copy.
        try ExtensionShim.prepare(folder)
        let again = try String(contentsOf: folder.appending(path: "background.js"), encoding: .utf8)
        #expect(again == worker)
    }

    @Test func whatLunaAddedIsNotWhatTheExtensionAsksFor() async throws {
        let folder = try Self.write(manifest: Self.plainManifest, background: "")
        try ExtensionShim.prepare(folder)
        let details = ExtensionDetails(try await WKWebExtension(resourceBaseURL: folder), directory: folder)
        #expect(!details.permissions.contains("nativeMessaging"))
        #expect(details.permissions.contains("storage"))
    }

    @Test func aPackageCannotBringItsOwnRecordOfWhatLunaAdded() async throws {
        let folder = try Self.write(manifest: Self.plainManifest, background: "")
        try Data(#"["tabs"]"#.utf8).write(to: folder.appending(path: ExtensionShim.added))
        let staged = try await ExtensionLibrary(root: temporaryDirectory()).stage(folder)
        #expect(ExtensionShim.addedPermissions(in: staged.directory).isEmpty)
    }

    // MARK: - Native hosts

    @Test func aHostRunsOnlyForTheExtensionsItAllows() async throws {
        let hosts = temporaryDirectory()
        let allowed = String(repeating: "a", count: 32)
        try Self.installEchoHost(in: hosts, allowing: allowed)
        let native = ExtensionNative(folders: [hosts])

        #expect(throws: ExtensionNative.Refused.self) { try native.host(Self.hostName, for: String(repeating: "b", count: 32)) }
        #expect(throws: ExtensionNative.Refused.self) { try native.host("../escape", for: allowed) }
        #expect(throws: ExtensionNative.Refused.self) { try native.host("com.luna.absent", for: allowed) }

        let reply = try await native.send(["word": "ping"], to: Self.hostName, from: allowed) as? [String: Any]
        #expect(reply?["word"] as? String == "ping")
    }

    // MARK: - End to end

    @Test func aWorkerReachesTheShimAndAnAppOnThisMac() async throws {
        let (store, spaceID) = try await makeTemporaryStoreWithSpace()
        let root = temporaryDirectory()
        let library = ExtensionLibrary(root: root.appending(path: "Extensions"))
        let dataStore = WKWebsiteDataStore(forIdentifier: UUID())
        defer { Self.remove(dataStore) }
        let browser = ShimProbeBrowser(space: spaceID)
        let manager = ExtensionManager(store: store, library: library)
        manager.browser = browser
        _ = manager.controller(forSpace: spaceID, dataStore: dataStore)

        let probe = try Self.write(manifest: Self.probeManifest, background: Self.probeWorker)
        let request = try await manager.prepareInstall(from: probe)
        try Self.installEchoHost(in: library.nativeHostsFolder, allowing: request.id)
        try await manager.install(request, granting: request.grantingEverything, inSpace: spaceID)

        let reported = { (key: String) in browser.reports[key] }
        try await waitUntil { ["self", "idle", "history", "echo"].allSatisfy { reported($0) != nil } }
        #expect(reported("self") == "Luna Shim Probe", "management.getSelf is the shim's, answered by Luna")
        #expect(["active", "idle", "locked"].contains(reported("idle") ?? ""))
        #expect(reported("history") == "refused", "history is gated on the manifest, which did not ask for it")
        #expect(reported("echo") == "hello", "the message went to the host and its answer came back over the port")
        manager.tearDown()
    }

    /// A worker has no DOM; the page it asks for has one, and talks back to it.
    @Test func anOffscreenDocumentGivesTheWorkerADOM() async throws {
        let (store, spaceID) = try await makeTemporaryStoreWithSpace()
        let library = ExtensionLibrary(root: temporaryDirectory().appending(path: "Extensions"))
        let dataStore = WKWebsiteDataStore(forIdentifier: UUID())
        defer { Self.remove(dataStore) }
        let browser = ShimProbeBrowser(space: spaceID)
        let manager = ExtensionManager(store: store, library: library)
        manager.browser = browser
        _ = manager.controller(forSpace: spaceID, dataStore: dataStore)

        let folder = try Self.write(manifest: Self.offscreenManifest, background: Self.offscreenWorker, extra: [
            "offscreen.html": #"<!doctype html><script src="offscreen.js"></script>"#,
            "offscreen.js": """
            const parsed = new DOMParser().parseFromString("<b>bold</b>", "text/html");
            chrome.runtime.sendMessage({ parsed: parsed.querySelector("b").textContent });
            """
        ])
        let request = try await manager.prepareInstall(from: folder)
        try await manager.install(request, granting: request.grantingEverything, inSpace: spaceID)

        try await waitUntil { browser.reports["has"] != nil && browser.reports["parsed"] != nil }
        #expect(browser.reports["has"] == "true")
        #expect(browser.reports["parsed"] == "bold", "the document parsed HTML and its message reached the worker")
        manager.tearDown()
    }

    /// The provider's page opens in a tab; its redirect to the extension's
    /// chromiumapp.org address is the answer, from that tab and no other.
    @Test func aSignInEndsWhereItBeganAndNowhereElse() async throws {
        let space = UUID()
        let browser = ShimProbeBrowser(space: space)
        let id = String(repeating: "c", count: 32)
        let answer = URL(string: "https://\(id).chromiumapp.org/done?code=42")!
        let flow = Task {
            try await ExtensionAuthFlows.run(URL(string: "https://example.com/sign-in")!, extensionID: id, inSpace: space, browser: browser)
        }
        try await waitUntil { browser.tabs.count == 2 }
        let signIn = try #require(browser.tabs.last?.id)
        #expect(!ExtensionAuthFlows.finish(answer, fromTab: try #require(browser.tabs.first?.id)), "another tab can't answer")
        #expect(ExtensionAuthFlows.finish(answer, fromTab: signIn))
        #expect(try await flow.value == answer)
        #expect(!browser.tabs.contains { $0.id == signIn }, "the sign-in tab goes with the answer")

        let abandoned = Task {
            try await ExtensionAuthFlows.run(URL(string: "https://example.com/sign-in")!, extensionID: id, inSpace: space, browser: browser)
        }
        try await waitUntil { browser.tabs.count == 2 }
        browser.closeTab(try #require(browser.tabs.last?.id))
        await #expect(throws: ExtensionAuthFlows.Declined.self) { try await abandoned.value }
    }

    // MARK: - Fixtures

    static let hostName = "com.luna.test_echo"

    static let plainManifest = """
    {
      "manifest_version": 3,
      "name": "Luna Shim Plain",
      "version": "1.0",
      "background": { "service_worker": "background.js" },
      "permissions": ["storage"]
    }
    """

    static let offscreenManifest = """
    {
      "manifest_version": 3,
      "name": "Luna Offscreen Probe",
      "version": "1.0",
      "background": { "service_worker": "background.js" },
      "permissions": ["offscreen"],
      "host_permissions": ["https://example.com/*"]
    }
    """

    static let offscreenWorker = """
    const report = (key, value) => chrome.tabs.create({ url: "https://example.com/?" + key + "=" + encodeURIComponent(value) });
    chrome.runtime.onMessage.addListener((m) => { if (m && m.parsed) report("parsed", m.parsed); });
    chrome.offscreen.createDocument({ url: "offscreen.html", reasons: ["DOM_PARSER"], justification: "test" })
      .then(() => chrome.offscreen.hasDocument())
      .then((has) => report("has", has), (e) => report("has", "error: " + e.message));
    """

    static let probeManifest = """
    {
      "manifest_version": 3,
      "name": "Luna Shim Probe",
      "version": "1.0",
      "background": { "service_worker": "background.js" },
      "permissions": ["storage", "nativeMessaging", "idle"],
      "host_permissions": ["https://example.com/*"]
    }
    """

    static let probeWorker = """
    const report = (key, value) => chrome.tabs.create({ url: "https://example.com/?" + key + "=" + encodeURIComponent(value) });
    chrome.management.getSelf().then((self) => report("self", self.name), (e) => report("self", "error: " + e.message));
    chrome.idle.queryState(60).then((state) => report("idle", state), (e) => report("idle", "error: " + e.message));
    chrome.history.search({ text: "" }).then(() => report("history", "allowed"), () => report("history", "refused"));
    const port = chrome.runtime.connectNative("\(hostName)");
    port.onMessage.addListener((m) => report("echo", m.word));
    port.postMessage({ word: "hello" });
    """

    /// Reads a four-byte length and that much JSON, and writes both back.
    /// Perl, because it is on every Mac the tests run on.
    static let echoHost = """
    #!/usr/bin/perl
    binmode STDIN; binmode STDOUT; $| = 1;
    while (read(STDIN, my $length, 4) == 4) {
      my $size = unpack("V", $length);
      read(STDIN, my $body, $size);
      print $length . $body;
    }
    """

    static func write(manifest: String, background: String, extra: [String: String] = [:]) throws -> URL {
        let folder = temporaryDirectory().appending(path: "Probe")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(manifest.utf8).write(to: folder.appending(path: "manifest.json"))
        try Data(background.utf8).write(to: folder.appending(path: "background.js"))
        for (name, text) in extra { try Data(text.utf8).write(to: folder.appending(path: name)) }
        return folder
    }

    static func installEchoHost(in folder: URL, allowing id: String) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let program = folder.appending(path: "echo.pl")
        try Data(echoHost.utf8).write(to: program)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: program.path)
        let manifest: [String: Any] = [
            "name": hostName, "description": "Echo", "path": program.path, "type": "stdio",
            "allowed_origins": [ExtensionNative.origin(of: id)]
        ]
        try JSONSerialization.data(withJSONObject: manifest).write(to: folder.appending(path: hostName + ".json"))
    }

    private static func remove(_ dataStore: WKWebsiteDataStore) {
        guard let identifier = dataStore.identifier else { return }
        let background = ExtensionHost.backgroundStoreIdentifier(forSpaceStore: identifier)
        Task { @MainActor in
            for id in [identifier, background] { try? await WKWebsiteDataStore.remove(forIdentifier: id) }
        }
    }

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
}

/// One window in one Space with one tab, keeping what the probe reports.
@MainActor
private final class ShimProbeBrowser: ExtensionBrowser {
    let space: UUID
    let window = UUID()
    var tabs: [Tab]
    var reports: [String: String] = [:]

    init(space: UUID) {
        self.space = space
        tabs = [Tab(spaceID: space, url: URL(string: "https://example.org/")!)]
    }

    func extensionWindows(inSpace space: UUID) -> (ids: [UUID], focused: UUID?) {
        space == self.space ? ([window], window) : ([], nil)
    }

    func extensionTabs(inSpace space: UUID) -> [Tab] { space == self.space ? tabs : [] }
    func activeTabID(inWindow window: UUID) -> UUID? { tabs.first?.id }
    func controller(for id: UUID) -> TabController? { nil }
    func activateTab(_ id: UUID) {}
    func closeTab(_ id: UUID) { tabs.removeAll { $0.id == id } }
    func loadURL(_ url: URL, inTab id: UUID) {}

    func openExtensionTab(url: URL?, inSpace space: UUID, configuration: WKWebViewConfiguration?, activate: Bool) -> UUID? {
        let tab = Tab(spaceID: space, url: url ?? URL(string: "about:blank")!)
        tabs.append(tab)
        for item in URLComponents(url: tab.url, resolvingAgainstBaseURL: false)?.queryItems ?? [] {
            reports[item.name] = item.value
        }
        return tab.id
    }
}
