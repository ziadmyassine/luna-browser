//
//  ControlServiceTests.swift
//  LunaTests
//
//  Luna Control against a real session: a client's tabs go into one folder
//  named after it without taking the user's selection, a page tool reaches
//  the tab it names, and a client cannot close the user's own tabs.
//

import BrowserKit
import LunaControl
import XCTest
@testable import Luna

@MainActor
final class ControlServiceTests: XCTestCase {

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

    private let client = ControlClient(rawName: "example-agent")

    private func text(_ result: ControlResult) -> String {
        result.content.compactMap { if case let .text(text) = $0 { text } else { nil } }.joined()
    }

    func testOpenedTabsShareOneFolderNamedAfterTheClientAndLeaveTheSelectionAlone() async throws {
        let session = try await session()
        let users = session.newTab(url: URL(string: "about:blank")!)
        let service = ControlService(session: session)

        _ = await service.perform(ControlCall(.openTab(URL(string: "about:blank"))), client)
        _ = await service.perform(ControlCall(.openTab(nil)), client)

        let folder = try XCTUnwrap(session.groups.first { $0.name == "Example Agent" })
        XCTAssertEqual(session.members(ofGroup: folder.id).count, 2)
        XCTAssertEqual(session.groups.filter { $0.name == "Example Agent" }.count, 1)
        XCTAssertEqual(session.activeTabID, users, "an agent's tab took over the user's window")
    }

    func testAPageToolActsOnTheTabItLastOpened() async throws {
        let session = try await session()
        let service = ControlService(session: session)
        let url = try XCTUnwrap(URL(string: "data:text/html,%3Cbutton%3EGo%3C/button%3E"))
        _ = await service.perform(ControlCall(.openTab(url)), client)

        let found = await service.perform(ControlCall(.find("go")), client)
        XCTAssertFalse(found.isError, text(found))
        XCTAssertTrue(text(found).contains("button \"Go\" [e"), text(found))
    }

    func testAClientCannotCloseTheUsersTabs() async throws {
        let session = try await session()
        let users = session.newTab(url: URL(string: "about:blank")!)
        let service = ControlService(session: session)
        let number = service.number(users)

        let result = await service.perform(ControlCall(tab: number, .closeTab), client)
        XCTAssertTrue(result.isError)
        XCTAssertNotNil(session.tab(users))
    }
}
