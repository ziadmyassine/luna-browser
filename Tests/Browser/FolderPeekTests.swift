//
//  FolderPeekTests.swift
//  LunaTests
//
//  §3.4b: a folded folder still shows the tab the user was on, and any tab
//  they go to inside it, until that tab is closed or the folder is opened and
//  folded again — in the column and on §4's bar alike.
//

import BrowserKit
import XCTest
@testable import Luna

@MainActor
final class FolderPeekTests: XCTestCase {

    private let directory = URL.temporaryDirectory.appending(path: "luna-tests-\(UUID().uuidString)")

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private struct Folder {
        let session: BrowserSession
        let group: UUID
        let first: UUID
        let second: UUID
        let loose: UUID
    }

    private func folder() async throws -> Folder {
        let store = try BrowserStore(path: directory.appending(path: "\(UUID().uuidString).sqlite"))
        let session = try await BrowserSession.restored(store: store)
        let loose = session.newTab(url: URL(string: "https://apple.com")!)
        let first = session.newTab(url: URL(string: "https://google.com")!)
        let second = session.newTab(url: URL(string: "https://github.com")!)
        let group = try XCTUnwrap(session.createGroup(name: "AI", containing: [first, second]))
        return Folder(session: session, group: group, first: first, second: second, loose: loose)
    }

    /// The rows the column would draw for the session as it stands.
    private func columnRows(_ folder: Folder) -> [SidebarRow] {
        SidebarList(today: folder.session.slots(inTier: .today), peeking: folder.session.folderPeeks).rows
    }

    private func barTabs(_ folder: Folder) -> [UUID] {
        TopBarStripRun(today: folder.session.slots(inTier: .today), peeking: folder.session.folderPeeks).tabs.map(\.id)
    }

    func testFoldingKeepsTheTabYouAreOn() async throws {
        let folder = try await folder()
        folder.session.activateTab(folder.first)
        folder.session.setGroupCollapsed(true, forGroup: folder.group)
        XCTAssertEqual(folder.session.folderPeeks, [folder.first])
        XCTAssertTrue(columnRows(folder).contains(.tab(folder.first)), "the column hid the tab you are on")
        XCTAssertFalse(columnRows(folder).contains(.tab(folder.second)))
        XCTAssertTrue(barTabs(folder).contains(folder.first), "the bar hid the tab you are on")
        XCTAssertFalse(barTabs(folder).contains(folder.second))
        XCTAssertEqual(folder.session.group(folder.group)?.isCollapsed, true)
    }

    func testFoldingWhileElsewhereShowsNothing() async throws {
        let folder = try await folder()
        folder.session.activateTab(folder.loose)
        folder.session.setGroupCollapsed(true, forGroup: folder.group)
        XCTAssertTrue(folder.session.folderPeeks.isEmpty)
        XCTAssertFalse(columnRows(folder).contains(.tab(folder.first)))
    }

    /// Going to a tab in a folded folder — as §9.1 does — shows it under the
    /// folder and does not open the folder; moving on leaves it there.
    func testGoingToAFoldedTabShowsItAndItStays() async throws {
        let folder = try await folder()
        folder.session.activateTab(folder.loose)
        folder.session.setGroupCollapsed(true, forGroup: folder.group)
        folder.session.activateTab(folder.second)
        XCTAssertEqual(folder.session.group(folder.group)?.isCollapsed, true, "going to it opened the folder")
        XCTAssertTrue(columnRows(folder).contains(.tab(folder.second)))
        folder.session.activateTab(folder.loose)
        XCTAssertTrue(columnRows(folder).contains(.tab(folder.second)), "clicking away put it away")
    }

    func testClosingItIsWhatPutsItAway() async throws {
        let folder = try await folder()
        folder.session.activateTab(folder.first)
        folder.session.setGroupCollapsed(true, forGroup: folder.group)
        folder.session.closeTab(folder.first)
        XCTAssertFalse(folder.session.folderPeeks.contains(folder.first))
        XCTAssertFalse(columnRows(folder).contains(.tab(folder.first)))
    }

    /// Opening and folding again starts over: only the tab you are on then.
    func testOpeningAndFoldingAgainStartsOver() async throws {
        let folder = try await folder()
        folder.session.activateTab(folder.first)
        folder.session.setGroupCollapsed(true, forGroup: folder.group)
        folder.session.activateTab(folder.second)
        folder.session.activateTab(folder.loose)
        XCTAssertEqual(folder.session.folderPeeks, [folder.first, folder.second])
        folder.session.setGroupCollapsed(false, forGroup: folder.group)
        folder.session.setGroupCollapsed(true, forGroup: folder.group)
        XCTAssertTrue(folder.session.folderPeeks.isEmpty)
        XCTAssertFalse(columnRows(folder).contains(.tab(folder.first)))
    }
}
