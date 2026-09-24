//
//  BrowserSessionExtensionsTests.swift
//  LunaTests
//
//  §16.1's seam: what the session tells a Space's extensions about its windows
//  and tabs, and which sessions get extensions at all. The host itself is
//  tested in BrowserKit against a real controller.
//

import BrowserKit
import XCTest
@testable import Luna

@MainActor
final class BrowserSessionExtensionsTests: XCTestCase {

    private let directory = URL.temporaryDirectory.appending(path: "luna-tests-\(UUID().uuidString)")

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testAPrivateSessionRunsNoExtensions() async throws {
        let ordinary = try await makeSession()
        let secret = try await makeSession(isPrivate: true)
        XCTAssertNotNil(ordinary.extensionController(forSpace: ordinary.activeSpaceID))
        XCTAssertNil(secret.extensionController(forSpace: secret.activeSpaceID))
    }

    /// One controller per Space, the same one every time it is asked for.
    func testEachSpaceHasItsOwnController() async throws {
        let session = try await makeSession()
        let first = session.activeSpaceID
        let second = try await session.createSpace(name: "Work").id
        let controller = try XCTUnwrap(session.extensionController(forSpace: first))
        XCTAssertTrue(controller === session.extensionController(forSpace: first))
        XCTAssertFalse(controller === session.extensionController(forSpace: second))
    }

    /// A saved row whose page was closed is not a tab an extension can see.
    func testExtensionsSeeTheSpacesOpenPagesOnly() async throws {
        let session = try await makeSession()
        let open = session.newTab(url: URL(string: "https://example.com/open")!)
        let kept = session.newTab(url: URL(string: "https://example.com/kept")!, kind: .pinned)
        session.closeTab(kept)

        let visible = session.extensionTabs(inSpace: session.activeSpaceID).map(\.id)
        XCTAssertTrue(visible.contains(open))
        XCTAssertFalse(visible.contains(kept), "the dormant row")
    }

    /// Two windows in one Space, listed in the same order whichever is in front.
    func testWindowsKeepTheirOrderWhenFocusMoves() async throws {
        let session = try await makeSession()
        let (one, two) = (UUID(), UUID())
        session.openWindow(one)
        session.openWindow(two)
        session.setKeyWindow(one)
        let before = session.extensionWindows(inSpace: session.activeSpaceID)
        session.setKeyWindow(two)
        let after = session.extensionWindows(inSpace: session.activeSpaceID)

        XCTAssertEqual(before.ids, after.ids)
        XCTAssertEqual(before.focused, one)
        XCTAssertEqual(after.focused, two)
    }

    private func makeSession(isPrivate: Bool = false) async throws -> BrowserSession {
        let store = try BrowserStore(path: directory.appending(path: "\(UUID().uuidString).sqlite"))
        return try await BrowserSession.restored(store: store, isPrivate: isPrivate)
    }
}
