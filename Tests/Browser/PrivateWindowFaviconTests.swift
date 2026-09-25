//
//  PrivateWindowFaviconTests.swift
//  LunaTests
//
//  §5.6: a private window's tabs fetch and draw icons through the session's
//  own memory-only `FaviconService`, never `FaviconService.shared`, whose
//  icons are written to disk and drawn by every ordinary window.
//

import BrowserKit
import XCTest
@testable import Luna

@MainActor
final class PrivateWindowFaviconTests: XCTestCase {

    private let directory = URL.temporaryDirectory.appending(path: "luna-tests-\(UUID().uuidString)")

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testAPrivateTabFetchesThroughItsSessionsOwnService() async throws {
        let secret = try await makeSession(isPrivate: true)
        let controller = secret.ensureController(for: try tab(in: secret))

        XCTAssertFalse(secret.favicons === FaviconService.shared)
        XCTAssertTrue(controller.favicons === secret.favicons)
        XCTAssertFalse(secret.icons === SidebarIcons.shared)
    }

    /// Two private windows are two services, so closing one forgets its icons
    /// without touching the other's.
    func testEachPrivateSessionHasItsOwn() async throws {
        let first = try await makeSession(isPrivate: true)
        let second = try await makeSession(isPrivate: true)
        XCTAssertFalse(first.favicons === second.favicons)
    }

    func testAnOrdinaryTabStillUsesTheSharedService() async throws {
        let session = try await makeSession()
        let controller = session.ensureController(for: try tab(in: session))

        XCTAssertTrue(controller.favicons === FaviconService.shared)
        XCTAssertTrue(session.icons === SidebarIcons.shared)
    }

    // MARK: - Helpers

    private func tab(in session: BrowserSession) throws -> Tab {
        let space = try XCTUnwrap(session.spaces.first)
        let tab = Tab(spaceID: space.id, kind: .today, url: URL(string: "https://example.com")!)
        session.persistAll(session.list.insert(tab, at: TabList.openIndex(for: .today)))
        return tab
    }

    private func makeSession(isPrivate: Bool = false) async throws -> BrowserSession {
        let store = try BrowserStore(path: directory.appending(path: "\(UUID().uuidString).sqlite"))
        return try await BrowserSession.restored(store: store, isPrivate: isPrivate)
    }
}
