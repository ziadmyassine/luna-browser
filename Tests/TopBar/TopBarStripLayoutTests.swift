//
//  TopBarStripLayoutTests.swift
//  LunaTests
//
//  §4's strip, laid out over a real session: where each chip lands, and what a
//  folder's plate covers.
//
//  `TopBarStripRunTests` asserts the arrangement; this asserts the frames it
//  turns into, which is the half that cannot be reasoned about — a folder's
//  plate is sized from its header and its open tabs, and a plate that is a few
//  points short reads as a folder whose last tab has fallen out of it.
//
//  Nothing here wakes a tab, so nothing here builds a web view.
//

import BrowserKit
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

    /// A folder standing open: its plate has to hold the header and both tabs,
    /// and nothing outside it may be standing on it.
    func testAnOpenFoldersPlateHoldsItsHeaderAndItsTabs() async throws {
        let session = try await session()
        let window = window(on: session)
        let space = try XCTUnwrap(session.spaces.first).id
        let members = (0 ..< 2).map { insert(tab: "In \($0)", order: $0, in: space, on: session) }
        let folder = try XCTUnwrap(session.createGroup(name: "Work", containing: members))
        let loose = insert(tab: "Loose", order: 9, in: space, on: session)

        let strip = laidOut(session: session, window: window)
        let plate = try XCTUnwrap(descendant(of: strip, ofType: TopBarGroupPlate.self))
        let header = try XCTUnwrap(chip(folder, in: strip))

        XCTAssertTrue(plate.frame.contains(header.frame), "the folder's header is off its own plate")
        for member in members {
            let row = try XCTUnwrap(chip(member, in: strip))
            XCTAssertTrue(plate.frame.contains(row.frame), "a tab in the folder is off its plate")
        }
        let outside = try XCTUnwrap(chip(loose, in: strip))
        XCTAssertFalse(plate.frame.intersects(outside.frame), "a loose tab is standing on the folder's plate")
    }

    /// Folded, the same folder is its header and nothing else — the tabs are
    /// not drawn at all, so nothing is left behind the plate to click.
    func testAFoldedFolderDrawsNoneOfItsTabs() async throws {
        let session = try await session()
        let window = window(on: session)
        let space = try XCTUnwrap(session.spaces.first).id
        let members = (0 ..< 2).map { insert(tab: "In \($0)", order: $0, in: space, on: session) }
        let folder = try XCTUnwrap(session.createGroup(name: "Work", containing: members))
        session.setGroupCollapsed(true, forGroup: folder)

        let strip = laidOut(session: session, window: window)
        let plate = try XCTUnwrap(descendant(of: strip, ofType: TopBarGroupPlate.self))
        let header = try XCTUnwrap(chip(folder, in: strip))

        XCTAssertTrue(plate.frame.contains(header.frame))
        for member in members {
            XCTAssertNil(chip(member, in: strip), "a folded folder is still drawing its tabs")
        }
    }

    /// §4's hairline stands between what is kept and what is not, and every
    /// kept tab is in front of it.
    func testTheHairlineStandsBetweenTheTwoRuns() async throws {
        let session = try await session()
        let window = window(on: session)
        let space = try XCTUnwrap(session.spaces.first).id
        let kept = insert(tab: "Kept", order: 0, in: space, on: session)
        let open = insert(tab: "Open", order: 1, in: space, on: session)
        XCTAssertTrue(session.pinTab(kept))

        let strip = laidOut(session: session, window: window)
        let hairline = try XCTUnwrap(descendant(of: strip, ofType: TopBarSeparator.self))
        XCTAssertFalse(hairline.isHidden)
        XCTAssertLessThan(try XCTUnwrap(chip(kept, in: strip)).frame.maxX, hairline.frame.minX)
        XCTAssertGreaterThan(try XCTUnwrap(chip(open, in: strip)).frame.minX, hairline.frame.maxX)
    }

    /// The tab the window is showing wears §3.4's selected plate, and it is the
    /// only one that does.
    func testOnlyTheWindowsOwnTabIsSelected() async throws {
        let session = try await session()
        let window = window(on: session)
        let space = try XCTUnwrap(session.spaces.first).id
        let first = insert(tab: "First", order: 0, in: space, on: session)
        let second = insert(tab: "Second", order: 1, in: space, on: session)
        session.activateTab(second, inWindow: window)

        let strip = laidOut(session: session, window: window)
        XCTAssertTrue(try XCTUnwrap(chip(second, in: strip)).isSelected)
        XCTAssertFalse(try XCTUnwrap(chip(first, in: strip)).isSelected)
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

    private func chip(_ id: UUID, in strip: NSView) -> TopBarButton? {
        descendants(of: strip, ofType: TopBarButton.self)
            .first { $0.identifier?.rawValue == id.uuidString }
    }

    private func descendant<T: NSView>(of root: NSView, ofType type: T.Type) -> T? {
        descendants(of: root, ofType: type).first { !$0.isHidden }
    }

    private func descendants<T: NSView>(of root: NSView, ofType type: T.Type) -> [T] {
        root.subviews.flatMap { view in
            (view as? T).map { [$0] } ?? [] + descendants(of: view, ofType: type)
        }
    }
}
