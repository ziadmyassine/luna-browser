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
    /// `applicationNameForUserAgent` **appends**, so Default is the mode that
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
}
