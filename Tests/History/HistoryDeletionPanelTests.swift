//
//  HistoryDeletionPanelTests.swift
//  LunaTests
//
//  §11.3 in the panel: pages grouped under their day, several marked and
//  deleted together, Clear History… over a span, and Forget This Site — and
//  that a page deleted here is gone from the Command Bar's lessons as well as
//  from the list.
//
//  The two questions are answered through the controller's seams; a modal
//  alert in a test is a test that waits for a person.
//

import BrowserKit
import WebKit
import XCTest
@testable import Luna

@MainActor
final class HistoryDeletionPanelTests: XCTestCase {

    private let directory = URL.temporaryDirectory.appending(path: "luna-tests-\(UUID().uuidString)")

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func url(_ text: String) -> URL { URL(string: text)! }

    /// A session whose Space visited each page `hoursAgo` hours ago.
    private func session(visiting pages: [(String, Double)]) async throws -> BrowserSession {
        let session = try await BrowserSession.restored(store: BrowserStore(path: directory.appending(path: "luna.sqlite")))
        for (address, hours) in pages {
            try await session.store.recordVisit(
                url: url(address), title: address, kind: .typed,
                at: Date().addingTimeInterval(-hours * 3600), inSpace: session.activeSpaceID
            )
        }
        return session
    }

    private func present(_ session: BrowserSession) async throws -> (HistoryPanelController, HistoryPanel) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.contentView = NSView(frame: window.contentLayoutRect)
        let history = HistoryPanelController(session: session)
        history.present(in: window, from: try XCTUnwrap(window.contentView))
        let panel = try XCTUnwrap(history.presented as? HistoryPanel)
        try await waitFor { !panel.shownEntries.isEmpty }
        return (history, panel)
    }

    private func waitFor(_ condition: () -> Bool) async throws {
        let start = Date()
        while !condition(), Date().timeIntervalSince(start) < 2 {
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    private func list(in panel: HistoryPanel) throws -> HistoryListView {
        func find(_ view: NSView) -> HistoryListView? {
            if let list = view as? HistoryListView { return list }
            return view.subviews.lazy.compactMap(find).first
        }
        return try XCTUnwrap(find(panel))
    }

    private func entry(_ address: String, in panel: HistoryPanel) throws -> HistoryEntry {
        try XCTUnwrap(panel.shownEntries.first { $0.url.absoluteString == address })
    }

    private func addresses(_ panel: HistoryPanel) -> [String] {
        panel.shownEntries.map(\.url.absoluteString)
    }

    // MARK: - Days

    /// Newest first, and a header wherever the day changes.
    func testPagesAreGroupedUnderTheirDay() async throws {
        let now = Date()
        let calendar = Calendar.current
        // 01:00 two calendar days back, wherever in the day the test runs.
        let earlier = try XCTUnwrap(calendar.date(byAdding: .day, value: -2, to: calendar.startOfDay(for: now)))
        let twoDaysAgo = now.timeIntervalSince(earlier.addingTimeInterval(3600)) / 3600
        let session = try await session(visiting: [
            ("https://swift.org/", twoDaysAgo), ("https://apple.com/", twoDaysAgo - 0.1), ("https://github.com/", 0)
        ])
        let (history, panel) = try await present(session)
        XCTAssertEqual(addresses(panel), ["https://github.com/", "https://apple.com/", "https://swift.org/"])
        XCTAssertEqual(
            panel.shownDays,
            [String(localized: "Today"), HistoryTimestamp.day(for: now.addingTimeInterval(-twoDaysAgo * 3600))]
        )
        history.dismiss()
        session.tearDown()
    }

    // MARK: - Marking and deleting

    func testCommandAndShiftClicksMarkRowsAndDeleteDeletesThem() async throws {
        let session = try await session(visiting: [
            ("https://a.example/", 4), ("https://b.example/", 3), ("https://c.example/", 2), ("https://d.example/", 1)
        ])
        let (history, panel) = try await present(session)
        let list = try list(in: panel)
        list.click(try entry("https://d.example/", in: panel), modifiers: .command)
        list.click(try entry("https://b.example/", in: panel), modifiers: .shift)
        XCTAssertEqual(
            panel.markedEntries.map(\.url.absoluteString),
            ["https://d.example/", "https://c.example/", "https://b.example/"]
        )
        // ⌘-click again unmarks.
        list.click(try entry("https://c.example/", in: panel), modifiers: .command)
        XCTAssertEqual(panel.markedEntries.count, 2)

        XCTAssertEqual(panel.field.onDeleteKey?(false), true, "⌫ with rows marked did not delete them")
        await history.deleting?.value
        XCTAssertEqual(addresses(panel), ["https://c.example/", "https://a.example/"])
        let left = await session.browsingHistory(matching: "", limit: 10).map(\.url.absoluteString)
        XCTAssertEqual(left, ["https://c.example/", "https://a.example/"])
        history.dismiss()
        session.tearDown()
    }

    /// ⌘A marks every page, not the query's text.
    func testCommandAMarksEveryPage() async throws {
        let session = try await session(visiting: [("https://a.example/", 2), ("https://b.example/", 1)])
        let (history, panel) = try await present(session)
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: 0,
            context: nil, characters: "a", charactersIgnoringModifiers: "a", isARepeat: false, keyCode: 0
        ))
        XCTAssertTrue(panel.performKeyEquivalent(with: event))
        XCTAssertEqual(panel.markedEntries.count, 2)
        history.dismiss()
        session.tearDown()
    }

    /// With nothing marked a plain ⌫ is the search field's; ⌘⌫ deletes the
    /// highlighted page.
    func testWithNothingMarkedOnlyCommandDeleteDeletesTheHighlightedPage() async throws {
        let session = try await session(visiting: [("https://a.example/", 2), ("https://b.example/", 1)])
        let (history, panel) = try await present(session)
        XCTAssertEqual(panel.field.onDeleteKey?(false), false, "a plain ⌫ deleted a page")
        XCTAssertEqual(panel.field.onDeleteKey?(true), true)
        await history.deleting?.value
        XCTAssertEqual(addresses(panel), ["https://a.example/"])
        history.dismiss()
        session.tearDown()
    }

    /// The menu acts on every marked page when the row is marked, and offers
    /// Forget This Site only while they are all one site's.
    func testTheRowMenuNamesWhatItActsOn() async throws {
        let session = try await session(visiting: [("https://www.apple.com/", 2), ("https://swift.org/", 1)])
        let (history, panel) = try await present(session)
        let apple = try entry("https://www.apple.com/", in: panel)
        // The words, without the glyph `SidebarMenu.glyphItem` sets in front of them.
        func words(_ menu: NSMenu) -> [String] { menu.items.map { $0.title.components(separatedBy: "\t").last ?? "" } }
        XCTAssertEqual(words(HistoryMenu.build(for: [apple], controller: history)), ["Delete", "Forget This Site", "", "Clear History…"])
        XCTAssertEqual(words(HistoryMenu.build(for: panel.shownEntries, controller: history)), ["Delete 2 Pages", "", "Clear History…"])
        for name in HistoryMenu.Glyph.all {
            XCTAssertNotNil(NSImage(systemSymbolName: name, accessibilityDescription: nil), "\(name) draws nothing")
        }
        history.dismiss()
        session.tearDown()
    }

    // MARK: - Clear History… and Forget This Site

    func testClearHistoryClearsTheSpanItWasAskedFor() async throws {
        let session = try await session(visiting: [("https://old.example/", 30), ("https://new.example/", 0.2)])
        let (history, panel) = try await present(session)
        var asked: String?
        history.askClearRange = { space in
            asked = space
            return .lastHour
        }
        history.clearHistory()
        await history.deleting?.value
        XCTAssertEqual(asked, session.space(session.activeSpaceID)?.name)
        XCTAssertEqual(addresses(panel), ["https://old.example/"])

        history.askClearRange = { _ in nil }
        history.clearHistory()
        await history.deleting?.value
        XCTAssertEqual(addresses(panel), ["https://old.example/"], "Cancel cleared something")
        history.dismiss()
        session.tearDown()
    }

    func testForgetThisSiteTakesEveryPageOfTheSite() async throws {
        let session = try await session(visiting: [
            ("https://www.apple.com/", 3), ("https://developer.apple.com/", 2), ("https://swift.org/", 1)
        ])
        let (history, panel) = try await present(session)
        history.confirmForget = { _, _ in false }
        history.forgetSite("apple.com")
        await history.deleting?.value
        XCTAssertEqual(panel.shownEntries.count, 3, "declining forgot the site anyway")

        history.confirmForget = { _, _ in true }
        history.forgetSite("apple.com")
        await history.deleting?.value
        XCTAssertEqual(addresses(panel), ["https://swift.org/"])
        history.dismiss()
        session.tearDown()
    }

    /// The site's records go and every other site's stay. A non-persistent
    /// store, so the test leaves nothing in a jar on disk.
    func testForgettingASiteRemovesItsWebsiteData() async throws {
        let store = WKWebsiteDataStore.nonPersistent()
        for domain in [".apple.com", "example.com"] {
            let cookie = try XCTUnwrap(HTTPCookie(properties: [
                .domain: domain, .path: "/", .name: "session", .value: "1", .secure: "TRUE",
                .expires: Date().addingTimeInterval(3600)
            ]))
            await store.httpCookieStore.setCookie(cookie)
        }
        await BrowserSession.removeWebsiteData(ofSite: "apple.com", from: store)
        let left = await store.httpCookieStore.allCookies().map(\.domain)
        XCTAssertEqual(left, ["example.com"])
    }

    /// A deleted page must not stay first in the Command Bar through the
    /// adaptive table it keeps in memory.
    func testDeletingAPageDropsTheCommandBarsLessonsForIt() async throws {
        let page = url("https://github.com/")
        let session = try await session(visiting: [(page.absoluteString, 1)])
        try await session.store.setInputUseCount(typed: "gi", url: page, useCount: 1, inSpace: session.activeSpaceID)
        let adaptive = AdaptiveHistory(store: session.store)
        await adaptive.loadIfNeeded(inSpace: session.activeSpaceID)
        XCTAssertEqual(adaptive.snapshot.count, 1)

        await session.deleteHistory(of: [page])
        XCTAssertTrue(adaptive.snapshot.isEmpty, "the table in memory still ranks the deleted page")
        await adaptive.loadIfNeeded(inSpace: session.activeSpaceID)
        XCTAssertTrue(adaptive.snapshot.isEmpty, "the store still holds the lesson")
        session.tearDown()
    }
}
