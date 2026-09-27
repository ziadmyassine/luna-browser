//
//  OpenURLTests.swift
//  LunaTests
//
//  A web link or an HTML file handed to Luna by another app. The two halves that are
//  decisions: which links Luna takes, and what happens to one that arrives
//  before there is a window to open it in.
//

import UniformTypeIdentifiers
import XCTest
@testable import Luna

@MainActor
final class OpenURLTests: XCTestCase {

    private func url(_ text: String) -> URL { URL(string: text)! }

    /// Only what `Info.plist` claims: web links, and files WebKit can show.
    func testTakesWebLinksAndFilesItCanShowAndNothingElse() {
        let links = [
            url("https://example.com/"),
            url("HTTP://example.org/page"),
            url("mailto:someone@example.com"),
            url("file:///Users/someone/page.html"),
            url("file:///Users/someone/page.htm"),
            url("file:///Users/someone/notes.txt"),
            url("file:///Users/someone/photo.png"),
            url("file:///Users/someone/report.pdf"),
            url("file:///Users/someone/README.md"),
            url("file:///Users/someone/data.json"),
            url("file:///Users/someone/script.py"),
            url("file:///Users/someone/clip.mp4"),
            url("file:///Users/someone/song.mp3"),
            url("file:///Users/someone/design.psd"),
            url("file:///Users/someone/letter.rtf"),
            url("file:///Users/someone/Luna.app"),
            url("ftp://example.net/")
        ]
        let refused = ["mailto:", "design.psd", "letter.rtf", "Luna.app", "ftp:"]
        XCTAssertEqual(
            AppDelegate.pages(in: links),
            links.filter { link in !refused.contains { link.absoluteString.contains($0) } }
        )
    }

    /// `Info.plist` claims exactly `LocalFileTypes`: Finder offers Luna only
    /// what it claims, and the open handler takes only what is on the list.
    func testInfoPlistClaimsTheListedTypes() throws {
        let types = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "CFBundleDocumentTypes") as? [[String: Any]])
        let claimed = types.flatMap { $0["LSItemContentTypes"] as? [String] ?? [] }
        XCTAssertEqual(Set(claimed), Set(LocalFileTypes.identifiers))
        XCTAssertTrue(claimed.contains(UTType.html.identifier), "\(claimed)")
    }

    /// With no other Luna running, a launch to open a page is this Luna's own.
    func testNoHandOffWithoutAnotherLuna() {
        let delegate = AppDelegate()
        delegate.application(NSApplication.shared, open: [url("https://example.com/")])
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .filter { $0 != .current }
        guard others.isEmpty else { return }
        XCTAssertFalse(delegate.handOffToRunningLuna())
    }

    /// A link that launched Luna waits for the window instead of being lost.
    func testALinkBeforeLaunchIsKeptForTheWindow() {
        let delegate = AppDelegate()
        delegate.application(NSApplication.shared, open: [url("https://example.com/")])
        delegate.application(NSApplication.shared, open: [url("mailto:someone@example.com")])
        delegate.application(NSApplication.shared, open: [url("https://example.org/")])
        XCTAssertEqual(delegate.linksBeforeLaunch, [url("https://example.com/"), url("https://example.org/")])
    }

    /// Once launch has taken them, nothing is kept back for later: a link
    /// from then on opens straight away.
    func testLaunchTakesTheKeptLinksOnce() {
        let delegate = AppDelegate()
        delegate.application(NSApplication.shared, open: [url("https://example.com/")])
        delegate.openLinksFromLaunch()
        XCTAssertNil(delegate.linksBeforeLaunch)
    }
}
