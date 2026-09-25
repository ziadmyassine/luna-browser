//
//  SidebarGroupPlateTests.swift
//  LunaTests
//
//  §3.4b: the plate round a folder while the pointer is over it, open or
//  folded, and its bottom edge stretching on the rows' clock as the folder
//  folds. Measured off the controller's own views; nothing here is put on
//  screen.
//

import BrowserKit
import XCTest
@testable import Luna

@MainActor
final class SidebarGroupPlateTests: XCTestCase {

    private let space = UUID()
    private var trip = TabGroup(spaceID: UUID(), name: "Trip", order: 0)
    private var work = TabGroup(spaceID: UUID(), name: "Work", order: 1)

    func testHoveringTheHeaderPlatesTheWholeFolder() throws {
        let controller = try list()
        let header = try XCTUnwrap(controller.list.row(ofGroup: trip.id))
        controller.setHovered(header)
        try assertPlate(controller, isRound: trip)
    }

    func testHoveringAMemberPlatesTheWholeFolderAndKeepsItsPill() throws {
        let controller = try list()
        let header = try XCTUnwrap(controller.list.row(ofGroup: trip.id))
        controller.setHovered(header + 2)
        try assertPlate(controller, isRound: trip)
        XCTAssertEqual(controller.hoverPill.alphaValue, 1, accuracy: 0.01)
        XCTAssertEqual(controller.hoverPill.frame, controller.pillBox(ofRow: header + 2))
        XCTAssertTrue(
            controller.groupPlate.frame.contains(controller.hoverPill.frame),
            "the member's pill reaches outside the plate"
        )
    }

    /// Open or folded, a header answers the pointer with the plate alone.
    func testNoHeaderTakesAHoverPill() throws {
        for collapsed in [false, true] {
            trip.isCollapsed = collapsed
            let controller = try list()
            controller.setHovered(try XCTUnwrap(controller.list.row(ofGroup: trip.id)))
            XCTAssertEqual(controller.hoverPill.alphaValue, 0, accuracy: 0.01, "collapsed: \(collapsed)")
            XCTAssertEqual(controller.groupPlate.alphaValue, 1, accuracy: 0.01, "collapsed: \(collapsed)")
        }
    }

    func testALooseTabHasNoPlate() throws {
        let controller = try list()
        controller.setHovered(try XCTUnwrap(controller.list.row(of: looseTab.id)))
        XCTAssertNil(controller.groupPlateBox())
        XCTAssertEqual(controller.groupPlate.alphaValue, 0, accuracy: 0.01)
    }

    func testNoHoverHasNoPlate() throws {
        let controller = try list()
        controller.setHovered(try XCTUnwrap(controller.list.row(ofGroup: trip.id)))
        controller.setHovered(nil)
        XCTAssertNil(controller.groupPlateBox())
    }

    /// A folded folder's hover is the plate too, and it is exactly the hover
    /// pill a loose tab gets — same box, same corners — with no foot because
    /// there is no room under it.
    func testAFoldedHeaderTakesThePlateAndNoHoverPill() throws {
        trip.isCollapsed = true
        let controller = try list()
        let header = try XCTUnwrap(controller.list.row(ofGroup: trip.id))
        // The loose tab is the selected one, so it is measured rather than hovered.
        let tabHover = controller.pillBox(ofRow: try XCTUnwrap(controller.list.row(of: looseTab.id)))
        controller.setHovered(header)
        controller.groupPlate.updateLayer()
        XCTAssertEqual(controller.hoverPill.alphaValue, 0, accuracy: 0.01)
        XCTAssertEqual(controller.groupPlate.alphaValue, 1, accuracy: 0.01)
        XCTAssertEqual(controller.groupPlate.frame, controller.pillBox(ofRow: header))
        XCTAssertEqual(controller.groupPlate.frame.size, tabHover.size, "the folder's plate is not a tab hover's size")
        XCTAssertEqual(controller.groupPlate.layer?.cornerRadius ?? 0, Tokens.Metric.rowCornerRadius, accuracy: 0.01)
    }

    /// Unfolding moves only the bottom edge, so the two plates differ by the
    /// three tab rows and the foot and by nothing else.
    func testFoldedAndOpenPlatesShareSidesTopAndCorners() throws {
        let open = try list()
        open.setHovered(try XCTUnwrap(open.list.row(ofGroup: trip.id)))
        trip.isCollapsed = true
        let folded = try list()
        folded.setHovered(try XCTUnwrap(folded.list.row(ofGroup: trip.id)))
        let (big, small) = (open.groupPlate.frame, folded.groupPlate.frame)
        XCTAssertEqual(big.minX, small.minX)
        XCTAssertEqual(big.maxX, small.maxX)
        XCTAssertEqual(big.minY, small.minY, "the top edge moved")
        XCTAssertEqual(big.height - small.height, 3 * Tokens.Metric.rowHeight + Tokens.Metric.groupPlateFoot, accuracy: 0.01)
        for controller in [open, folded] { controller.groupPlate.updateLayer() }
        XCTAssertEqual(open.groupPlate.layer?.cornerRadius, folded.groupPlate.layer?.cornerRadius)
    }

    func testUnfoldingStretchesThePlateOnTheRowsClock() throws {
        trip.isCollapsed = true
        let controller = try list()
        controller.setHovered(try XCTUnwrap(controller.list.row(ofGroup: trip.id)))
        let foldedHeight = controller.groupPlate.frame.height
        fold(controller, false)
        XCTAssertEqual(controller.groupPlate.frame, controller.groupPlateBox())
        try assertStretch(controller, from: foldedHeight)
    }

    func testFoldingShrinksThePlateBackUp() throws {
        let controller = try list()
        controller.setHovered(try XCTUnwrap(controller.list.row(ofGroup: trip.id)))
        let openHeight = controller.groupPlate.frame.height
        fold(controller, true)
        XCTAssertEqual(controller.groupPlate.frame, controller.groupPlateBox())
        XCTAssertLessThan(controller.groupPlate.frame.height, openHeight)
        try assertStretch(controller, from: openHeight)
    }

    /// The rows' own layout pass lands on `movePills(animated: false)` while
    /// they are still sliding; the plate is already standing where it is going
    /// and has to keep stretching there.
    func testALayoutPassMidFoldDoesNotSnapThePlate() throws {
        trip.isCollapsed = true
        let controller = try list()
        controller.setHovered(try XCTUnwrap(controller.list.row(ofGroup: trip.id)))
        let foldedHeight = controller.groupPlate.frame.height
        fold(controller, false)
        controller.table.needsLayout = true
        controller.table.layoutSubtreeIfNeeded()
        controller.movePills(animated: false)
        try assertStretch(controller, from: foldedHeight)
    }

    func testHoverMovingFromHeaderToChildKeepsThePlateStill() throws {
        trip.isCollapsed = true
        let controller = try list()
        let header = try XCTUnwrap(controller.list.row(ofGroup: trip.id))
        controller.setHovered(header)
        // Offscreen the fade-in never finishes; clear it so a second one shows.
        controller.groupPlate.layer?.removeAllAnimations()
        let foldedHeight = controller.groupPlate.frame.height
        fold(controller, false)
        let frame = controller.groupPlate.frame
        controller.setHovered(header + 1)
        XCTAssertEqual(controller.groupPlate.frame, frame)
        XCTAssertNil(controller.groupPlate.layer?.animation(forKey: "opacity"))
        try assertStretch(controller, from: foldedHeight)
    }

    func testFoldingWithThePointerElsewhereShowsNoPlate() throws {
        let controller = try list()
        controller.setHovered(try XCTUnwrap(controller.list.row(of: looseTab.id)))
        fold(controller, true)
        XCTAssertNil(controller.groupPlateBox())
        XCTAssertEqual(controller.groupPlate.alphaValue, 0, accuracy: 0.01)
    }

    /// A width change is not the plate's own move: it lands, stretch or not.
    func testAResizeStillLandsThePlate() throws {
        trip.isCollapsed = true
        let controller = try list()
        controller.setHovered(try XCTUnwrap(controller.list.row(ofGroup: trip.id)))
        fold(controller, false)
        let width = controller.groupPlate.frame.width
        controller.scrollView.frame.size.width += 40
        controller.scrollView.layoutSubtreeIfNeeded()
        controller.movePills(animated: false)
        XCTAssertEqual(controller.groupPlate.frame.width, width + 40, accuracy: 0.01)
        XCTAssertEqual(controller.groupPlate.frame, controller.groupPlateBox())
        XCTAssertNil(controller.groupPlate.layer?.animationKeys())
    }

    func testThePlateFollowsThePointerToTheNextFolder() throws {
        let controller = try list()
        controller.setHovered(try XCTUnwrap(controller.list.row(ofGroup: trip.id)) + 1)
        controller.setHovered(try XCTUnwrap(controller.list.row(ofGroup: work.id)) + 1)
        try assertPlate(controller, isRound: work)
    }

    /// The room under the folder is inside the plate, so crossing it does not
    /// drop the plate and bring it straight back.
    func testHoveringTheRoomUnderAFolderKeepsItsPlate() throws {
        let controller = try list()
        controller.setHovered(try XCTUnwrap(controller.list.rows.firstIndex(of: .groupEnd(trip.id))))
        try assertPlate(controller, isRound: trip)
        XCTAssertEqual(controller.hoverPill.alphaValue, 0, accuracy: 0.01)
    }

    /// The header draws no pill, so above the folder the plate stands the
    /// header icon's margin in its pill clear of the icon. The
    /// last tab gets the same room below its pill, and the plate stops where
    /// the next row starts.
    func testThePlateHasEqualRoomAboveTheHeaderAndBelowTheLastTab() throws {
        let controller = try list()
        let header = try XCTUnwrap(controller.list.row(ofGroup: trip.id))
        controller.setHovered(header)
        let plate = controller.groupPlate.frame
        let iconTop = controller.pillBox(ofRow: header).minY + (Tokens.Metric.rowPillHeight - Tokens.Metric.groupIconSize) / 2
        let lastPill = controller.pillBox(ofRow: header + 3)
        XCTAssertEqual(iconTop - plate.minY, plate.maxY - lastPill.maxY, accuracy: 0.01)
        XCTAssertEqual(plate.maxY - lastPill.maxY, 7.5, accuracy: 0.01)
        let next = try XCTUnwrap(controller.list.row(ofGroup: work.id))
        XCTAssertEqual(plate.maxY, controller.table.rect(ofRow: next).minY, accuracy: 0.01)
        XCTAssertLessThan(plate.maxY, controller.pillBox(ofRow: next).minY, "the plate lies under the next pill")
    }

    /// Parked for the whole lift, so it never lies under §6.6's dashed box.
    func testThePlateIsParkedDuringADrag() throws {
        let controller = try list()
        let header = try XCTUnwrap(controller.list.row(ofGroup: trip.id))
        controller.setHovered(header + 1)
        controller.beginDrag(atRow: try XCTUnwrap(controller.list.row(of: looseTab.id)))
        controller.table.needsLayout = true
        controller.table.layoutSubtreeIfNeeded()
        controller.movePills()
        XCTAssertEqual(controller.groupPlate.alphaValue, 0, accuracy: 0.01)
    }

    // MARK: - Fixtures

    /// The plate's height runs on the rows' clock: `tabInsert`'s duration and
    /// curve, from the height it had before the fold. Nothing under Reduce
    /// Motion, where the rows do not slide either.
    private func assertStretch(_ controller: TabListController, from height: CGFloat) throws {
        let layer = try XCTUnwrap(controller.groupPlate.layer)
        guard !Tokens.Motion.reduceMotion else { return XCTAssertNil(layer.animationKeys()) }
        let stretch = try XCTUnwrap(layer.animation(forKey: "bounds") as? CABasicAnimation, "the plate did not stretch")
        XCTAssertEqual(stretch.duration, Tokens.Motion.tabInsert.duration, accuracy: 0.001)
        XCTAssertEqual(controlPoints(stretch.timingFunction), controlPoints(Tokens.Motion.tabInsert.timingFunction))
        XCTAssertEqual((stretch.fromValue as? NSValue)?.rectValue.height ?? 0, height, accuracy: 0.01)
    }

    private func controlPoints(_ function: CAMediaTimingFunction?) -> [Float] {
        guard let function else { return [] }
        return (0...3).flatMap { index -> [Float] in
            var point = [Float](repeating: 0, count: 2)
            function.getControlPoint(at: index, values: &point)
            return point
        }
    }

    /// Folds or unfolds Trip through the controller's real rebuild, the path
    /// the chevron takes.
    private func fold(_ controller: TabListController, _ collapsed: Bool) {
        trip.isCollapsed = collapsed
        controller.show(saved: [], today: slots, essentials: [], activeTabID: looseTab.id)
    }

    /// The folder's extent as its pills span it, plus the foot — computed here
    /// from the rows rather than read back from the controller.
    private func assertPlate(_ controller: TabListController, isRound group: TabGroup) throws {
        let header = try XCTUnwrap(controller.list.row(ofGroup: group.id))
        controller.groupPlate.updateLayer()
        let last = header + 3
        let rows = controller.table.rect(ofRow: header).union(controller.table.rect(ofRow: last))
        var expected = rows.insetBy(dx: Tokens.Metric.rowInset, dy: Tokens.Metric.rowPillInset)
        expected.size.height += Tokens.Metric.groupPlateFoot
        XCTAssertEqual(controller.groupPlate.frame, expected, "the plate is not round the whole folder")
        XCTAssertEqual(controller.groupPlate.alphaValue, 1, accuracy: 0.01)
        XCTAssertEqual(
            controller.groupPlate.layer?.cornerRadius ?? 0,
            Tokens.Metric.rowCornerRadius,
            accuracy: 0.01,
            "the plate's corners are not a row pill's"
        )
    }

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

    /// A loose tab, then two folders of three tabs each. The tabs are built
    /// once so a fold hands the controller the same ids again.
    private lazy var folderTabs = (0 ..< 6).map { tab($0) }

    private var slots: [SidebarSlot] {
        [
            .tab(looseTab),
            .group(trip, tabs: Array(folderTabs[0 ..< 3])),
            .group(work, tabs: Array(folderTabs[3 ..< 6]))
        ]
    }

    private func list() throws -> TabListController {
        let controller = TabListController()
        controller.scrollView.frame = NSRect(x: 0, y: 0, width: 260, height: 500)
        controller.show(
            saved: [],
            today: slots,
            essentials: [],
            activeTabID: looseTab.id
        )
        controller.table.layoutSubtreeIfNeeded()
        return controller
    }
}

/// Where the plate stands across the column and against the list's top edge.
extension SidebarGroupPlateTests {

    /// The plate's sides are a loose tab's, and a folder's tabs keep their
    /// pills clear of its trailing edge.
    func testThePlateStandsOnALooseTabsSidesAndHoldsItsTabsInside() throws {
        let controller = try list()
        let header = try XCTUnwrap(controller.list.row(ofGroup: trip.id))
        controller.setHovered(header + 1)
        let plate = controller.groupPlate.frame
        let loose = controller.pillBox(ofRow: try XCTUnwrap(controller.list.row(of: looseTab.id)))
        XCTAssertEqual(plate.minX, loose.minX)
        XCTAssertEqual(plate.maxX, loose.maxX)
        XCTAssertEqual(plate.maxX - controller.hoverPill.frame.maxX, Tokens.Metric.groupMemberTrailingInset, accuracy: 0.01)
    }

    /// A folder first in the list has its plate's top edge on screen: the
    /// plate reaches no higher than its header's own pill.
    func testAFolderAtTheTopOfTheListHasItsWholePlateInView() throws {
        let controller = TabListController()
        controller.scrollView.frame = NSRect(x: 0, y: 0, width: 260, height: 500)
        controller.show(saved: [], today: Array(slots.dropFirst()), essentials: [], activeTabID: folderTabs[0].id)
        controller.table.layoutSubtreeIfNeeded()
        controller.setHovered(try XCTUnwrap(controller.list.row(ofGroup: trip.id)))
        let visible = controller.scrollView.contentView.bounds
        XCTAssertLessThanOrEqual(visible.minY, controller.groupPlate.frame.minY, "the plate's top edge is clipped")
    }
}
