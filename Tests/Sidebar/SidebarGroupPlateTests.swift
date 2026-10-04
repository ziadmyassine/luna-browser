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

    /// A folded folder's hover is the plate too: the hover pill a loose tab
    /// gets, as wide and as round, and as much taller as the folder's row is
    /// (`groupHeaderRowHeight`), with no foot because there is no room under it.
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
        XCTAssertEqual(controller.groupPlate.frame.width, tabHover.width, "the folder's plate is not a tab hover's width")
        XCTAssertEqual(
            controller.groupPlate.frame.height - tabHover.height,
            Tokens.Metric.groupHeaderRowHeight - Tokens.Metric.tabRowHeight,
            accuracy: 0.01,
            "the folded plate is not the folder row's own pill"
        )
        XCTAssertEqual(controller.groupPlate.layer?.cornerRadius ?? 0, Tokens.Metric.rowCornerRadius, accuracy: 0.01)
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

    /// An open plate has as much room over the folder's icon as under its last
    /// tab's, give or take the two icons' sizes, and stops short of the next
    /// row by as much as a pill does. The foot was twice the head.
    func testAnOpenFolderHasTheSameRoomAtItsHeadAsAtItsFoot() throws {
        let controller = try list()
        let header = try XCTUnwrap(controller.list.row(ofGroup: trip.id))
        controller.setHovered(header)
        let plate = controller.groupPlate.frame
        let lastPill = controller.pillBox(ofRow: header + 3)
        // The folder symbol draws about 15 pt of its 20 pt box; a favicon
        // fills its 16. What is compared is the room round what is drawn.
        let drawnFolder: CGFloat = 15
        let row = try XCTUnwrap(controller.table.view(atColumn: 0, row: header, makeIfNecessary: true) as? SidebarRowView)
        row.layoutSubtreeIfNeeded()
        let middle = controller.table.convert(NSPoint(x: 0, y: row.contentMidY), from: row).y
        let head = middle - drawnFolder / 2 - plate.minY
        let foot = plate.maxY - (lastPill.midY + Tokens.Metric.faviconSize / 2)
        // Within 3.5: the folded header stands at a tab's pitch so folders
        // step like tabs, and the plate keeps 4 pt round its tabs so their
        // glyphs clear its side; the foot is what gives.
        XCTAssertEqual(head, foot, accuracy: 3.51, "head \(head), foot \(foot)")
        XCTAssertEqual(plate.maxY - lastPill.maxY, Tokens.Metric.groupPlateFoot, accuracy: 0.01)
        XCTAssertEqual(plate.maxX - lastPill.maxX, plate.maxY - lastPill.maxY, accuracy: 0.01, "the side is not the foot")
        let next = try XCTUnwrap(controller.list.row(ofGroup: work.id))
        XCTAssertEqual(plate.maxY, controller.table.rect(ofRow: next).minY - Tokens.Metric.tabRowPillInset, accuracy: 0.01)
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
        var expected = rows.insetBy(dx: Tokens.Metric.rowInset, dy: Tokens.Metric.tabRowPillInset)
        expected.size.height += Tokens.Metric.groupPlateFoot
        XCTAssertEqual(controller.groupPlate.frame, expected, "the plate is not round the whole folder")
        XCTAssertEqual(controller.groupPlate.alphaValue, 1, accuracy: 0.01)
        XCTAssertEqual(
            controller.groupPlate.layer?.cornerRadius ?? 0,
            Tokens.Metric.groupPlateCornerRadius,
            accuracy: 0.01,
            "the plate's corners do not nest round the pills inside it"
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

    /// Unfolding moves only the bottom edge, so the two plates differ by the
    /// three tab rows and the foot and by nothing else.
    func testFoldedAndOpenPlatesShareSidesAndTop() throws {
        let open = try list()
        open.setHovered(try XCTUnwrap(open.list.row(ofGroup: trip.id)))
        trip.isCollapsed = true
        let folded = try list()
        folded.setHovered(try XCTUnwrap(folded.list.row(ofGroup: trip.id)))
        let (big, small) = (open.groupPlate.frame, folded.groupPlate.frame)
        XCTAssertEqual(big.minX, small.minX)
        XCTAssertEqual(big.maxX, small.maxX)
        XCTAssertEqual(big.minY, small.minY, "the top edge moved")
        XCTAssertEqual(
            big.height - small.height,
            3 * Tokens.Metric.tabRowHeight + Tokens.Metric.groupPlateFoot
                + Tokens.Metric.groupHeaderOpenRowHeight - Tokens.Metric.groupHeaderRowHeight,
            accuracy: 0.01
        )
        for controller in [open, folded] { controller.groupPlate.updateLayer() }
        // Folded, the plate is a tab-sized pill and rounds like one; open, it
        // holds pills `groupPlateFoot` inside it and rounds round them.
        XCTAssertEqual(folded.groupPlate.layer?.cornerRadius ?? 0, Tokens.Metric.rowCornerRadius, accuracy: 0.01)
        XCTAssertEqual(open.groupPlate.layer?.cornerRadius ?? 0, Tokens.Metric.groupPlateCornerRadius, accuracy: 0.01)
    }

    /// The name leads its tabs: the first one sits closer under it than one
    /// tab sits under the next, and folding never moves the name. At a full
    /// row's pitch it read as a heading floating over the folder.
    func testAnOpenFolderNameSitsCloseOverItsTabsAndStaysPutWhenFolded() throws {
        func nameMiddle(_ controller: TabListController) throws -> CGFloat {
            let header = try XCTUnwrap(controller.list.row(ofGroup: trip.id))
            let row = try XCTUnwrap(controller.table.view(atColumn: 0, row: header, makeIfNecessary: true) as? SidebarRowView)
            row.layoutSubtreeIfNeeded()
            return controller.table.convert(NSPoint(x: 0, y: row.contentMidY), from: row).y
        }
        let open = try list()
        let header = try XCTUnwrap(open.list.row(ofGroup: trip.id))
        let toFirstTab = open.pillBox(ofRow: header + 1).midY - (try nameMiddle(open))
        let toNextTab = open.pillBox(ofRow: header + 2).midY - open.pillBox(ofRow: header + 1).midY
        XCTAssertLessThan(toFirstTab, toNextTab - 4, "the name floats over its first tab")
        let openName = try nameMiddle(open)
        trip.isCollapsed = true
        XCTAssertEqual(try nameMiddle(try list()), openName, accuracy: 0.01, "folding moved the name")
    }

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

    /// An open folder stands as far from the row after it as one tab stands
    /// from the next. It stood at half that, and two open folders read as one
    /// block.
    func testTheRowAfterAnOpenFolderHasATabsGapAboveIt() throws {
        let controller = try list()
        let header = try XCTUnwrap(controller.list.row(ofGroup: trip.id))
        let next = try XCTUnwrap(controller.list.row(ofGroup: work.id))
        let loose = controller.pillBox(ofRow: try XCTUnwrap(controller.list.row(of: looseTab.id)))
        let tabGap = controller.pillBox(ofRow: header).minY - loose.maxY
        XCTAssertEqual(tabGap, 2 * Tokens.Metric.tabRowPillInset, accuracy: 0.01)
        controller.setHovered(header)
        let gap = controller.pillBox(ofRow: next).minY - controller.groupPlate.frame.maxY
        XCTAssertEqual(gap, tabGap, accuracy: 0.01, "the next folder is closer to this one than a tab is to a tab")
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

/// Luna Control's outlines: round a working tab, and gone with a closed folder.
extension SidebarGroupPlateTests {

    /// A tab an agent is acting on wears its folder's rim and spark, on the
    /// tab's own pill box, and loses them when the agent is done.
    func testATabAnAgentIsUsingIsOutlined() throws {
        let controller = try list()
        let row = try XCTUnwrap(controller.list.row(of: looseTab.id))
        controller.workingTabs = [looseTab.id: ControlFace(appID: "claude-code")]
        let glow = try XCTUnwrap(controller.tabGlows[looseTab.id], "the tab has no outline")
        XCTAssertEqual(glow.frame, controller.pillBox(ofRow: row))
        XCTAssertTrue(glow.isWorking)
        XCTAssertEqual(glow.tint, Tokens.Agent.tint(forApp: "claude-code"))
        controller.workingTabs = [:]
        XCTAssertNil(controller.tabGlows[looseTab.id], "the outline stayed after the agent was done")
        XCTAssertFalse(glow.isWorking)
    }

    /// A Luna Control folder that is closed takes its outline with it.
    func testAClosedAgentFolderLeavesNoOutline() throws {
        let controller = try list()
        controller.controlFaces = [trip.id: ControlFace(appID: "claude-code")]
        let plate = try XCTUnwrap(controller.controlPlates[trip.id], "the folder has no outline")
        XCTAssertEqual(plate.alphaValue, 1, accuracy: 0.01)
        controller.show(
            saved: [], today: [.tab(looseTab), .group(work, tabs: Array(folderTabs[3 ..< 6]))], essentials: [],
            activeTabID: looseTab.id
        )
        controller.table.layoutSubtreeIfNeeded()
        XCTAssertTrue(plate.superview == nil || plate.alphaValue < 0.01, "the closed folder's outline stayed")
    }

    /// The pointer on a row the list no longer has: a folder that went with
    /// its last tab took the rows under it. Moving the pointer on crashed
    /// Luna, asking the table for a row past its end.
    func testLeavingARowThatIsGoneDoesNotCrash() throws {
        let controller = try list()
        controller.setHovered(controller.list.rows.count - 1)
        controller.show(saved: [], today: [.tab(looseTab)], essentials: [], activeTabID: looseTab.id)
        controller.table.layoutSubtreeIfNeeded()
        controller.setHovered(nil)
        XCTAssertNil(controller.hoveredRow)
    }

    /// A tinted plate the column no longer tracks is taken away on the next
    /// pass rather than left standing with nothing in it.
    func testAnOwnerlessAgentPlateIsSweptAway() throws {
        let controller = try list()
        let stray = RowPillView(role: .folder)
        stray.tint = Tokens.Agent.tint(forApp: "claude-code")
        stray.frame = NSRect(x: 8, y: 40, width: 240, height: 35)
        controller.table.addSubview(stray)
        controller.movePills(animated: false)
        XCTAssertEqual(stray.alphaValue, 0, accuracy: 0.01, "the ownerless plate stayed in the column")
    }
}
