//
//  WindowFrameMemoryTests.swift
//  LunaTests
//
//  §22.6: each window's frame, per screen setup — which setup this is, where a
//  frame may stand on it, and that each window comes back to its own.
//

import AppKit
import XCTest
@testable import Luna

@MainActor
final class WindowFrameMemoryTests: XCTestCase {

    private typealias Screen = WindowPlacement.Screen

    /// A 1512 × 982 laptop with a menu bar, and a 2560 × 1440 monitor to its right.
    private let laptop = Screen(
        frame: NSRect(x: 0, y: 0, width: 1512, height: 982),
        visibleFrame: NSRect(x: 0, y: 0, width: 1512, height: 949)
    )
    private let monitor = Screen(
        frame: NSRect(x: 1512, y: -200, width: 2560, height: 1440),
        visibleFrame: NSRect(x: 1512, y: -200, width: 2560, height: 1440)
    )

    private var suite: String!
    private var defaults: UserDefaults!
    private var screens: [Screen] = []
    private var windows: [NSWindow] = []

    override func setUpWithError() throws {
        suite = "luna.tests.WindowFrameMemory.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        screens = [laptop]
    }

    override func tearDownWithError() throws {
        for window in windows { window.close() }
        windows = []
        defaults.removePersistentDomain(forName: suite)
    }

    // MARK: - The setup

    func testTheSetupIsTheDisplaysArrangement() {
        XCTAssertEqual(WindowPlacement.setupKey([laptop, monitor]), WindowPlacement.setupKey([monitor, laptop]))
        XCTAssertNotEqual(WindowPlacement.setupKey([laptop]), WindowPlacement.setupKey([laptop, monitor]))
        var moved = monitor
        moved.frame.origin = NSPoint(x: -2560, y: 0)
        XCTAssertNotEqual(
            WindowPlacement.setupKey([laptop, monitor]), WindowPlacement.setupKey([laptop, moved]),
            "the monitor on the other side is another desk"
        )
        var docked = laptop
        docked.visibleFrame.size.height -= 80
        XCTAssertEqual(
            WindowPlacement.setupKey([laptop]), WindowPlacement.setupKey([docked]),
            "the Dock appearing made a new setup"
        )
    }

    // MARK: - Fitting

    func testAFrameOnScreenStaysWhereItIs() {
        let frame = NSRect(x: 2000, y: 100, width: 1200, height: 800)
        XCTAssertEqual(WindowPlacement.fit(frame, onto: [laptop, monitor]), frame)
    }

    func testAFrameHangingOffAnEdgeIsBroughtIn() throws {
        let frame = NSRect(x: 1000, y: 400, width: 1200, height: 800)
        let fitted = try XCTUnwrap(WindowPlacement.fit(frame, onto: [laptop]))
        XCTAssertEqual(fitted.size, frame.size)
        XCTAssertTrue(laptop.visibleFrame.contains(fitted))
    }

    func testAFrameTooBigForTheScreenIsShrunkToIt() throws {
        let frame = NSRect(x: 1600, y: -100, width: 2400, height: 1300)
        let fitted = try XCTUnwrap(WindowPlacement.fit(frame, onto: [laptop]))
        XCTAssertTrue(laptop.visibleFrame.contains(fitted))
        XCTAssertEqual(fitted.width, laptop.visibleFrame.width)
        XCTAssertEqual(fitted.height, laptop.visibleFrame.height)
    }

    /// The monitor has gone: the window comes to the main screen at its own
    /// size, centred, not to wherever its old corner falls.
    func testAFrameOnAGoneDisplayLandsOnTheMainScreen() throws {
        let frame = NSRect(x: 2200, y: 300, width: 1000, height: 700)
        let fitted = try XCTUnwrap(WindowPlacement.fit(frame, onto: [laptop]))
        XCTAssertEqual(fitted.size, frame.size)
        XCTAssertEqual(fitted.midX, laptop.visibleFrame.midX, accuracy: 1)
        XCTAssertEqual(fitted.midY, laptop.visibleFrame.midY, accuracy: 1)
        XCTAssertNil(WindowPlacement.fit(frame, onto: []))
    }

    // MARK: - Remembering

    /// Two windows, two frames, and each comes back to its own after a relaunch.
    func testEachWindowComesBackToItsOwnFrame() throws {
        let memory = makeMemory()
        let first = makeWindow(), second = makeWindow()
        XCTAssertFalse(memory.register(first), "a window with nothing remembered was moved")
        memory.register(second)
        XCTAssertEqual(memory.slot(of: first), 0)
        XCTAssertEqual(memory.slot(of: second), 1)
        let frames = [NSRect(x: 40, y: 60, width: 900, height: 700), NSRect(x: 500, y: 100, width: 800, height: 600)]
        first.setFrame(frames[0], display: false)
        second.setFrame(frames[1], display: false)

        let relaunched = makeMemory()
        let again = [makeWindow(), makeWindow()]
        XCTAssertTrue(relaunched.register(again[0]))
        XCTAssertTrue(relaunched.register(again[1]))
        XCTAssertEqual(again.map(\.frame), frames)
    }

    /// A slot freed by a closed window is the next one's, so a window opened
    /// after closing the first goes where the first was.
    func testAClosedWindowsSlotIsTakenAgain() {
        let memory = makeMemory()
        let first = makeWindow(), second = makeWindow()
        memory.register(first)
        memory.register(second)
        first.close()
        let third = makeWindow()
        memory.register(third)
        XCTAssertEqual(memory.slot(of: third), 0)
    }

    /// The laptop on its own and the laptop at the desk keep a frame each,
    /// and plugging the monitor back in puts the window back on it.
    func testEachSetupKeepsItsOwnFrame() {
        let memory = makeMemory()
        let window = makeWindow()
        memory.register(window)
        let alone = NSRect(x: 100, y: 100, width: 1000, height: 700)
        window.setFrame(alone, display: false)

        screens = [laptop, monitor]
        memory.screensChanged()
        let desk = NSRect(x: 2000, y: 0, width: 1800, height: 1100)
        window.setFrame(desk, display: false)

        screens = [laptop]
        memory.screensChanged()
        XCTAssertEqual(window.frame, alone)
        screens = [laptop, monitor]
        memory.screensChanged()
        XCTAssertEqual(window.frame, desk)
    }

    /// AppKit moves a window off a display that has gone before Luna hears
    /// that the screens changed; that move is not the user's frame for the
    /// laptop on its own.
    func testAMoveWhileTheScreensAreChangingIsNotSaved() throws {
        screens = [laptop, monitor]
        let memory = makeMemory()
        let window = makeWindow()
        memory.register(window)
        window.setFrame(NSRect(x: 2000, y: 0, width: 1800, height: 1100), display: false)

        screens = [laptop]
        window.setFrame(NSRect(x: 0, y: 0, width: 1512, height: 949), display: false)
        XCTAssertNil(memory.frame(slot: 0, setup: WindowPlacement.setupKey([laptop])))
        memory.screensChanged()
        let saved = try XCTUnwrap(memory.frame(slot: 0, setup: WindowPlacement.setupKey([laptop])))
        XCTAssertTrue(laptop.visibleFrame.contains(saved))
    }

    /// The first launch after frames went per setup opens where AppKit's
    /// autosave last had the window.
    func testTheOldAutosavedFrameIsReadOnce() {
        defaults.set("120 80 1100 760 0 0 1512 949 ", forKey: WindowFrameMemory.legacyKey)
        let memory = makeMemory()
        let window = makeWindow()
        XCTAssertTrue(memory.register(window))
        XCTAssertEqual(window.frame, NSRect(x: 120, y: 80, width: 1100, height: 760))
    }

    // MARK: - Fixtures

    private func makeMemory() -> WindowFrameMemory {
        WindowFrameMemory(defaults: defaults) { [unowned self] in screens }
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled, .resizable], backing: .buffered, defer: true
        )
        window.isReleasedWhenClosed = false
        windows.append(window)
        return window
    }
}
