//
//  HistoryPanelTests.swift
//  LunaTests
//
//  §6.4's panel as the user meets it: the pages the Space visited, newest
//  first, found by any word of their address, and a chosen one opened —
//  in the tab that already has it, if one does.
//
//  The report this exists for: a repository visited nine times, searched for
//  by its owner's name, and not in the panel, because the panel listed closed
//  tabs and the repository had only ever been open.
//

import BrowserKit
import XCTest
@testable import Luna

@MainActor
final class HistoryPanelTests: XCTestCase {

    private let directory = URL.temporaryDirectory.appending(path: "luna-tests-\(UUID().uuidString)")

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func url(_ text: String) -> URL { URL(string: text)! }

    /// A session whose Space has visited `pages`, oldest first.
    private func session(visiting pages: [(String, String)]) async throws -> BrowserSession {
        let session = try await BrowserSession.restored(store: BrowserStore(path: directory.appending(path: "luna.sqlite")))
        for (index, (address, title)) in pages.enumerated() {
            try await session.store.recordVisit(
                url: url(address), title: title, kind: .link,
                at: Date().addingTimeInterval(Double(index - pages.count) * 60),
                inSpace: session.activeSpaceID
            )
        }
        return session
    }

    private func window() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.contentView = NSView(frame: window.contentLayoutRect)
        return window
    }

    /// The titles in the list once the store has answered. Read off the list
    /// rather than its row views: a window that is not on screen never runs
    /// the pop-out's growth, so it has no room to draw a row in.
    private func shownTitles(in history: HistoryPanelController) async throws -> [String] {
        let panel = try XCTUnwrap(history.presented as? HistoryPanel)
        let start = Date()
        while panel.shownEntries.isEmpty, Date().timeIntervalSince(start) < 2 {
            try await Task.sleep(for: .milliseconds(5))
        }
        return panel.shownEntries.map(\.title)
    }

    func testItListsTheVisitedPagesNewestFirst() async throws {
        let session = try await session(visiting: [
            ("https://github.com/driceroland/Search", "driceroland/Search"),
            ("https://swift.org/blog", "Swift Blog")
        ])
        let window = window()
        let history = HistoryPanelController(session: session)
        history.present(in: window, from: try XCTUnwrap(window.contentView))
        let titles = try await shownTitles(in: history)
        XCTAssertEqual(titles, ["Swift Blog", "driceroland/Search"])
        history.dismiss()
        session.tearDown()
    }

    /// The reported case: a word only the address carries.
    func testSearchingFindsAPageByAWordInItsAddress() async throws {
        let session = try await session(visiting: [
            ("https://github.com/driceroland/Search", "A small, fast WebKit browser"),
            ("https://swift.org/blog", "Swift Blog")
        ])
        let window = window()
        let history = HistoryPanelController(session: session)
        history.present(in: window, from: try XCTUnwrap(window.contentView))
        let panel = try XCTUnwrap(history.presented as? HistoryPanel)
        _ = try await shownTitles(in: history)
        panel.onFilter?("driceroland")
        let start = Date()
        while panel.shownEntries.count != 1, Date().timeIntervalSince(start) < 2 {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertEqual(panel.shownEntries.map(\.title), ["A small, fast WebKit browser"])
        history.dismiss()
        session.tearDown()
    }

    /// Choosing a page that is already open goes to its tab rather than
    /// opening a second copy of it.
    func testChoosingAnOpenPageSwitchesToItsTab() async throws {
        let repo = url("https://github.com/driceroland/Search")
        let session = try await session(visiting: [(repo.absoluteString, "driceroland/Search")])
        let open = session.newTab(url: repo)
        session.newTab(url: url("https://swift.org/blog"))
        let count = session.tabsInActiveSpace(includeArchived: false).count
        let window = window()
        let history = HistoryPanelController(session: session)
        history.present(in: window, from: try XCTUnwrap(window.contentView))
        let panel = try XCTUnwrap(history.presented as? HistoryPanel)
        panel.onChoose?(entry(repo))
        XCTAssertEqual(session.activeTabID, open)
        XCTAssertEqual(session.tabsInActiveSpace(includeArchived: false).count, count, "a second copy was opened")
        session.tearDown()
    }

    func testChoosingAPageWithNoTabOpensOne() async throws {
        let blog = url("https://swift.org/blog")
        let session = try await session(visiting: [(blog.absoluteString, "Swift Blog")])
        let window = window()
        let history = HistoryPanelController(session: session)
        history.present(in: window, from: try XCTUnwrap(window.contentView))
        let panel = try XCTUnwrap(history.presented as? HistoryPanel)
        panel.onChoose?(entry(blog))
        let active = try XCTUnwrap(session.activeTabID.flatMap { id in
            session.tabsInActiveSpace(includeArchived: false).first { $0.id == id }
        })
        XCTAssertEqual(active.url, blog)
        session.tearDown()
    }

    private func entry(_ url: URL) -> HistoryEntry {
        HistoryEntry(id: UUID(), title: "", subtitle: "", when: "", host: url.host() ?? "", url: url)
    }
}
