//
//  TopBarStripLayoutTests.swift
//  LunaTests
//
//  §4's strip, laid out over a real session: where each chip lands, and what a
//  folder's plate covers.
//
//  `TopBarStripRunTests` asserts the arrangement; this asserts the frames it
//  turns into, and that they are the column's own parts in the column's own
//  sizes — a tile the grid's shape, a row a pill's height, one selected pill.
//
//  Nothing here wakes a tab, so nothing here builds a web view.
//

@testable import BrowserKit
import XCTest
@testable import Luna

@MainActor
final class TopBarStripLayoutTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = URL.temporaryDirectory.appending(path: "luna-tests-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    /// A folder standing open is one object on the bar: its name, a divider,
    /// then its tabs edge to edge, all on a plate of its own that holds
    /// nothing else.
    func testAnOpenFolderStandsOnItsOwnPlateWithADividerAfterItsName() async throws {
        let session = try await session()
        let window = window(on: session)
        let space = try XCTUnwrap(session.spaces.first).id
        let members = (0 ..< 2).map { insert(tab: "In \($0)", order: $0, in: space, on: session) }
        let folder = try XCTUnwrap(session.createGroup(name: "Work", containing: members))
        let loose = insert(tab: "Loose", order: 9, in: space, on: session)

        let strip = laidOut(session: session, window: window)
        let header = try XCTUnwrap(view(folder, in: strip))
        let first = try XCTUnwrap(view(members[0], in: strip))
        let second = try XCTUnwrap(view(members[1], in: strip))
        let outside = try XCTUnwrap(view(loose, in: strip))
        XCTAssertEqual(first.frame.maxX, second.frame.minX, "a folder's tabs stand edge to edge")
        // As wide as a loose tab with the same title: a fixed, narrower width
        // cut every title in a folder short with the bar half empty.
        XCTAssertEqual(first.frame.width, outside.frame.width)

        let divider = try XCTUnwrap(strip.dividers[folder])
        XCTAssertFalse(divider.isHidden)
        XCTAssertGreaterThan(divider.frame.minX, header.frame.maxX)
        XCTAssertLessThan(divider.frame.maxX, first.frame.minX, "the divider stands between the name and the tabs")

        let plate = try XCTUnwrap(strip.folderPlates[folder]).frame
        XCTAssertEqual(plate.minX, header.frame.minX)
        XCTAssertEqual(plate.maxX, second.frame.maxX)
        XCTAssertEqual(plate.height, TopBarMetrics.lineHeight)
        XCTAssertFalse(plate.intersects(outside.frame), "the plate holds the folder and nothing else")
        XCTAssertEqual(outside.frame.minX - plate.maxX, TopBarMetrics.gap)
    }

    /// Folded, the same folder is its header and nothing else — its tabs are
    /// not drawn at all, so nothing is left behind to click, and no divider.
    func testAFoldedFolderDrawsNoneOfItsTabs() async throws {
        let session = try await session()
        let window = window(on: session)
        let space = try XCTUnwrap(session.spaces.first).id
        let members = (0 ..< 2).map { insert(tab: "In \($0)", order: $0, in: space, on: session) }
        let folder = try XCTUnwrap(session.createGroup(name: "Work", containing: members))
        session.setGroupCollapsed(true, forGroup: folder)

        let strip = laidOut(session: session, window: window)
        XCTAssertNotNil(view(folder, in: strip))
        for member in members {
            XCTAssertNil(view(member, in: strip), "a folded folder is still drawing its tabs")
        }
        XCTAssertEqual(strip.dividers[folder]?.isHidden, true)
    }

    /// Shutting a folder on screen is one movement: its plate morphs down to
    /// the name as the run slides, rather than holding its width until the
    /// tabs have faded and then snapping — which read as the bar lagging.
    func testShuttingAFolderMorphsItsPlateDownAtOnce() async throws {
        let session = try await session()
        let window = window(on: session)
        let space = try XCTUnwrap(session.spaces.first).id
        let members = (0 ..< 2).map { insert(tab: "In \($0)", order: $0, in: space, on: session) }
        let folder = try XCTUnwrap(session.createGroup(name: "Work", containing: members))
        let strip = laidOut(session: session, window: window)
        let plate = try XCTUnwrap(strip.folderPlates[folder])

        session.setGroupCollapsed(true, forGroup: folder)
        strip.reload()
        strip.layoutSubtreeIfNeeded()

        XCTAssertTrue(strip.shrinkingPlates.isEmpty, "the pass that shut the folder started the morph")
        if Tokens.Motion.reduceMotion {
            let header = try XCTUnwrap(view(folder, in: strip))
            XCTAssertEqual(plate.frame.maxX, header.frame.maxX, "with Reduce Motion the plate lands at once")
        } else {
            XCTAssertTrue(plate.isMorphing, "the plate held its width instead of shrinking with the run")
        }
    }

    /// Kept tabs are §3.3's own tiles, on the plate after the Space's name;
    /// open ones are §3.4's rows after the plate, one gap on. The plate and
    /// the rows stand at the capsule's height, the tiles at a capsule item's.
    func testKeptTabsAreTilesOnThePlateAndOpenOnesAreRowsAfterIt() async throws {
        let session = try await session()
        let window = window(on: session)
        let space = try XCTUnwrap(session.spaces.first).id
        let kept = insert(tab: "Kept", order: 0, in: space, on: session)
        let open = insert(tab: "Open", order: 1, in: space, on: session)
        XCTAssertTrue(session.pinTab(kept))

        let strip = laidOut(session: session, window: window)
        let tile = try XCTUnwrap(view(kept, in: strip) as? GlassButton)
        let row = try XCTUnwrap(view(open, in: strip) as? TopBarTabRow)
        XCTAssertEqual(tile.frame.size, TopBarMetrics.keptTile.size)
        XCTAssertEqual(row.frame.height, TopBarMetrics.lineHeight)
        XCTAssertEqual(row.frame.width, TopBarMetrics.tabWidth)

        let plate = strip.plate.frame
        XCTAssertEqual(plate.height, TopBarMetrics.lineHeight)
        // The Space's name has its own capsule now, so the plate starts
        // where its first box does.
        XCTAssertEqual(tile.frame.minX, plate.minX, "the plate starts where its first box does")
        XCTAssertEqual(tile.frame.height, plate.height, "the box fills the plate top to bottom")
        XCTAssertEqual(tile.frame.minY, plate.minY)
        XCTAssertEqual(plate.maxX, tile.frame.maxX, "the plate ends where its last box does")
        // The hairline between the pinned section and today's tabs, a gap
        // either side of it.
        XCTAssertFalse(strip.rule.isHidden)
        XCTAssertEqual(strip.rule.frame.minX - plate.maxX, TopBarMetrics.gap)
        XCTAssertEqual(row.frame.minX - strip.rule.frame.maxX, TopBarMetrics.gap)
        // The glow is drawn inside the tile, so a tile at the strip's own
        // edge keeps all of it.
        XCTAssertGreaterThanOrEqual(tile.frame.minX, 0)
    }

    /// A kept folder stands beside the Space's plate on a plate of its own,
    /// not on it, and the hairline comes after the whole pinned section.
    func testAKeptFolderStandsBesideTheSpacesPlate() async throws {
        let session = try await session()
        let window = window(on: session)
        let space = try XCTUnwrap(session.spaces.first).id
        let tile = insert(tab: "Tile", order: 0, in: space, on: session)
        let member = insert(tab: "Member", order: 1, in: space, on: session)
        let open = insert(tab: "Open", order: 2, in: space, on: session)
        XCTAssertTrue(session.pinTab(tile))
        let folder = try XCTUnwrap(session.createGroup(name: "Work", kind: .pinned, containing: [member]))

        let strip = laidOut(session: session, window: window)
        let spacePlate = strip.plate.frame
        let folderPlate = try XCTUnwrap(strip.folderPlates[folder]).frame
        XCTAssertEqual(spacePlate.maxX, try XCTUnwrap(view(tile, in: strip)).frame.maxX, "the Space's plate ends at its tiles")
        XCTAssertEqual(folderPlate.minX - spacePlate.maxX, TopBarMetrics.gap, "the kept folder stands beside it")
        // Within half a point: the hairline is snapped to whole points so it
        // stays one crisp line.
        XCTAssertEqual(strip.rule.frame.minX - folderPlate.maxX, TopBarMetrics.gap, accuracy: 0.5)
        XCTAssertGreaterThan(try XCTUnwrap(view(open, in: strip)).frame.minX, strip.rule.frame.maxX)
    }

    /// Two open tabs stand Dia's 4 pt apart, closer than the bar's gap
    /// between anything else, so the tabs read as one strip.
    func testOpenTabsStandATabGapApart() async throws {
        let session = try await session()
        let window = window(on: session)
        let space = try XCTUnwrap(session.spaces.first).id
        let first = insert(tab: "One", order: 0, in: space, on: session)
        let second = insert(tab: "Two", order: 1, in: space, on: session)

        let strip = laidOut(session: session, window: window)
        let one = try XCTUnwrap(view(first, in: strip))
        let two = try XCTUnwrap(view(second, in: strip))
        XCTAssertEqual(two.frame.minX - one.frame.maxX, TopBarMetrics.tabGap)
        XCTAssertLessThan(TopBarMetrics.tabGap, TopBarMetrics.gap)
    }

    /// The tab the window is showing carries §3.4's selected pill, standing
    /// exactly on its row — the one pill for the whole bar, not one per row.
    func testTheSelectedPillStandsOnTheWindowsOwnTab() async throws {
        let session = try await session()
        let window = window(on: session)
        let space = try XCTUnwrap(session.spaces.first).id
        _ = insert(tab: "First", order: 0, in: space, on: session)
        let second = insert(tab: "Second", order: 1, in: space, on: session)
        session.activateTab(second, inWindow: window)

        let strip = laidOut(session: session, window: window)
        let row = try XCTUnwrap(view(second, in: strip) as? TopBarTabRow)
        XCTAssertTrue(row.row.isSelected)
        XCTAssertEqual(strip.selectionPill.frame, row.frame)
        XCTAssertEqual(descendants(of: strip, ofType: RowPillView.self).count, 2, "one selected pill, one hover pill")
    }

    /// §3.4's read band: the selected tab's pill fills as its page is read,
    /// and a tab selected again shows where it was left. Through the session's
    /// observers, because the sidebar is alive beside the bar and a single
    /// callback on the page was theirs in turn.
    func testTheSelectedPillCarriesHowFarThePageHasBeenRead() async throws {
        let session = try await session()
        let window = window(on: session)
        let space = try XCTUnwrap(session.spaces.first).id
        let first = insert(tab: "First", order: 0, in: space, on: session)
        let second = insert(tab: "Second", order: 1, in: space, on: session)
        session.activateTab(second, inWindow: window)
        let bar = TopBarView(session: session, windowID: window)
        bar.frame = NSRect(x: 0, y: 0, width: 1400, height: Tokens.Metric.topBarHeight)
        bar.layoutSubtreeIfNeeded()

        let reading = try XCTUnwrap(session.controller(for: second))
        reading.setScrollProgress(0.4)
        XCTAssertEqual(bar.strip.selectionPill.progress ?? -1, 0.4, accuracy: 0.001)

        // A tab the window is not showing does not move the band.
        session.ensureController(for: try XCTUnwrap(session.tab(first))).setScrollProgress(0.9)
        XCTAssertEqual(bar.strip.selectionPill.progress ?? -1, 0.4, accuracy: 0.001)

        session.activateTab(first, inWindow: window)
        XCTAssertEqual(bar.strip.selectionPill.progress ?? -1, 0.9, accuracy: 0.001, "taken on arrival")
    }

    /// A new tab at the end of a full bar is brought wholly into view, and
    /// stays whole when the page's title arrives. Tabs were sized to their
    /// titles then, so it widened past the strip's edge and had to be
    /// scrolled to; every tab is `tabWidth` now, and the strip still follows
    /// the tab on screen through a change of size until the user scrolls.
    func testANewTabAtTheEndOfAFullBarIsWhollyInView() async throws {
        let session = try await session()
        let window = window(on: session)
        let space = try XCTUnwrap(session.spaces.first).id
        let ids = (0..<8).map { insert(tab: "Tab \($0)", order: $0, in: space, on: session) }
        let last = try XCTUnwrap(ids.last)
        session.activateTab(last, inWindow: window)
        let strip = TopBarTabStrip(session: session, windowID: window)
        strip.frame = NSRect(x: 0, y: 0, width: 600, height: Tokens.Metric.topBarHeight)
        strip.reload()
        strip.layoutSubtreeIfNeeded()

        // The live title, as `apply(_:for:)` hears it — no reload.
        var tab = try XCTUnwrap(session.tab(last))
        tab.title = "what is up - Google Search, and then some more"
        session.list.update(tab)
        strip.apply(TabState(title: tab.title), for: last)
        strip.layoutSubtreeIfNeeded()

        let row = try XCTUnwrap(view(last, in: strip))
        let shown = strip.scrollView.contentView.bounds
        XCTAssertEqual(row.frame.width, TopBarMetrics.tabWidth, "the title changed the tab's width")
        XCTAssertLessThanOrEqual(row.frame.maxX, shown.maxX + 0.5, "the new tab runs past the strip")
        XCTAssertGreaterThanOrEqual(row.frame.minX, shown.minX - 0.5)
    }

    /// §30.9 on the bar: the tabs travel with the fingers, one point per point
    /// of a Space's swipe, and fade as they go — and are back, whole, at rest.
    func testTheTabsTravelWithASpaceSwipe() async throws {
        let session = try await session()
        let window = window(on: session)
        let space = try XCTUnwrap(session.spaces.first).id
        _ = insert(tab: "One", order: 0, in: space, on: session)
        let bar = TopBarView(session: session, windowID: window)
        bar.frame = NSRect(x: 0, y: 0, width: 1400, height: Tokens.Metric.topBarHeight)
        bar.layoutSubtreeIfNeeded()
        let layer = try XCTUnwrap(bar.strip.content.layer)

        bar.slideTabs(0.5)
        XCTAssertEqual(layer.affineTransform().tx, -0.5 * bar.spaceName.swipeSpan, accuracy: 0.5)
        XCTAssertEqual(layer.opacity, 0.5, accuracy: 0.01)

        bar.slideTabs(0)
        XCTAssertEqual(layer.affineTransform().tx, 0)
        XCTAssertEqual(layer.opacity, 1)
    }

    // MARK: - Fixtures

    private func session() async throws -> BrowserSession {
        let store = try BrowserStore(path: directory.appending(path: "\(UUID().uuidString).sqlite"))
        return try await BrowserSession.restored(store: store)
    }

    private func window(on session: BrowserSession) -> UUID {
        let id = UUID()
        session.openWindow(id)
        return id
    }

    private func insert(tab title: String, order: Int, in space: UUID, on session: BrowserSession) -> UUID {
        let tab = Tab(
            spaceID: space,
            kind: .today,
            url: URL(string: "https://example.com/\(order)")!,
            title: title,
            order: order
        )
        session.persistAll(session.list.insert(tab))
        return tab.id
    }

    /// Wide enough that nothing overflows and the run's own order is what the
    /// frames report.
    private func laidOut(session: BrowserSession, window: UUID) -> TopBarTabStrip {
        let strip = TopBarTabStrip(session: session, windowID: window)
        strip.frame = NSRect(x: 0, y: 0, width: 1400, height: Tokens.Metric.topBarHeight)
        strip.reload()
        strip.layoutSubtreeIfNeeded()
        return strip
    }

    /// The tile or row drawing `id`, or nil when the bar is not drawing it.
    private func view(_ id: UUID, in root: NSView) -> NSView? {
        for sub in root.subviews {
            if sub.identifier?.rawValue == id.uuidString, sub.superview != nil { return sub }
            if let found = view(id, in: sub) { return found }
        }
        return nil
    }

    private func descendant<T: NSView>(of root: NSView, ofType type: T.Type) -> T? {
        descendants(of: root, ofType: type).first { !$0.isHidden }
    }

    private func descendants<T: NSView>(of root: NSView, ofType type: T.Type) -> [T] {
        root.subviews.flatMap { view in
            ((view as? T).map { [$0] } ?? []) + descendants(of: view, ofType: type)
        }
    }
}
