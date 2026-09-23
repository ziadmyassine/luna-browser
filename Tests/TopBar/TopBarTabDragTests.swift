//
//  TopBarTabDragTests.swift
//  LunaTests
//
//  §6.6 on §4's bar, driven end to end: a real window, a real bar, mouse
//  events posted into the window's queue, and the bar's own tracking loop
//  consuming them — then the session asked where the tab went.
//
//  `TopBarStripRunTests` asserts what each half of each chip means. This
//  asserts that a hand moving across those halves ends in that meaning: the
//  gap resolution, the lift, the settle and the commit, in one pass. A drag is
//  exactly the thing that looks right on screen and lands one slot off.
//
//  Nothing here wakes a tab, so nothing here builds a web view.
//

import BrowserKit
import XCTest
@testable import Luna

@MainActor
final class TopBarTabDragTests: XCTestCase {

    private var directory: URL!
    private var window: NSWindow!

    override func setUpWithError() throws {
        directory = URL.temporaryDirectory.appending(path: "luna-tests-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        window?.orderOut(nil)
        window = nil
        try? FileManager.default.removeItem(at: directory)
    }

    func testATabCarriedPastTheLastOneLandsAtTheEnd() async throws {
        let (session, bar, space) = try await fixture()
        let tabs = ["One", "Two", "Three"].enumerated().map { insert($1, order: $0, in: space, on: session) }
        bar.refresh()
        bar.layoutSubtreeIfNeeded()

        try drag(tabs[0], in: bar, toTrailingHalfOf: tabs[2])
        try await settle { session.slots(inTier: .today).compactMap(\.tabID) == [tabs[1], tabs[2], tabs[0]] }
    }

    func testATabCarriedOntoAFoldersHeaderGoesInsideIt() async throws {
        let (session, bar, space) = try await fixture()
        let member = insert("Member", order: 0, in: space, on: session)
        let folder = try XCTUnwrap(session.createGroup(name: "Work", containing: [member]))
        let loose = insert("Loose", order: 5, in: space, on: session)
        bar.refresh()
        bar.layoutSubtreeIfNeeded()

        try drag(loose, in: bar, toTrailingHalfOf: folder)
        try await settle { session.tab(loose)?.groupID == folder }
        XCTAssertEqual(session.members(ofGroup: folder).first?.id, loose, "past the header is the front of the folder")
    }

    /// Across the hairline among §3.3's circles is pinning it.
    func testATabCarriedAmongTheCirclesIsPinned() async throws {
        let (session, bar, space) = try await fixture()
        let kept = insert("Kept", order: 0, in: space, on: session)
        let open = insert("Open", order: 1, in: space, on: session)
        XCTAssertTrue(session.pinTab(kept))
        bar.refresh()
        bar.layoutSubtreeIfNeeded()

        try drag(open, in: bar, toTrailingHalfOf: kept)
        try await settle { session.tab(open)?.kind == .essential }
        XCTAssertEqual(session.favorites(inSpace: space).map(\.id), [kept, open])
    }

    /// Escape puts it back where it was: nothing is committed.
    func testEscapeLeavesEverythingWhereItWas() async throws {
        let (session, bar, space) = try await fixture()
        let tabs = ["One", "Two"].enumerated().map { insert($1, order: $0, in: space, on: session) }
        bar.refresh()
        bar.layoutSubtreeIfNeeded()

        try drag(tabs[0], in: bar, toTrailingHalfOf: tabs[1], cancelling: true)
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(session.slots(inTier: .today).compactMap(\.tabID), tabs)
    }

    // MARK: - The hand

    /// Posts a press-and-carry into the window's queue, then hands the press
    /// to the controller, whose loop is what reads the rest.
    private func drag(
        _ id: UUID,
        in bar: TopBarView,
        toTrailingHalfOf target: UUID,
        cancelling: Bool = false
    ) throws {
        let from = try XCTUnwrap(chip(id, in: bar))
        let to = try XCTUnwrap(chip(target, in: bar))
        let start = from.convert(NSPoint(x: from.bounds.midX, y: from.bounds.midY), to: nil)
        let goal = to.convert(NSPoint(x: to.bounds.maxX - 2, y: to.bounds.midY), to: nil)

        let steps = 12
        for step in 1 ... steps {
            let fraction = CGFloat(step) / CGFloat(steps)
            let point = NSPoint(x: start.x + (goal.x - start.x) * fraction, y: start.y)
            window.postEvent(mouse(.leftMouseDragged, at: point), atStart: false)
        }
        if cancelling {
            window.postEvent(escape(), atStart: false)
        } else {
            window.postEvent(mouse(.leftMouseUp, at: goal), atStart: false)
        }
        let lifted: TopBarLifted = bar.session.group(id) == nil ? .tab(id) : .group(id)
        bar.drag?.track(lifted, from: from, event: mouse(.leftMouseDown, at: start))
    }

    private func mouse(_ type: NSEvent.EventType, at point: NSPoint) -> NSEvent {
        NSEvent.mouseEvent(
            with: type,
            location: point,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: type == .leftMouseUp ? 0 : 1
        ) ?? NSEvent()
    }

    private func escape() -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "\u{1b}",
            charactersIgnoringModifiers: "\u{1b}",
            isARepeat: false,
            keyCode: 53
        ) ?? NSEvent()
    }

    /// The lift settles on a spring before it commits, so the drop lands a
    /// beat after the mouse comes up.
    private func settle(_ landed: () -> Bool) async throws {
        for _ in 0 ..< 40 where !landed() {
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertTrue(landed(), "the drop never landed")
    }

    // MARK: - Fixtures

    private func fixture() async throws -> (BrowserSession, TopBarView, UUID) {
        let store = try BrowserStore(path: directory.appending(path: "\(UUID().uuidString).sqlite"))
        let session = try await BrowserSession.restored(store: store)
        let id = UUID()
        session.openWindow(id)
        session.setKeyWindow(id)
        let bar = TopBarView(session: session, windowID: id)
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: Tokens.Metric.topBarHeight),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = bar
        window.orderFrontRegardless()
        bar.layoutSubtreeIfNeeded()
        return (session, bar, try XCTUnwrap(session.spaces.first).id)
    }

    private func insert(_ title: String, order: Int, in space: UUID, on session: BrowserSession) -> UUID {
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

    private func chip(_ id: UUID, in root: NSView) -> TopBarButton? {
        if let button = root as? TopBarButton, button.identifier?.rawValue == id.uuidString { return button }
        for sub in root.subviews {
            if let found = chip(id, in: sub) { return found }
        }
        return nil
    }
}
