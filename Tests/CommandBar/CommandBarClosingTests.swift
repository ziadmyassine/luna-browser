//
//  CommandBarClosingTests.swift
//  LunaTests
//
//  §9.1's bar leaving, which is `CommandBarOpeningTests` backwards and has to
//  stay that way.
//
//  Two placements, two endings, and the anchored one is the one with a claim
//  in it: the glass closes back down onto the pill it grew out of, and the
//  pill only comes back once it has. Unhidden any earlier and the address is
//  on screen twice on the same 34 pt — the exact thing hiding it was for.
//
//  The rest is about not leaving anything behind. The panel covers the window,
//  so a sheet that outlives its own animation is a dead layer over the page,
//  and one that is still hit-testing eats the next click.
//

import XCTest
@testable import Luna

@MainActor
final class CommandBarClosingTests: XCTestCase {

    private var window: NSWindow?

    /// A pill standing where §3.2b's does, in a real window — `anchorRect` is
    /// nil for a view that is not in one, and that is the floating bar.
    private func anchored() -> (CommandBarPanel, NSView) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        self.window = window
        let root = window.contentView!
        let pill = NSView(frame: NSRect(x: 390, y: 730, width: 420, height: 34))
        root.addSubview(pill)
        let results = CommandBarResultsView(frame: .zero)
        results.setResults(rows(8), selecting: nil)
        let panel = CommandBarPanel(
            frame: root.bounds,
            resultsView: results,
            anchor: CommandBarAnchor(view: pill)
        )
        root.addSubview(panel)
        return (panel, pill)
    }

    private func floating() -> CommandBarPanel {
        let results = CommandBarResultsView(frame: .zero)
        results.setResults(rows(8), selecting: nil)
        return CommandBarPanel(
            frame: NSRect(x: 0, y: 0, width: 1200, height: 800),
            resultsView: results
        )
    }

    private func rows(_ count: Int) -> [CommandBarResult] {
        (0..<count).map { index in
            CommandBarResult(
                source: .history,
                title: "Result \(index)",
                subtitle: "example\(index).com",
                action: .open(URL(string: "https://example\(index).com")!),
                url: URL(string: "https://example\(index).com")!,
                symbolName: "clock"
            )
        }
    }

    /// Opens an anchored bar and waits for it, so the close has a full-height
    /// list to close from.
    private func opened() -> (CommandBarPanel, NSView) {
        let (panel, pill) = anchored()
        panel.prepareToOpen()
        pill.isHidden = true
        panel.layoutSubtreeIfNeeded()
        let open = expectation(description: "the reveal finishes")
        panel.onOpened = { open.fulfill() }
        panel.animateIn()
        wait(for: [open], timeout: 2)
        panel.layoutSubtreeIfNeeded()
        return (panel, pill)
    }

    /// The glass ends where the reveal started: the pill's own frame. A close
    /// that ended anywhere else would be the bar folding into a place the pill
    /// is not.
    func testTheAnchoredBarClosesBackDownOntoItsPill() {
        let (panel, pill) = opened()
        XCTAssertGreaterThan(panel.body.frame.height, panel.inputHeight + 1, "nothing opened, so nothing can close")

        let closed = expectation(description: "the fold finishes")
        panel.onClosed = { closed.fulfill() }
        panel.animateOut()
        XCTAssertNotNil(panel.superview, "it vanished instead of closing")
        wait(for: [closed], timeout: 2)

        XCTAssertEqual(panel.body.frame.height, pill.frame.height, accuracy: 1)
        // The width is `morph`'s, and read off the pill only while the panel is
        // in the window it has now left.
        XCTAssertEqual(panel.morph, 0, accuracy: 0.001)
    }

    /// And the pill comes back at the end of that, not the start. The caller
    /// hangs it on `onClosed`, so what this asserts is the order: by the time
    /// anything is told, the bar is out of the window.
    func testThePillIsOnlyHandedBackOnceTheBarHasGone() {
        let (panel, pill) = opened()
        var superviewAtHandback: NSView??
        let closed = expectation(description: "the fold finishes")
        panel.onClosed = {
            superviewAtHandback = panel.superview
            pill.isHidden = false
            closed.fulfill()
        }
        panel.animateOut()
        XCTAssertTrue(pill.isHidden, "the pill is back while the bar is still standing on it")
        wait(for: [closed], timeout: 2)

        XCTAssertEqual(superviewAtHandback, .some(nil), "the bar was still in the window when the pill came back")
        XCTAssertFalse(pill.isHidden)
    }

    /// A bar that never opened has nothing to fold. It stands at the pill's
    /// height waiting for the store (`openWhenReady`), and 0.18 s of animating
    /// that to the height it already has is a press that appears to do nothing.
    func testABarThatNeverOpenedClosesAtOnce() {
        let (panel, _) = anchored()
        panel.prepareToOpen()
        panel.layoutSubtreeIfNeeded()
        panel.animateOut()
        XCTAssertNil(panel.superview, "a bar that never opened waited to close")
    }

    /// The floating bar covers the window, and a closing one is not a surface:
    /// the click that dismissed it must not be followed by a second one
    /// landing in a sheet that is on its way out.
    func testAClosingBarStopsTakingClicks() {
        let panel = floating()
        panel.prepareToOpen()
        panel.animateIn()
        XCTAssertNotNil(panel.hitTest(NSPoint(x: 40, y: 40)), "an open bar has to take the click")
        panel.animateOut()
        XCTAssertTrue(panel.isClosing)
        XCTAssertNil(panel.hitTest(NSPoint(x: 40, y: 40)), "a closing bar is still eating clicks")
    }

    /// And it does leave. The removal is on the end of an animation rather
    /// than on the line that asked for it, which is the shape of bug that
    /// leaves an invisible sheet over the page for the rest of the session.
    func testTheFloatingBarTakesItselfOutOfTheTree() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 1200, height: 800))
        let panel = floating()
        root.addSubview(panel)
        panel.prepareToOpen()
        panel.animateIn()

        let closed = expectation(description: "the bar left the view tree")
        panel.onClosed = { closed.fulfill() }
        panel.animateOut()
        wait(for: [closed], timeout: 2)
        XCTAssertNil(panel.superview)
    }
}
