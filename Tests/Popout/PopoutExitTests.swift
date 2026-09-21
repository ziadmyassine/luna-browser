//
//  PopoutExitTests.swift
//  LunaTests
//
//  §6.4's pop-out leaving, which used to be `removeFromSuperview()` and is now
//  `animateIn` run backwards.
//
//  Three things can go wrong with an exit animation and none of them are
//  visible at the speed it runs. It can fold back to a different corner from
//  the one it grew out of, which reads as the panel sliding rather than
//  closing. It can keep swallowing clicks while it fades, so the press on the
//  button that closed it does nothing — the ordinary way anyone closes one of
//  these, and the failure looks like a button that has stopped working. And it
//  can fail to leave at all, which is a transparent sheet left over the page
//  forever.
//

import XCTest
@testable import Luna

@MainActor
final class PopoutExitTests: XCTestCase {

    private func panel(_ edge: PopoutEdge) -> PopoutPanelView {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 1070, height: 801))
        let panel = PopoutPanelView(frame: root.bounds, size: CGSize(width: 360, height: 340), edge: edge)
        root.addSubview(panel)
        panel.layoutSubtreeIfNeeded()
        return panel
    }

    /// It folds back into the corner it came out of. The anchor point is the
    /// whole of what makes the motion belong to the button — the same corner
    /// in both directions, up from §3.5's foot and down from §4's capsule.
    func testItFoldsBackIntoTheCornerItGrewOutOf() {
        for edge in [PopoutEdge.above, .below] {
            let opening = panel(edge)
            opening.animateIn()
            let corner = opening.body.layer?.anchorPoint
            let closing = panel(edge)
            closing.animateIn()
            closing.animateOut()
            XCTAssertEqual(closing.body.layer?.anchorPoint, corner, "the way out pivots somewhere else")
        }
    }

    /// A pop-out that is closing is not a surface any more. Its sheet covers
    /// the whole window, so a sheet that went on hit-testing for the length of
    /// the animation would eat the click on the button that closed it.
    func testAClosingPopOutStopsTakingClicks() {
        let panel = panel(.above)
        panel.animateIn()
        XCTAssertNotNil(panel.hitTest(NSPoint(x: 500, y: 400)), "an open pop-out has to take the click")
        panel.animateOut()
        XCTAssertNil(panel.hitTest(NSPoint(x: 500, y: 400)), "a closing pop-out is still eating clicks")
    }

    /// And it does leave. The removal is on the end of an animation rather
    /// than on the line that asked for it, which is exactly the shape of bug
    /// that leaves an invisible sheet over the page for the rest of the
    /// session.
    func testItTakesItselfOutOfTheTree() {
        let panel = panel(.below)
        panel.animateIn()
        let root = panel.superview
        XCTAssertNotNil(root)
        panel.animateOut()
        let gone = expectation(description: "the pop-out left the view tree")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            MainActor.assumeIsolated {
                if panel.superview == nil { gone.fulfill() }
            }
        }
        wait(for: [gone], timeout: 2)
    }
}
