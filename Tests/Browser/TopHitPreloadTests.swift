//
//  TopHitPreloadTests.swift
//  LunaTests
//
//  The command bar's top hit, loaded before Return: handed over only for the
//  page and Space it was loaded for, and taken over by the new tab rather
//  than loaded a second time.
//

import BrowserKit
import XCTest
@testable import Luna

@MainActor
final class TopHitPreloadTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = URL.temporaryDirectory.appending(path: "luna-tests-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func session() async throws -> BrowserSession {
        let store = try BrowserStore(path: directory.appending(path: "luna.sqlite"))
        try await store.seedIfEmpty()
        return try await BrowserSession.restored(store: store)
    }

    /// Nothing listens on the discard port, so the load ends at once and the
    /// test never reaches the network.
    private let page = URL(string: "http://127.0.0.1:9/")!
    private static let size = CGSize(width: 1200, height: 800)

    private func settle() async throws {
        try await Task.sleep(for: TopHitPreload.settle + .milliseconds(150))
    }

    func testThePreloadIsHandedOverOnlyForItsPageAndSpace() async throws {
        let session = try await session()
        let space = session.activeSpaceID
        let preload = TopHitPreload()
        preload.want(page, inSpace: space, size: Self.size, session: session)
        try await settle()

        XCTAssertNil(preload.take(URL(string: "http://127.0.0.1:9/other"), inSpace: space))
        XCTAssertNil(preload.take(page, inSpace: UUID()))
        XCTAssertNotNil(preload.take(page, inSpace: space))
        XCTAssertNil(preload.take(page, inSpace: space), "a preload was handed over twice")
    }

    /// Choosing before the address has settled finds no page, and starts none.
    func testAnAddressThatHasNotSettledIsNotLoaded() async throws {
        let session = try await session()
        let preload = TopHitPreload()
        preload.want(page, inSpace: session.activeSpaceID, size: Self.size, session: session)
        XCTAssertNil(preload.take(page, inSpace: session.activeSpaceID))
        preload.cancel()
        try await settle()
        XCTAssertNil(preload.url)
    }

    func testANewTabTakesOverThePreloadedPage() async throws {
        let session = try await session()
        let preload = TopHitPreload()
        preload.want(page, inSpace: session.activeSpaceID, size: Self.size, session: session)
        try await settle()
        let controller = try XCTUnwrap(preload.take(page, inSpace: session.activeSpaceID))
        let webView = try XCTUnwrap(controller.webView)

        let id = session.newTab(url: page, adopting: controller)

        XCTAssertEqual(id, controller.id)
        XCTAssertNotNil(session.tab(id))
        XCTAssertTrue(session.controller(for: id) === controller)
        XCTAssertTrue(session.controller(for: id)?.webView === webView, "the tab started the page again")
        XCTAssertEqual(webView.frame.size, Self.size, "the page loaded at a size it is not shown at")
        XCTAssertEqual(session.activeTabID, id)
    }
}
