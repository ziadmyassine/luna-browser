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

    /// Allow-all, so these tests are about tabs and folders rather than
    /// approvals (`ControlSafetyTests` has those), and in a suite of their own
    /// rather than the user's defaults — fixed and emptied, for the reason in
    /// `ControlSafetyTests.setUpWithError`.
    private func makeService(_ session: BrowserSession) -> ControlService {
        let defaults = UserDefaults(suiteName: "luna.tests.ControlServiceTests")
        defaults?.removePersistentDomain(forName: "luna.tests.ControlServiceTests")
        defaults?.set(ControlMode.allowAll.rawValue, forKey: ControlService.modeKey)
        return ControlService(
            session: session, defaults: defaults ?? .standard, auditURL: directory.appending(path: "activity.jsonl")
        )
    }

    private func text(_ result: ControlResult) -> String {
        result.content.compactMap { if case let .text(text) = $0 { text } else { nil } }.joined()
    }

    func testOpenedTabsShareOneFolderNamedAfterTheClientAndLeaveTheSelectionAlone() async throws {
        let session = try await session()
        let users = session.newTab(url: URL(string: "about:blank")!)
        let service = makeService(session)

        _ = await service.perform(ControlCall(.openTab(URL(string: "about:blank"))), client)
        _ = await service.perform(ControlCall(.openTab(nil)), client)

        let folder = try XCTUnwrap(session.groups.first { $0.name == "Example Agent" })
        XCTAssertEqual(session.members(ofGroup: folder.id).count, 2)
        XCTAssertEqual(session.groups.filter { $0.name == "Example Agent" }.count, 1)
        XCTAssertEqual(session.activeTabID, users, "an agent's tab took over the user's window")
    }

    func testAPageToolActsOnTheTabItLastOpened() async throws {
        let session = try await session()
        let service = makeService(session)
        let url = try XCTUnwrap(URL(string: "data:text/html,%3Cbutton%3EGo%3C/button%3E"))
        _ = await service.perform(ControlCall(.openTab(url)), client)

        let found = await service.perform(ControlCall(.find("go")), client)
        XCTAssertFalse(found.isError, text(found))
        XCTAssertTrue(text(found).contains("button \"Go\" [e"), text(found))
    }

    func testAClientCannotCloseTheUsersTabs() async throws {
        let session = try await session()
        let users = session.newTab(url: URL(string: "about:blank")!)
        let service = makeService(session)
        let number = service.number(users)

        let result = await service.perform(ControlCall(tab: number, .closeTab), client)
        XCTAssertTrue(result.isError)
        XCTAssertNotNil(session.tab(users))
    }

    /// Two sessions of one app are two agents: a folder each, called by the
    /// session's name, numbered while a session has none, and following the
    /// name until the user renames the folder themselves.
    func testEachSessionOfOneAppGetsAFolderOfItsOwn() async throws {
        let session = try await session()
        let service = makeService(session)
        let first = ControlClient(rawName: "claude-code", session: "one")
        var second = ControlClient(rawName: "claude-code", session: "two")
        _ = await service.perform(ControlCall(.openTab(nil)), first)
        _ = await service.perform(ControlCall(.openTab(nil)), second)
        let one = try XCTUnwrap(service.folders["one"])
        let two = try XCTUnwrap(service.folders["two"])
        XCTAssertNotEqual(one, two, "two sessions share a folder")
        XCTAssertEqual(session.group(one)?.name, "Claude Code")
        XCTAssertEqual(session.group(two)?.name, "Claude Code 2")
        XCTAssertEqual(session.members(ofGroup: two).count, 1)

        second.sessionName = "Main 3"
        _ = await service.perform(ControlCall(.listTabs), second)
        XCTAssertEqual(session.group(two)?.name, "Main 3", "the folder did not take the session's name")

        session.renameGroup(two, to: "Mine")
        second.sessionName = "Main 4"
        _ = await service.perform(ControlCall(.listTabs), second)
        XCTAssertEqual(session.group(two)?.name, "Mine", "the user's name for the folder was replaced")
        XCTAssertEqual(service.shownActivity.map(\.agent).sorted(), ["one", "two"], "one pill for both sessions")
    }

    /// A loose tab of the user's that an agent acts on goes into the agent's
    /// folder; one it only reads stays where it is.
    func testATabAnAgentActsOnGoesIntoItsFolder() async throws {
        let session = try await session()
        let users = session.newTab(url: try XCTUnwrap(URL(string: "data:text/html,%3Cp%3Ehi%3C/p%3E")))
        let service = makeService(session)
        let number = service.number(users)

        let read = await service.perform(ControlCall(tab: number, .pageText), client)
        XCTAssertFalse(read.isError, text(read))
        XCTAssertNil(session.tab(users)?.groupID, "reading the tab moved it")

        let ran = await service.perform(ControlCall(tab: number, .javascript("1 + 1")), client)
        XCTAssertFalse(ran.isError, text(ran))
        let folder = try XCTUnwrap(service.folders[client.session], "acting made no folder")
        XCTAssertEqual(session.tab(users)?.groupID, folder, "the tab the agent used is not in its folder")
        XCTAssertEqual(session.activeTabID, users, "moving the tab changed the user's selection")
    }

    /// Scrolling and hovering ask nothing, but they move the page the user is
    /// watching under the agent's pointer: the tab is the agent's from then.
    func testScrollingATabTakesItOver() async throws {
        let session = try await session()
        let users = session.newTab(url: try XCTUnwrap(URL(string: "data:text/html,%3Cp%3Ehi%3C/p%3E")))
        let service = makeService(session)
        let scrolled = await service.perform(
            ControlCall(tab: service.number(users), .scroll(.down, amount: 1, target: nil)), client
        )
        XCTAssertFalse(scrolled.isError, text(scrolled))
        let folder = try XCTUnwrap(service.folders[client.session], "scrolling made no folder")
        XCTAssertEqual(session.tab(users)?.groupID, folder, "the scrolled tab is still loose")
    }

    /// A tab in a Space the user is not in goes into a folder in its own
    /// Space: it was left loose there, and it must not change Space either.
    func testATabInAnotherSpaceGoesIntoAFolderThere() async throws {
        let session = try await session()
        let home = session.activeSpaceID
        let users = session.newTab(url: try XCTUnwrap(URL(string: "data:text/html,%3Cp%3Ehi%3C/p%3E")))
        let work = try await session.createSpace(name: "Work").id
        session.switchSpace(work, inWindow: session.keyWindowID)
        XCTAssertEqual(session.activeSpaceID, work)
        let service = makeService(session)

        let ran = await service.perform(ControlCall(tab: service.number(users), .javascript("1 + 1")), client)
        XCTAssertFalse(ran.isError, text(ran))
        let folder = try XCTUnwrap(session.tab(users)?.groupID, "the tab in the other Space is still loose")
        XCTAssertEqual(session.group(folder)?.spaceID, home, "the folder is not in the tab's Space")
        XCTAssertEqual(session.tab(users)?.spaceID, home, "folding the tab moved it to another Space")
        XCTAssertEqual(session.activeSpaceID, work, "the agent changed the user's Space")
    }
}
