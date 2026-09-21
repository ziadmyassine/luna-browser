//
//  TabGroupTests.swift
//  LunaTests
//
//  §3.4b: named groups, the saved tier, and the two presses it takes to let a
//  saved row go.
//
//  Three rules carry the whole feature, and each of them is silent when it
//  breaks — the list simply arranges itself wrongly, or a page the user meant
//  to keep is gone:
//
//  · A group's tier is its tabs' tier. Carry a group across the rule and its
//    tabs go with it, so "is this saved" has one answer wherever it is asked.
//  · A group and the loose tabs around it share one run of indices, so a group
//    can stand between two of them — and moving either has to renumber both.
//  · Removing a group removes a name. Only *Close Group* ends pages, and it
//    ends them one at a time so undo can reach each one.
//

import BrowserKit
import XCTest
@testable import Luna

@MainActor
final class TabGroupTests: XCTestCase {

    private let directory = URL.temporaryDirectory.appending(path: "luna-groups-\(UUID().uuidString)")

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - Making one

    /// A group made from a row appears where that row was standing, which is
    /// the only answer that does not move the list under the pointer.
    func testAGroupLandsWhereItsFirstTabStood() async throws {
        let session = try await makeSession()
        let first = session.newTab(url: url("a"))
        let second = session.newTab(url: url("b"))
        // Today's tabs stack newest-first, so `second` is the top slot.
        XCTAssertEqual(session.list.indexInSection(of: first), 1)

        let group = try XCTUnwrap(session.createGroup(name: "Work", containing: [first]))

        XCTAssertEqual(session.group(group)?.order, 1)
        XCTAssertEqual(session.members(ofGroup: group).map(\.id), [first])
        XCTAssertEqual(session.tab(second)?.groupID, nil)
    }

    func testABlankNameMakesNoGroup() async throws {
        let session = try await makeSession()
        XCTAssertNil(session.createGroup(name: "   "))
        XCTAssertTrue(session.groups.isEmpty)
    }

    // MARK: - The two tiers

    /// A group carried above the rule takes its tabs with it, and back down
    /// again brings them back.
    func testAGroupsTierIsItsTabsTier() async throws {
        let session = try await makeSession()
        let id = session.newTab(url: url("a"))
        let group = try XCTUnwrap(session.createGroup(name: "Work", containing: [id]))
        XCTAssertEqual(session.tab(id)?.kind, .today)

        session.setGroupSaved(true, group: group)

        XCTAssertTrue(try XCTUnwrap(session.group(group)).isSaved)
        XCTAssertEqual(session.tab(id)?.kind, .pinned)
        // Saved means there is an address to go home to when the page is closed.
        XCTAssertEqual(session.tab(id)?.pinnedURL, url("a"))

        session.setGroupSaved(false, group: group)

        XCTAssertEqual(session.tab(id)?.kind, .today)
        XCTAssertNil(session.tab(id)?.pinnedURL)
    }

    /// A tab dropped into a saved group is saved, whichever side of the rule it
    /// was dragged from — the group's tier wins over the drop's.
    func testDroppingIntoASavedGroupSavesTheTab() async throws {
        let session = try await makeSession()
        let group = try XCTUnwrap(session.createGroup(name: "Work"))
        session.setGroupSaved(true, group: group)
        let id = session.newTab(url: url("a"))

        session.reorderTab(id, to: 0, kind: .today, group: group)

        XCTAssertEqual(session.tab(id)?.kind, .pinned)
        XCTAssertEqual(session.tab(id)?.groupID, group)
    }

    /// Sending one tab up takes it out of the ordinary group it was in and puts
    /// it in a new folder of its own: §3.4b's upper tier holds folders and
    /// nothing else, so there is no loose row for it to become.
    func testSendingOneTabUpPutsItInAFolderOfItsOwn() async throws {
        let session = try await makeSession()
        let id = session.newTab(url: url("a"))
        let group = try XCTUnwrap(session.createGroup(name: "Work", containing: [id]))

        session.setTabSaved(true, tab: id)

        let moved = try XCTUnwrap(session.tab(id))
        XCTAssertEqual(moved.kind, .pinned)
        let folder = try XCTUnwrap(moved.groupID.flatMap { session.group($0) })
        XCTAssertNotEqual(folder.id, group, "it stayed in the folder it came from")
        XCTAssertEqual(folder.kind, .pinned)
        XCTAssertEqual(session.members(ofGroup: folder.id).map(\.id), [id])
        XCTAssertTrue(session.members(ofGroup: group).isEmpty)
    }

    /// And nothing loose can stand in that tier, however it got there.
    func testNoTabStandsLooseInTheFolderTier() async throws {
        let session = try await makeSession()
        let id = session.newTab(url: url("a"))
        let space = try XCTUnwrap(session.spaces.first).id

        session.reorderTab(id, to: 0, kind: .pinned)

        XCTAssertTrue(
            session.slots(inTier: .pinned).allSatisfy { slot in
                if case .group = slot { return true } else { return false }
            },
            "a loose row stood in the folder tier"
        )
        XCTAssertTrue(session.list[space].filter { $0.kind == .pinned }.allSatisfy { $0.groupID != nil })
    }

    // MARK: - Two presses

    /// The whole of §3.4b's close. The first press ends the page and leaves the
    /// row, dimmed and back at the address it was saved at; the second has no
    /// page left to mean, so it means the row.
    func testASavedTabTakesTwoPressesToClose() async throws {
        let session = try await makeSession()
        let id = session.newTab(url: url("a"))
        session.setTabSaved(true, tab: id)

        session.closeTab(id)

        let dimmed = try XCTUnwrap(session.tab(id))
        XCTAssertTrue(dimmed.isDormant)
        XCTAssertEqual(dimmed.url, url("a"))
        XCTAssertNil(session.controller(for: id))

        session.closeTab(id)

        XCTAssertNil(session.tab(id))
        XCTAssertTrue(session.archived.contains { $0.id == id })
    }

    /// An ordinary tab is archived by the first press, as it always was — the
    /// second press only exists above the rule.
    func testAnOrdinaryTabStillClosesOnTheFirstPress() async throws {
        let session = try await makeSession()
        let id = session.newTab(url: url("a"))

        session.closeTab(id)

        XCTAssertNil(session.tab(id))
    }

    /// Clicking a dimmed row is opening it again, so the second press it was
    /// holding goes away.
    func testChoosingADimmedRowWakesIt() async throws {
        let session = try await makeSession()
        let id = session.newTab(url: url("a"))
        session.setTabSaved(true, tab: id)
        session.closeTab(id)

        session.activateTab(id)

        XCTAssertEqual(session.tab(id)?.isDormant, false)
    }

    /// A tab carried back down past the rule is an ordinary open tab again, not
    /// a dimmed one that the next press would throw away.
    func testComingBackDownClearsTheDimming() async throws {
        let session = try await makeSession()
        let id = session.newTab(url: url("a"))
        session.setTabSaved(true, tab: id)
        session.closeTab(id)

        session.setTabSaved(false, tab: id)

        XCTAssertEqual(session.tab(id)?.isDormant, false)
    }

    // MARK: - Taking one apart

    /// Ungroup keeps every page and drops the name, in the slot the group held.
    func testUngroupKeepsTheTabsWhereTheGroupStood() async throws {
        let session = try await makeSession()
        let inside = session.newTab(url: url("a"))
        let loose = session.newTab(url: url("b"))
        let group = try XCTUnwrap(session.createGroup(name: "Work", containing: [inside]))

        session.ungroup(group)

        XCTAssertNil(session.group(group))
        XCTAssertEqual(session.tab(inside)?.groupID, nil)
        XCTAssertEqual(session.tab(inside)?.kind, .today)
        // One run of indices, renumbered together: two slots, 0 and 1.
        let slots = session.list.slots(inSpace: session.activeSpaceID, kind: .today)
        XCTAssertEqual(slots.compactMap(\.tabID), [loose, inside])
        XCTAssertEqual(slots.map(\.order), [0, 1])
    }

    /// Close Group ends the pages and then the group. Each tab goes through
    /// `closeTab`, so each one is in the archive and each one is undoable.
    func testCloseGroupArchivesItsTabsAndThenGoes() async throws {
        let session = try await makeSession()
        let first = session.newTab(url: url("a"))
        let second = session.newTab(url: url("b"))
        let group = try XCTUnwrap(session.createGroup(name: "Work", containing: [first, second]))

        session.closeGroup(group)

        XCTAssertNil(session.group(group))
        XCTAssertNil(session.tab(first))
        XCTAssertNil(session.tab(second))
        XCTAssertEqual(session.archived.filter { $0.id == first || $0.id == second }.count, 2)
    }

    /// A saved group's tabs dim on the first Close Group, exactly as pressing
    /// close on each of them would — and the group is still there, because
    /// nothing in it has been let go yet.
    func testCloseGroupOnASavedGroupDimsFirst() async throws {
        let session = try await makeSession()
        let id = session.newTab(url: url("a"))
        let group = try XCTUnwrap(session.createGroup(name: "Work", containing: [id]))
        session.setGroupSaved(true, group: group)

        session.closeGroup(group)

        XCTAssertNotNil(session.group(group))
        XCTAssertEqual(session.tab(id)?.isDormant, true)

        session.closeGroup(group)

        XCTAssertNil(session.group(group))
        XCTAssertNil(session.tab(id))
    }

    // MARK: - Ordering

    /// Groups and loose tabs share one run, so moving a group renumbers the
    /// tabs around it and the arrangement on disk stays the one on screen.
    func testAGroupStandsBetweenTwoLooseTabs() async throws {
        let session = try await makeSession()
        let bottom = session.newTab(url: url("a"))
        let top = session.newTab(url: url("b"))
        let group = try XCTUnwrap(session.createGroup(name: "Work"))

        session.moveGroup(group, to: 1, kind: .today)

        let slots = session.list.slots(inSpace: session.activeSpaceID, kind: .today)
        XCTAssertEqual(slots.map(\.id), [top, group, bottom])
        XCTAssertEqual(slots.map(\.order), [0, 1, 2])
    }

    /// A group belongs to the Space it was made in, so a tab carried out of
    /// that Space leaves the group rather than dragging it along.
    func testATabMovedToAnotherSpaceLeavesItsGroup() async throws {
        let session = try await makeSession()
        let id = session.newTab(url: url("a"))
        let group = try XCTUnwrap(session.createGroup(name: "Work", containing: [id]))
        let other = try await session.createSpace(name: "Other")

        session.moveTab(id, toSpace: other.id)

        XCTAssertNil(session.tab(id)?.groupID)
        XCTAssertTrue(session.members(ofGroup: group).isEmpty)
    }

    /// The column reads the tiers already arranged, group tabs inline under
    /// their header — which is what keeps the sidebar from having an order of
    /// its own to disagree with.
    func testTheDrawnSlotsCarryEachGroupsTabs() async throws {
        let session = try await makeSession()
        let inside = session.newTab(url: url("a"))
        let group = try XCTUnwrap(session.createGroup(name: "Work", containing: [inside]))

        let slots = session.slots(inTier: .today)

        XCTAssertEqual(slots.count, 1)
        guard case let .group(drawn, tabs) = try XCTUnwrap(slots.first) else {
            return XCTFail("the group did not come back as a group")
        }
        XCTAssertEqual(drawn.id, group)
        XCTAssertEqual(tabs.map(\.id), [inside])
    }

    // MARK: - Fixtures

    private func url(_ path: String) -> URL {
        URL(string: "https://example.com/\(path)")!
    }

    private func makeSession() async throws -> BrowserSession {
        try await BrowserSession.restored(store: BrowserStore(path: directory.appending(path: "luna.sqlite")))
    }
}
