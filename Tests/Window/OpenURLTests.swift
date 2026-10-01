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

    /// `Info.plist` claims exactly `LocalFileTypes` and `WebLocationFile`:
    /// Finder offers Luna only what it claims, and the open handler takes only
    /// what is on the lists.
    func testInfoPlistClaimsTheListedTypes() throws {
        let types = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "CFBundleDocumentTypes") as? [[String: Any]])
        let claimed = types.flatMap { $0["LSItemContentTypes"] as? [String] ?? [] }
        XCTAssertEqual(Set(claimed), Set(LocalFileTypes.identifiers + WebLocationFile.identifiers))
        XCTAssertTrue(claimed.contains(UTType.html.identifier), "\(claimed)")
    }

    /// The App Store and Finder's Applications view file Luna under this.
    func testInfoPlistNamesTheCategory() {
        XCTAssertEqual(
            Bundle.main.object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String,
            "public.app-category.productivity"
        )
    }

    // MARK: - Saved links

    private var folder: URL!

    override func setUpWithError() throws {
        folder = URL.temporaryDirectory.appending(path: "luna-weblocs-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func write(_ name: String, _ contents: Data) throws -> URL {
        let file = folder.appending(path: name)
        try contents.write(to: file)
        return file
    }

    private func plist(_ link: String, format: PropertyListSerialization.PropertyListFormat) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: ["URL": link], format: format, options: 0)
    }

    /// A `.webloc`, binary or XML — Finder has written both over the years —
    /// opens the address inside it, not the file.
    func testAWeblocOpensTheAddressItHolds() throws {
        let binary = try write("Example.webloc", plist("https://example.com/page?q=1", format: .binary))
        let xml = try write("Other.webloc", plist("http://example.org/", format: .xml))
        XCTAssertEqual(AppDelegate.pages(in: [binary, xml]), [url("https://example.com/page?q=1"), url("http://example.org/")])
    }

    func testAnInetlocAndAWindowsShortcutOpenTheirAddresses() throws {
        let inetloc = try write("Old.inetloc", plist("https://example.net/", format: .xml))
        let shortcut = try write(
            "Shortcut.url",
            Data("[DEFAULT]\r\nBASEURL=https://wrong.example/\r\n[InternetShortcut]\r\nURL=https://example.com/win\r\nIconIndex=0\r\n".utf8)
        )
        XCTAssertEqual(AppDelegate.pages(in: [inetloc, shortcut]), [url("https://example.net/"), url("https://example.com/win")])
    }

    /// A saved link to anything but the web, or a file that is not one at
    /// all, opens nothing.
    func testASavedLinkOffTheWebOpensNothing() throws {
        let mail = try write("Mail.inetloc", plist("mailto:someone@example.com", format: .xml))
        let local = try write("Local.webloc", plist("file:///etc/hosts", format: .xml))
        let script = try write("Script.webloc", plist("javascript:alert(1)", format: .binary))
        let broken = try write("Broken.webloc", Data("not a property list".utf8))
        let missing = folder.appending(path: "Missing.webloc")
        XCTAssertEqual(AppDelegate.pages(in: [mail, local, script, broken, missing]), [])
    }

    func testRecognisesSavedLinksByExtension() {
        XCTAssertTrue(WebLocationFile.handles(url("file:///Users/someone/Example.webloc")))
        XCTAssertTrue(WebLocationFile.handles(url("file:///Users/someone/Example.inetloc")))
        XCTAssertTrue(WebLocationFile.handles(url("file:///Users/someone/Example.url")))
        XCTAssertFalse(WebLocationFile.handles(url("file:///Users/someone/page.html")))
        XCTAssertFalse(WebLocationFile.handles(url("https://example.com/a.webloc")))
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
