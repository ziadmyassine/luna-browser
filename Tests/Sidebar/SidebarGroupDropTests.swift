//
//  SidebarGroupDropTests.swift
//  LunaTests
//
//  §6.6: the box that closes round a §3.4b folder a tab is being filed into.
//
//  An expanded folder used to answer a lift with nothing at all — the tab
//  stepped in by `groupIndent` and that was the whole of it — so what is
//  asserted here is that the box is the folder's whole extent and not its
//  header: the name, the tabs already in it, and the room the list has just
//  opened for the one arriving.
//
//  Extent is arithmetic over rows that are themselves being offset by the gap,
//  which is exactly the kind of thing that comes out one row short on screen
//  and reads as a box that does not quite reach.
//

import BrowserKit
import XCTest
@testable import Luna

@MainActor
final class SidebarGroupDropTests: XCTestCase {

    private let space = UUID()
    private var group = TabGroup(spaceID: UUID(), name: "Trip", order: 0)

    /// Three tabs in the folder, plus the one arriving from outside it.
    func testTheBoxHoldsTheWholeFolderAndTheRoomForTheTabArriving() throws {
        let controller = try list()
        let header = try XCTUnwrap(controller.list.row(ofGroup: group.id))
        controller.beginDrag(atRow: try XCTUnwrap(controller.list.row(of: looseTab.id)))
        controller.setGroupDrop(inside: group.id)
        controller.setGap(row: header + 2)
        XCTAssertEqual(
            controller.groupDrop.frame.height,
            5 * Tokens.Metric.rowHeight - 2 * Tokens.Metric.rowPillInset,
            accuracy: 0.51,
            "the box does not reach round the folder and the tab going into it"
        )
        XCTAssertFalse(controller.groupDrop.isHidden)
    }

    /// A tab already in the folder leaves a hole where it was, so the folder is
    /// the same height throughout — the box must not grow by a row for a tab
    /// that is only changing places inside it.
    func testTheBoxDoesNotGrowForATabAlreadyInTheFolder() throws {
        let controller = try list()
        let header = try XCTUnwrap(controller.list.row(ofGroup: group.id))
        controller.beginDrag(atRow: header + 1)
        controller.setGroupDrop(inside: group.id)
        controller.setGap(row: header + 3)
        XCTAssertEqual(
            controller.groupDrop.frame.height,
            4 * Tokens.Metric.rowHeight - 2 * Tokens.Metric.rowPillInset,
            accuracy: 0.51
        )
    }

    /// The box starts at the folder's header, wherever the gap has pushed it.
    /// A tab dragged from above the folder closes the rows behind it up, so the
    /// header stands one row higher than the table's own answer for it.
    func testTheBoxFollowsTheHeaderTheGapHasMoved() throws {
        let controller = try list()
        let header = try XCTUnwrap(controller.list.row(ofGroup: group.id))
        controller.beginDrag(atRow: try XCTUnwrap(controller.list.row(of: looseTab.id)))
        controller.setGroupDrop(inside: group.id)
        controller.setGap(row: header + 1)
        XCTAssertEqual(
            controller.groupDrop.frame.minY,
            controller.table.rect(ofRow: header).minY - Tokens.Metric.rowHeight + Tokens.Metric.rowPillInset,
            accuracy: 0.51,
            "the box is where the header was rather than where it is"
        )
    }

    /// A folded folder makes the same movement an open one does: a row opens
    /// under its header and the box holds it. None of its own tabs are on
    /// screen, so that is a box two rows tall — which is what the folder will
    /// be a moment later, since the drop opens it.
    func testAFoldedFolderOpensTheSameRoomAnOpenOneDoes() throws {
        group.isCollapsed = true
        let controller = try list()
        let header = try XCTUnwrap(controller.list.row(ofGroup: group.id))
        controller.beginDrag(atRow: try XCTUnwrap(controller.list.row(of: looseTab.id)))
        controller.setGroupDrop(inside: group.id)
        controller.setGap(row: header + 1)
        XCTAssertEqual(
            controller.groupDrop.frame.height,
            2 * Tokens.Metric.rowHeight - 2 * Tokens.Metric.rowPillInset,
            accuracy: 0.51
        )
    }

    /// A folder's header is not split down the middle: most of it means "in
    /// this folder", because the row above has already offered "beside it".
    func testMostOfAFoldersHeaderMeansInsideIt() throws {
        let controller = try list()
        let header = try XCTUnwrap(controller.list.row(ofGroup: group.id))
        // Asked in the table's own coordinates, which is what `landing` reads
        // once the sidebar has been converted out of the question.
        let box = controller.table.rect(ofRow: header)
        let table = controller.table
        XCTAssertEqual(
            controller.landing(atY: box.minY + Tokens.Metric.groupDropEdge + 1, in: table).destination.groupID,
            group.id,
            "a point well inside the header still landed beside the folder"
        )
        XCTAssertNil(
            controller.landing(atY: box.minY + 1, in: table).destination.groupID,
            "the folder took the boundary above it as well"
        )
    }

    /// A drop landing loose has no folder to draw a box round.
    func testALooseDropDrawsNoBox() throws {
        let controller = try list()
        controller.beginDrag(atRow: 0)
        controller.setGroupDrop(inside: group.id)
        controller.setGroupDrop(inside: nil)
        XCTAssertEqual(controller.groupDrop.alphaValue, 0, accuracy: 0.01)
    }

    // MARK: - Fixtures

    private lazy var looseTab = tab(9)

    private func tab(_ index: Int) -> Tab {
        Tab(
            spaceID: space,
            kind: .today,
            url: URL(string: "https://example.com/\(index)")!,
            title: "Tab \(index)",
            order: index
        )
    }

    /// One folder of three tabs, with a loose tab above it to drag in from —
    /// above, so the rows closing up behind the lift move the folder's header
    /// and the box has something to follow.
    private func list() throws -> TabListController {
        let members = (0 ..< 3).map { tab($0) }
        let controller = TabListController()
        controller.scrollView.frame = NSRect(x: 0, y: 0, width: 260, height: 500)
        controller.show(
            saved: [],
            today: [.tab(looseTab), .group(group, tabs: members)],
            essentials: [],
            activeTabID: looseTab.id
        )
        controller.table.layoutSubtreeIfNeeded()
        XCTAssertNotNil(controller.list.row(ofGroup: group.id), "the fixture has no folder in it")
        return controller
    }
}
