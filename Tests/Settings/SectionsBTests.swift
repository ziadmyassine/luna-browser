//
//  SectionsBTests.swift
//  LunaTests
//
//  The four things in §3.3/§3.5/§3.7/§3.9 that are decisions rather than
//  drawing, and would each fail silently:
//
//    · the Default user agent, which must stay byte-for-byte what §4.6 measured;
//    · what WebKit's own UA prefix actually is, re-measured from a live web view
//      rather than trusted, because `.safari` and `.chrome` are built on it;
//    · where a download lands when the chosen folder is gone or unwritable.
//
//  §2's search is `SettingsBody.filter`, which agent B owns and tests.
//

import BrowserKit
import WebKit
import XCTest
@testable import Luna

@MainActor
final class UserAgentTests: XCTestCase {

    /// These write the very keys the running app reads, so every one of them
    /// is put back exactly as it was found.
    private var saved: [String: Any?] = [:]

    override func setUp() {
        super.setUp()
        let keys = [WebViewFactory.Key.userAgent, WebViewFactory.Key.customUserAgent, WebViewFactory.Key.webInspector]
        saved = Dictionary(uniqueKeysWithValues: keys.map { ($0, UserDefaults.standard.object(forKey: $0)) })
        for key in keys { UserDefaults.standard.removeObject(forKey: key) }
    }

    override func tearDown() {
        for (key, value) in saved { UserDefaults.standard.set(value, forKey: key) }
        super.tearDown()
    }

    /// The constraint the whole user-agent row is built around:
    /// `applicationNameForUserAgent` appends, so Default is the mode that
    /// changes nothing. If this string moves, every site that sniffs for Safari
    /// sees a different browser.
    func testDefaultModeAppendsTheSafariTokensAndNothingElse() {
        XCTAssertEqual(WebViewFactory.userAgentMode, .default)
        XCTAssertNil(
            WebViewFactory.customUserAgent(for: .default),
            "Default must leave customUserAgent nil or the appended string is thrown away"
        )
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        XCTAssertEqual(WebViewFactory.applicationNameForUserAgent, "Version/26.0 Safari/605.1.15 Luna/\(version)")
    }

    func testImpersonatingModesReplaceTheWholeUserAgent() {
        let safari = WebViewFactory.customUserAgent(for: .safari)
        XCTAssertEqual(safari, "\(WebViewFactory.webKitBase) Version/26.0 Safari/605.1.15")
        XCTAssertFalse(safari?.contains("Luna/") ?? true, "Safari mode must not leak Luna's own token")

        let chrome = WebViewFactory.customUserAgent(for: .chrome)
        XCTAssertEqual(chrome?.contains("Chrome/"), true)
        XCTAssertEqual(chrome?.contains("Luna/"), false)
    }

    /// A Custom mode with nothing typed into it must behave as Default, not
    /// send an empty UA header.
    func testEmptyCustomFallsBackToTheAppendedDefault() {
        WebViewFactory.customUserAgentString = "   "
        XCTAssertNil(WebViewFactory.customUserAgent(for: .custom))
        WebViewFactory.customUserAgentString = "Luna/test"
        XCTAssertEqual(WebViewFactory.customUserAgent(for: .custom), "Luna/test")
    }

    func testModeAndInspectorRoundTripThroughDefaults() {
        WebViewFactory.userAgentMode = .chrome
        XCTAssertEqual(UserDefaults.standard.string(forKey: WebViewFactory.Key.userAgent), "chrome")
        XCTAssertEqual(WebViewFactory.userAgentMode, .chrome)

        // Defaults to on: every Luna web view was inspectable before it was a setting.
        XCTAssertTrue(WebViewFactory.isWebInspectorEnabled)
        WebViewFactory.isWebInspectorEnabled = false
        XCTAssertFalse(WebViewFactory.isWebInspectorEnabled)
    }

    /// Re-measures the one constant here that is copied rather than derived. A
    /// WebKit update that changes the default UA prefix makes `.safari` a
    /// string no Safari has ever sent, and nothing else would catch it.
    func testWebKitBasePrefixIsStillWhatWeThinkItIs() async throws {
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        webView.configuration.websiteDataStore = .nonPersistent()
        webView.load(URLRequest(url: URL(string: "about:blank")!))
        let reported = try await webView.evaluateJavaScript("navigator.userAgent") as? String
        let agent = try XCTUnwrap(reported)
        XCTAssertTrue(
            agent.hasPrefix(WebViewFactory.webKitBase),
            "WebKit now reports \(agent) — update WebViewFactory.webKitBase and the Safari mode built on it"
        )
    }
}

@MainActor
final class DownloadsSettingTests: XCTestCase {

    private var saved: String?

    override func setUp() {
        super.setUp()
        saved = UserDefaults.standard.string(forKey: DownloadDestination.directoryKey)
    }

    override func tearDown() {
        UserDefaults.standard.set(saved, forKey: DownloadDestination.directoryKey)
        super.tearDown()
    }

    /// Luna is unsandboxed (D8) so there is no bookmark to resolve — the check
    /// that replaces one is writing a file, because the mode bits lie about TCC.
    func testIsWritableWritesRatherThanAsking() throws {
        let temporary = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }

        XCTAssertTrue(DownloadDestination.isWritable(temporary))
        XCTAssertFalse(DownloadDestination.isWritable(temporary.appending(path: "gone", directoryHint: .isDirectory)))

        // A file is not a folder, however writable it is.
        let file = temporary.appending(path: "a.txt", directoryHint: .notDirectory)
        XCTAssertTrue(FileManager.default.createFile(atPath: file.path(percentEncoded: false), contents: nil))
        XCTAssertFalse(DownloadDestination.isWritable(file))

        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: temporary.path)
        XCTAssertFalse(DownloadDestination.isWritable(temporary), "a read-only folder must not be offered")
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: temporary.path)
    }

    func testFolderUsesTheSettingAndFallsBackWhenItIsGone() throws {
        let temporary = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }

        UserDefaults.standard.set(temporary.path(percentEncoded: false), forKey: DownloadDestination.directoryKey)
        XCTAssertEqual(
            DownloadDestination.folder.standardizedFileURL.path(percentEncoded: false),
            temporary.standardizedFileURL.path(percentEncoded: false)
        )

        // An ejected volume or a deleted folder must not fail the download.
        UserDefaults.standard.set("/Volumes/definitely-not-mounted-\(UUID().uuidString)", forKey: DownloadDestination.directoryKey)
        XCTAssertEqual(DownloadDestination.folder, DownloadDestination.systemDownloads)

        UserDefaults.standard.removeObject(forKey: DownloadDestination.directoryKey)
        XCTAssertEqual(DownloadDestination.folder, DownloadDestination.systemDownloads)
    }

    /// §3.5's whole point. `bool(forKey:)` on an unset key is false, so the
    /// default is off without anyone having to remember to register it.
    func testAutoOpenIsOffUntilItIsTurnedOn() {
        let key = DownloadDestination.autoOpenKey
        let previous = UserDefaults.standard.object(forKey: key)
        defer { UserDefaults.standard.set(previous, forKey: key) }
        UserDefaults.standard.removeObject(forKey: key)
        XCTAssertFalse(UserDefaults.standard.bool(forKey: key))
    }

    /// §3.5's "Ask where to save each file": off goes straight to the folder
    /// without asking, on asks starting in the folder and then in the last
    /// folder chosen, and a cancelled panel is no destination at all — which
    /// is what WebKit takes as cancelling the download before a byte lands.
    func testAskingEachTimeDecidesTheDestination() async throws {
        let keys = [DownloadDestination.askKey, DownloadDestination.lastAskedKey]
        let previous = keys.map { UserDefaults.standard.object(forKey: $0) }
        defer { for (key, value) in zip(keys, previous) { UserDefaults.standard.set(value, forKey: key) } }
        keys.forEach(UserDefaults.standard.removeObject(forKey:))

        let elsewhere = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: elsewhere) }
        // Not `~/Downloads`: reading it from the test host asks TCC.
        let downloads = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: downloads) }
        UserDefaults.standard.set(downloads.path(percentEncoded: false), forKey: DownloadDestination.directoryKey)

        var asked: [(name: String, folder: URL)] = []
        var answer: URL?
        let ask: (String, URL) async -> URL? = { name, folder in
            asked.append((name, folder))
            return answer
        }

        // Off: the folder, unasked.
        let straight = await DownloadDestination.decide("moon.pdf", ask: ask)
        XCTAssertEqual(straight?.deletingLastPathComponent().standardizedFileURL, DownloadDestination.folder.standardizedFileURL)
        XCTAssertTrue(asked.isEmpty)

        // On: asked with the suggested name, starting in the folder.
        UserDefaults.standard.set(true, forKey: DownloadDestination.askKey)
        answer = elsewhere.appending(path: "renamed.pdf", directoryHint: .notDirectory)
        let chosen = await DownloadDestination.decide("moon.pdf", ask: ask)
        XCTAssertEqual(chosen, answer)
        XCTAssertEqual(asked.last?.name, "moon.pdf")
        XCTAssertEqual(asked.last?.folder.standardizedFileURL, DownloadDestination.folder.standardizedFileURL)

        // Cancelled: no destination, and the next ask starts where the last one ended.
        answer = nil
        let cancelled = await DownloadDestination.decide("sun.pdf", ask: ask)
        XCTAssertNil(cancelled)
        XCTAssertEqual(asked.last?.folder.standardizedFileURL, elsewhere.standardizedFileURL)
    }

    /// The panel has already asked whether to replace the file, and WebKit
    /// refuses a destination that exists, so the old file goes first.
    func testReplacingAnExistingFileMovesItOutOfTheWay() async throws {
        let previous = UserDefaults.standard.object(forKey: DownloadDestination.askKey)
        defer { UserDefaults.standard.set(previous, forKey: DownloadDestination.askKey) }
        UserDefaults.standard.set(true, forKey: DownloadDestination.askKey)

        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let existing = folder.appending(path: "moon.pdf", directoryHint: .notDirectory)
        XCTAssertTrue(FileManager.default.createFile(atPath: existing.path(percentEncoded: false), contents: Data("old".utf8)))

        let chosen = await DownloadDestination.decide("moon.pdf") { _, _ in existing }
        XCTAssertEqual(chosen, existing)
        XCTAssertFalse(FileManager.default.fileExists(atPath: existing.path(percentEncoded: false)))
    }
}
