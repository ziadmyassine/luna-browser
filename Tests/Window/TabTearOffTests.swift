//
//  TabTearOffTests.swift
//  LunaTests
//
//  §6.6's way out of the list: when a lifted tab leaves it, what it carries,
//  where a new window for it stands, and that moving it to another window
//  moves the page rather than loading it again.
//
//  The drag itself is AppKit's and runs only under a real pointer; what it
//  decides with is asserted here.
//

import AppKit
import BrowserKit
import XCTest
@testable import Luna

@MainActor
final class TabTearOffTests: XCTestCase {

    private var directory: URL!
    private let distance = Tokens.Metric.tabTearOffDistance
    private let window = NSRect(x: 0, y: 0, width: 1200, height: 800)
    private let column = NSRect(x: 0, y: 0, width: 280, height: 800)

    override func setUpWithError() throws {
        directory = URL.temporaryDirectory.appending(path: "luna-tearoff-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - The lock holds

    /// A reorder never tears: the hand can wander across the whole column,
    /// and a little past its edge, and the tab stays in the list.
    func testAReorderInsideTheColumnNeverLeavesTheList() {
        for x in stride(from: column.minX, through: column.maxX + distance - 1, by: 20) {
            XCTAssertFalse(tears(NSPoint(x: x, y: 400), run: column, along: .vertical), "torn off at x \(x)")
        }
        XCTAssertFalse(tears(NSPoint(x: column.maxX + distance - 0.5, y: 400), run: column, along: .vertical))
    }

    func testAPullClearOfTheColumnLeavesIt() {
        XCTAssertTrue(tears(NSPoint(x: column.maxX + distance, y: 400), run: column, along: .vertical))
        XCTAssertTrue(tears(NSPoint(x: column.minX - distance, y: 400), run: column, along: .vertical))
    }

    /// Past the top or the foot of the window is a reorder overshooting, until
    /// it is clearly out of the window.
    func testOutOfTheWindowCountsOnlyOnceItIsClearlyOut() {
        XCTAssertFalse(tears(NSPoint(x: 140, y: -(distance - 1)), run: column, along: .vertical))
        XCTAssertTrue(tears(NSPoint(x: 140, y: -distance), run: column, along: .vertical))
        XCTAssertTrue(tears(NSPoint(x: 140, y: window.maxY + distance), run: column, along: .vertical))
    }

    /// §4's bar is the same rule on its side: along the bar is a reorder, down
    /// into the page is the way out.
    func testTheBarIsLockedAcrossItsLine() {
        let bar = NSRect(x: 0, y: 748, width: 1200, height: 52)
        XCTAssertFalse(tears(NSPoint(x: 1100, y: 770), run: bar, along: .horizontal))
        XCTAssertFalse(tears(NSPoint(x: 10, y: bar.minY - distance + 1), run: bar, along: .horizontal))
        XCTAssertTrue(tears(NSPoint(x: 600, y: bar.minY - distance), run: bar, along: .horizontal))
        XCTAssertTrue(tears(NSPoint(x: window.maxX + distance, y: 770), run: bar, along: .horizontal))
    }

    // MARK: - What it carries

    /// Finder names the .webloc after the page; everything else gets the
    /// address. Nothing over the desktop, so Finder leaves nothing there.
    func testTheLinkGoesToOtherAppsAndNotToTheDesktop() {
        let link = "https://example.com/page"
        XCTAssertEqual(TabTearOff.string(for: .URL, link: link, name: "Page", overDesktop: false), link)
        XCTAssertEqual(TabTearOff.string(for: .string, link: link, name: "Page", overDesktop: false), link)
        XCTAssertEqual(TabTearOff.string(for: TabTearOff.urlNameType, link: link, name: "Page", overDesktop: false), "Page")
        XCTAssertNil(TabTearOff.string(for: .URL, link: link, name: "Page", overDesktop: true))
    }

    /// Finder's icons and the wallpaper stand below every app's windows.
    func testTheDesktopIsAnythingBelowTheAppsWindows() {
        XCTAssertTrue(TabTearOff.isDesktopLayer(-2_147_483_603), "Finder's desktop icons")
        XCTAssertTrue(TabTearOff.isDesktopLayer(-2_147_483_625), "the wallpaper")
        XCTAssertFalse(TabTearOff.isDesktopLayer(0), "an ordinary window")
        XCTAssertFalse(TabTearOff.isDesktopLayer(20), "the Dock")
    }

    /// A tab carries its link, and Luna's own drop targets must not open that
    /// link as a second copy of the tab being moved.
    func testLunasOwnDropTargetsRefuseATab() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("TabTearOffTests-\(UUID().uuidString)"))
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString(UUID().uuidString, forType: TabTearOff.tabType)
        item.setString("https://example.com/", forType: .URL)
        pasteboard.writeObjects([item])
        XCTAssertEqual(WindowDrop.pages(on: pasteboard), [])
    }

    // MARK: - A window of its own

    /// Held where the hand held the window the tab came out of.
    func testTheNewWindowStandsWhereItWasLetGo() {
        let visible = NSRect(x: 0, y: 0, width: 1512, height: 944)
        let frame = AppDelegate.tornOffFrame(
            size: NSSize(width: 900, height: 600), droppedAt: NSPoint(x: 700, y: 500), grab: NSPoint(x: 100, y: 200), on: visible
        )
        XCTAssertEqual(frame, NSRect(x: 600, y: 100, width: 900, height: 600))
    }

    /// And kept on the screen: a drop near an edge does not hang the window
    /// off it, and a window bigger than the screen comes down to it.
    func testTheNewWindowStaysOnTheScreen() {
        let visible = NSRect(x: 0, y: 0, width: 1512, height: 944)
        let corner = AppDelegate.tornOffFrame(
            size: NSSize(width: 900, height: 600), droppedAt: NSPoint(x: 1500, y: 20), grab: NSPoint(x: 100, y: 200), on: visible
        )
        XCTAssertTrue(visible.contains(corner), "\(corner) is off the screen")
        let huge = AppDelegate.tornOffFrame(
            size: NSSize(width: 3000, height: 2000), droppedAt: NSPoint(x: 700, y: 500), grab: .zero, on: visible
        )
        XCTAssertEqual(huge, visible)
    }

    /// The tab goes on the other window's card and off this one's, which
    /// moves to the row beside it — and the page is the same page, not a
    /// fresh load of its address.
    func testMovingATabToAnotherWindowKeepsItsPage() async throws {
        let session = try await session()
        let source = UUID()
        let target = UUID()
        session.openWindow(source)
        session.openWindow(target)
        let space = try XCTUnwrap(session.spaces.first).id
        let tabs = (0 ..< 3).map { index in
            Tab(spaceID: space, kind: .today, url: URL(string: "https://example.com/\(index)")!, order: index)
        }
        for tab in tabs { session.persistAll(session.list.insert(tab)) }
        session.activateTab(tabs[1].id, inWindow: source)
        let page = try XCTUnwrap(session.controller(for: tabs[1].id))

        session.showTab(tabs[1].id, onlyInWindow: target)

        XCTAssertEqual(session.activeTabID(inWindow: target), tabs[1].id)
        XCTAssertNotEqual(session.activeTabID(inWindow: source), tabs[1].id, "both windows are showing the tab")
        XCTAssertNotNil(session.activeTabID(inWindow: source), "the window it left is showing nothing")
        XCTAssertTrue(session.controller(for: tabs[1].id) === page, "the page was rebuilt")
    }

    /// A window standing in another Space goes to the tab's.
    func testAWindowInAnotherSpaceGoesToTheTabsSpace() async throws {
        let session = try await session()
        let target = UUID()
        session.openWindow(target)
        let home = try XCTUnwrap(session.spaces.first).id
        let other = try await session.createSpace(name: "Other")
        session.switchSpace(other.id, inWindow: target)
        XCTAssertEqual(session.activeSpaceID(inWindow: target), other.id)
        let tab = Tab(spaceID: home, kind: .today, url: URL(string: "https://example.com/")!, order: 0)
        session.persistAll(session.list.insert(tab))

        session.showTab(tab.id, onlyInWindow: target)

        XCTAssertEqual(session.activeSpaceID(inWindow: target), home)
        XCTAssertEqual(session.activeTabID(inWindow: target), tab.id)
    }

    /// The window a page has moved to keeps it when the window it left picks
    /// something else to show: that window's card no longer holds it.
    func testAPageThatMovedIsNotTakenBackOffItsNewCard() {
        let left = ContentCardView()
        let right = ContentCardView()
        let page = NSView()
        left.setContent(page)
        right.setContent(page)
        XCTAssertTrue(page.superview === right)

        left.setContent(NSView())
        XCTAssertTrue(page.superview === right, "the window it left took it off the card it moved to")
    }

    // MARK: - Helpers

    private func tears(_ pointer: NSPoint, run: NSRect, along axis: TabTearOff.Axis) -> Bool {
        TabTearOff.hasTornOff(pointer: pointer, run: run, along: axis, window: window)
    }

    private func session() async throws -> BrowserSession {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = try BrowserStore(path: directory.appending(path: "luna.sqlite"))
        try await store.seedIfEmpty()
        return try await BrowserSession.restored(store: store)
    }
}
