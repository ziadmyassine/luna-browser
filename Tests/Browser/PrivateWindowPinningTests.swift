//
//  PrivateWindowPinningTests.swift
//  LunaTests
//
//  §5.6 keeps nothing: neither §3.3's tiles nor §3.4b's folder tier is offered
//  in a private window, and neither verb does anything if it is called anyway.
//
//  Both halves are asserted, because either on its own is the bug. A verb that
//  refuses while the menu still offers it is a dead item; a menu that hides the
//  item while the verb still works is one drag away from a tile in a database
//  that is deleted when the window closes.
//

import AppKit
import BrowserKit
import XCTest
@testable import Luna

@MainActor
final class PrivateWindowPinningTests: XCTestCase {

    private let directory = URL.temporaryDirectory.appending(path: "luna-tests-\(UUID().uuidString)")

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - The rule

    func testAnOrdinaryWindowKeepsThingsAndAPrivateOneDoesNot() async throws {
        let ordinary = try await makeSession()
        let secret = try await makeSession(isPrivate: true)
        XCTAssertTrue(ordinary.allowsPinning)
        XCTAssertFalse(secret.allowsPinning)
    }

    // MARK: - The verbs

    func testPinningATabIsRefused() async throws {
        let session = try await makeSession(isPrivate: true)
        let id = try tab(in: session)

        XCTAssertFalse(session.pinTab(id))
        XCTAssertEqual(session.tab(id)?.kind, .today)
    }

    func testPinningAFolderIsRefused() async throws {
        let session = try await makeSession(isPrivate: true)
        let id = try XCTUnwrap(session.createGroup(name: "Work"))

        session.setGroupSaved(true, group: id)

        XCTAssertEqual(session.group(id)?.kind, .today)
        XCTAssertFalse(try XCTUnwrap(session.group(id)).isSaved)
    }

    /// The same two calls on an ordinary session, so the guard above is read as
    /// the exception it is rather than as the behaviour.
    func testAnOrdinaryWindowStillPinsBoth() async throws {
        let session = try await makeSession()
        let tabID = try tab(in: session)
        let groupID = try XCTUnwrap(session.createGroup(name: "Work"))

        XCTAssertTrue(session.pinTab(tabID))
        session.setGroupSaved(true, group: groupID)

        XCTAssertEqual(session.tab(tabID)?.kind, .essential)
        XCTAssertTrue(try XCTUnwrap(session.group(groupID)).isSaved)
    }

    // MARK: - The menus

    func testTheTabMenuHasNoPinItem() async throws {
        let session = try await makeSession(isPrivate: true)
        let id = try tab(in: session)
        let actions = session.tabMenuActions(for: id)
        XCTAssertNil(actions.pin)
        XCTAssertNil(actions.unpin)

        let menu = TabMenu.build(for: try XCTUnwrap(session.tab(id)), isMuted: false, actions: actions)
        XCTAssertFalse(menu.items.contains { Self.word($0) == "Pin" })
        // And the menu still leads with something rather than with a rule.
        XCTAssertEqual(menu.items.first.map(Self.word), "Add to Folder")
    }

    func testTheFolderMenuHasNoPinItemAndNoGapWhereItWas() async throws {
        let session = try await makeSession(isPrivate: true)
        let id = try XCTUnwrap(session.createGroup(name: "Work"))
        let actions = session.groupMenuActions(for: id)
        XCTAssertNil(actions.setSaved)

        let menu = GroupMenu.build(for: try XCTUnwrap(session.group(id)), actions: actions, rename: {}, emoji: {})
        XCTAssertEqual(menu.items.map(Self.word), [
            "Rename", "Change Icon", "", "Remove Folder, Keep Tabs", "Close Folder and Tabs"
        ])
    }

    // MARK: - The column

    /// §3.4b's rule marks the bottom of the kept tier, and a window with no
    /// kept tier has no bottom to mark — not even under a §6.6 lift, which is
    /// the one thing that otherwise brings it out on an empty Space.
    func testTheKeptTiersRuleNeverComesOut() {
        XCTAssertFalse(SidebarList(revealingSaved: true, pinning: false).rows.contains(.separator))
        XCTAssertTrue(SidebarList(revealingSaved: true).rows.contains(.separator))
    }

    /// The half of `New Tab` above its midpoint is the kept tier's target, and
    /// with no kept tier it has to mean the head of today's tabs instead —
    /// otherwise the row would still pin whatever was dropped on it.
    func testNothingDroppedOnNewTabLandsInTheKeptTier() throws {
        let list = SidebarList(today: [.tab(Tab(spaceID: UUID(), kind: .today, url: url))], pinning: false)
        let row = try XCTUnwrap(list.rows.firstIndex(of: .addTab))

        XCTAssertEqual(list.destination(forRow: row, isBelowMidpoint: false).kind, .today)
        XCTAssertEqual(list.destination(forRow: row, isBelowMidpoint: true).kind, .today)
    }

    // MARK: - Helpers

    /// An item's word, without §3.4a's glyph in front of it — see
    /// `BrowserSessionTabMenuTests.word`.
    private static func word(_ item: NSMenuItem) -> String {
        item.title.split(separator: "\t", maxSplits: 1).last.map(String.init) ?? item.title
    }

    @discardableResult
    private func tab(in session: BrowserSession) throws -> UUID {
        let space = try XCTUnwrap(session.spaces.first)
        let tab = Tab(spaceID: space.id, kind: .today, url: url)
        session.persistAll(session.list.insert(tab, at: TabList.openIndex(for: .today)))
        return tab.id
    }

    private func makeSession(isPrivate: Bool = false) async throws -> BrowserSession {
        let store = try BrowserStore(path: directory.appending(path: "\(UUID().uuidString).sqlite"))
        return try await BrowserSession.restored(store: store, isPrivate: isPrivate)
    }

    private let url = URL(string: "https://example.com/one")!
}
