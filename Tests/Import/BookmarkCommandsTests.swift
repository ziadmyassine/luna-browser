//
//  BookmarkCommandsTests.swift
//  LunaTests
//
//  §11.4: File ▸ Import Bookmarks… and Export Bookmarks…, the Netscape HTML
//  importer and exporter from the menu bar. The panels are the only part not
//  run here; each command's work past the panel takes the URL the panel would
//  have returned.
//
//  The app delegate is a fresh one with a window of its own, never the test
//  host's, and nothing here is put on screen.
//

import AppKit
@testable import BrowserKit
import XCTest
@testable import Luna

@MainActor
final class BookmarkCommandsTests: XCTestCase {

    private var directory: URL!
    private var session: BrowserSession!
    private var delegate: AppDelegate!
    private var window: BrowserWindow!

    override func setUp() async throws {
        directory = URL.temporaryDirectory.appending(path: "luna-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        session = try await BrowserSession.restored(store: BrowserStore(path: directory.appending(path: "luna.sqlite")))
        window = BrowserWindow(session: session, controller: BrowserWindowController(remembersFrame: false))
        session.setKeyWindow(window.id)
        delegate = AppDelegate()
        delegate.windows = [window]
        delegate.front = window
    }

    override func tearDown() async throws {
        window.controller.close()
        session.tearDown()
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - Listed

    func testBothAreInTheTableTheCommandBarAndTheFileMenu() throws {
        MainMenu.rebuild(in: NSApplication.shared)
        let file = try XCTUnwrap(NSApp.mainMenu?.items.first { $0.title == "File" }?.submenu)
        for command in [BrowserCommand.importBookmarks, .exportBookmarks] {
            XCTAssertNotNil(BrowserCommand.command(id: command.id), command.id)
            XCTAssertTrue(command.isCustomisable, "\(command.id) cannot be given a key in Settings")
            XCTAssertNotNil(command.symbolName, "\(command.id) is left out of the Command Bar")
            XCTAssertNotNil(file.items.first { $0.action == command.action }, "File has no \(command.title)")
        }
    }

    /// A private window's store is thrown away with it: an import there would
    /// vanish, and an export would hold none of the user's bookmarks.
    func testBothDimInAPrivateWindow() async throws {
        let item = NSMenuItem(title: "", action: BrowserCommand.importBookmarks.action, keyEquivalent: "")
        XCTAssertTrue(delegate.validateMenuItem(item))

        let home = directory.appending(path: "private")
        let hidden = try await BrowserSession.restored(
            store: BrowserStore(path: home.appending(path: "luna.sqlite")), isPrivate: true
        )
        let privateWindow = BrowserWindow(session: hidden, controller: BrowserWindowController(remembersFrame: false))
        delegate.front = privateWindow
        defer {
            privateWindow.controller.close()
            hidden.tearDown()
        }
        XCTAssertFalse(delegate.validateMenuItem(item))
        item.action = BrowserCommand.exportBookmarks.action
        XCTAssertFalse(delegate.validateMenuItem(item))
    }

    // MARK: - Import

    func testImportLandsInTheSidebarAndSaysHowMany() async throws {
        let file = directory.appending(path: "Safari Bookmarks.html")
        try """
        <!DOCTYPE NETSCAPE-Bookmark-file-1>
        <DL><p>
            <DT><A HREF="https://a.example/">A</A>
            <DT><H3>Reading</H3>
            <DL><p>
                <DT><A HREF="https://b.example/">B</A>
            </DL><p>
        </DL><p>
        """.write(to: file, atomically: true, encoding: .utf8)

        let toast = await delegate.importBookmarks(from: file, into: session)

        XCTAssertEqual(toast, .bookmarksImported(2, into: "Safari Bookmarks"))
        let space = try XCTUnwrap(session.spaces.first { $0.name == "Safari Bookmarks" }, "the session never adopted the import")
        let hosts = Set(session.allTabs(includeArchived: false).filter { $0.spaceID == space.id }.compactMap { $0.url.host() })
        XCTAssertEqual(hosts, ["a.example", "b.example"])
    }

    func testAFileWithNoBookmarksIsRefused() async throws {
        let file = directory.appending(path: "notes.html")
        try "<html><body>no bookmarks here</body></html>".write(to: file, atomically: true, encoding: .utf8)

        let toast = await delegate.importBookmarks(from: file, into: session)

        XCTAssertEqual(toast, .bookmarksNotImported("notes.html"))
    }

    // MARK: - Export

    func testExportWritesAFileTheImporterReadsBack() async throws {
        let space = try XCTUnwrap(session.spaces.first)
        try await session.store.upsert(Tab(
            spaceID: space.id, kind: .pinned, url: URL(string: "https://c.example/")!, title: "C", order: 0
        ))
        let file = directory.appending(path: "Luna Bookmarks.html")

        let toast = await delegate.exportBookmarks(to: file, from: session)

        XCTAssertEqual(toast, .bookmarksExported("Luna Bookmarks.html"))
        let html = try String(contentsOf: file, encoding: .utf8)
        XCTAssertTrue(NetscapeBookmarks.parse(html).contains { $0.url.host() == "c.example" })
    }
}
