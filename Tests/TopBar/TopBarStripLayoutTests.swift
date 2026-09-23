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

import BrowserKit
import XCTest
@testable import Luna

@MainActor
final class TopBarStripLayoutTests: XCTestCase {

    private var directory: URL!
    /// The live setting, put back afterwards. These tests measure where
    /// things land, and where a run starts is `Settings.tabsPosition` — a
    /// machine set to Left would otherwise move every assertion.
    private var storedPosition: TabsPosition!

    override func setUpWithError() throws {
        storedPosition = Settings.tabsPosition
        Settings.tabsPosition = .centre
        directory = URL.temporaryDirectory.appending(path: "luna-tests-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        Settings.tabsPosition = storedPosition
        try? FileManager.default.removeItem(at: directory)
    }

    /// A folder standing open: its tabs follow its header, and §3.4b's spine
    /// runs under them and under nothing else.
    func testAnOpenFoldersTabsFollowItWithTheSpineUnderThem() async throws {
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
        XCTAssertLessThan(header.frame.maxX, first.frame.minX)
        XCTAssertLessThan(first.frame.maxX, second.frame.minX)

        let spine = try XCTUnwrap(descendant(of: strip, ofType: TopBarFolderSpine.self))
        XCTAssertFalse(spine.isHidden)
        XCTAssertGreaterThan(spine.frame.minX, header.frame.maxX, "the spine is under the header")
        XCTAssertLessThan(spine.frame.minX, first.frame.maxX)
        XCTAssertLessThanOrEqual(spine.frame.maxX, second.frame.maxX)
        XCTAssertLessThan(spine.frame.maxY, first.frame.minY, "the spine is over the pills, not under them")
        XCTAssertFalse(spine.frame.intersects(outside.frame))
    }

    /// Folded, the same folder is its header and nothing else — its tabs are
    /// not drawn at all, so nothing is left behind to click, and no spine.
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
        XCTAssertTrue(descendants(of: strip, ofType: TopBarFolderSpine.self).allSatisfy(\.isHidden))
    }

    /// Kept tabs are §3.3's own tiles, in the grid's shape, in front of the
    /// hairline; open ones are §3.4's rows after it.
    func testKeptTabsAreTheGridsTilesAndOpenOnesAreRows() async throws {
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
        XCTAssertEqual(row.frame.height, Tokens.Metric.rowPillHeight)

        let hairline = try XCTUnwrap(descendant(of: strip, ofType: TopBarSeparator.self))
        XCTAssertFalse(hairline.isHidden)
        XCTAssertLessThan(tile.frame.maxX, hairline.frame.minX)
        XCTAssertGreaterThan(row.frame.minX, hairline.frame.maxX)
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
