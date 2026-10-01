//
//  UnreadTabTests.swift
//  LunaTests
//
//  §7.3's unread dot: a tab no window is showing gets it when its page
//  finishes a load or changes its title, and loses it the moment a window
//  shows it. The states are handed to the session directly — what WebKit
//  would report — so the rule is tested without waiting on the network.
//

import BrowserKit
import XCTest
@testable import Luna

@MainActor
final class UnreadTabTests: XCTestCase {

    private let directory = URL.temporaryDirectory.appending(path: "luna-unread-\(UUID().uuidString)")

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testALinkOpenedInTheBackgroundIsUnreadOnceItHasLoaded() async throws {
        let session = try await makeSession()
        let front = session.newTab(url: url("front"))
        let child = try openInBackground(url("next"), from: front, in: session)
        let controller = try XCTUnwrap(session.controller(for: child))

        session.tabController(controller, didChange: TabState(url: url("next"), title: "Next", isLoading: true))
        XCTAssertFalse(try unread(child, in: session), "a page still loading is not news yet")

        session.tabController(controller, didChange: TabState(url: url("next"), title: "Next", isLoading: false))
        XCTAssertTrue(try unread(child, in: session), "a background tab that finished loading has no dot")
        XCTAssertFalse(try unread(front, in: session), "the tab in front was marked")
    }

    func testTheTabBeingLookedAtNeverGoesUnread() async throws {
        let session = try await makeSession()
        let front = session.newTab(url: url("front"))
        let controller = try XCTUnwrap(session.controller(for: front))

        session.tabController(controller, didChange: TabState(url: url("front"), isLoading: true))
        session.tabController(controller, didChange: TabState(url: url("front"), title: "Front", isLoading: false))
        session.tabController(controller, didChange: TabState(url: url("front"), title: "(1) Front", isLoading: false))
        XCTAssertFalse(try unread(front, in: session))
    }

    func testATitleChangeOnATabLeftBehindMarksIt() async throws {
        let session = try await makeSession()
        let inbox = session.newTab(url: url("inbox"))
        let controller = try XCTUnwrap(session.controller(for: inbox))
        session.tabController(controller, didChange: TabState(url: url("inbox"), title: "Inbox", isLoading: false))
        session.newTab(url: url("elsewhere"))

        session.tabController(controller, didChange: TabState(url: url("inbox"), title: "Inbox", isLoading: false))
        XCTAssertFalse(try unread(inbox, in: session), "a report with nothing new in it marked the tab")

        session.tabController(controller, didChange: TabState(url: url("inbox"), title: "(3) Inbox", isLoading: false))
        XCTAssertTrue(try unread(inbox, in: session), "a new title on a tab nobody is looking at has no dot")
    }

    func testATitleArrivingDuringALoadWaitsForTheLoad() async throws {
        let session = try await makeSession()
        let front = session.newTab(url: url("front"))
        let child = try openInBackground(url("next"), from: front, in: session)
        let controller = try XCTUnwrap(session.controller(for: child))

        session.tabController(controller, didChange: TabState(url: url("next"), title: "Next", isLoading: true))
        XCTAssertFalse(try unread(child, in: session), "the dot came before the page")
    }

    func testChoosingTheTabClearsItAndTheDotIsKept() async throws {
        let session = try await makeSession()
        let front = session.newTab(url: url("front"))
        let child = try openInBackground(url("next"), from: front, in: session)
        try finishLoading(child, in: session)
        XCTAssertTrue(try unread(child, in: session))

        await session.persist()
        let stored = try await session.store.tabs(inSpace: session.activeSpaceID, includeArchived: false)
        XCTAssertEqual(stored.first { $0.id == child }?.hasUnread, true, "the dot did not reach the database")

        session.activateTab(child)
        XCTAssertFalse(try unread(child, in: session), "choosing the tab left its dot")
    }

    /// The selection moving on its own — the tab above it closed — is a window
    /// showing the tab too.
    func testATabArrivedAtByClosingTheOneAboveIsRead() async throws {
        let session = try await makeSession()
        let front = session.newTab(url: url("front"))
        let child = try openInBackground(url("next"), from: front, in: session)
        try finishLoading(child, in: session)

        session.closeTab(front)
        XCTAssertEqual(session.activeTabID, child)
        XCTAssertFalse(try unread(child, in: session), "the tab now on screen kept its dot")
    }

    func testAnotherWindowShowingTheTabIsReadingIt() async throws {
        let session = try await makeSession()
        let shared = session.newTab(url: url("shared"))
        let controller = try XCTUnwrap(session.controller(for: shared))
        let other = UUID()
        session.openWindow(other)
        session.activateTab(shared, inWindow: other)
        session.newTab(url: url("elsewhere"))

        session.tabController(controller, didChange: TabState(url: url("shared"), isLoading: true))
        session.tabController(controller, didChange: TabState(url: url("shared"), title: "Shared", isLoading: false))
        XCTAssertFalse(try unread(shared, in: session), "a tab on screen in the other window was marked")
    }

    // MARK: - Helpers

    private func openInBackground(_ link: URL, from parent: UUID, in session: BrowserSession) throws -> UUID {
        let before = Set(session.tabs.map(\.id))
        let controller = try XCTUnwrap(session.controller(for: parent))
        session.tabController(controller, wantsToOpenInNewTab: link, inBackground: true)
        return try XCTUnwrap(session.tabs.first { !before.contains($0.id) }?.id)
    }

    private func finishLoading(_ id: UUID, in session: BrowserSession) throws {
        let controller = try XCTUnwrap(session.controller(for: id))
        let page = try XCTUnwrap(session.tab(id)?.url)
        session.tabController(controller, didChange: TabState(url: page, isLoading: true))
        session.tabController(controller, didChange: TabState(url: page, title: "Loaded", isLoading: false))
    }

    private func unread(_ id: UUID, in session: BrowserSession) throws -> Bool {
        try XCTUnwrap(session.tab(id)).hasUnread
    }

    private func makeSession() async throws -> BrowserSession {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = try BrowserStore(path: directory.appending(path: "luna.sqlite"))
        try await store.seedIfEmpty()
        return try await BrowserSession.restored(store: store)
    }

    private func url(_ path: String) -> URL {
        URL(string: "https://example.com/\(path)")!
    }
}
