//
//  SpaceDotPressTests.swift
//  LunaTests
//
//  §3.5's dots answering a pointer, which until now they did not: a dot took a
//  click and said nothing at all until the Space had already changed.
//
//  The answer is §3.4's two washes on a chip the size of the dot's slot, and
//  §6's swell — on the pill, because a 6 pt mark has no material of its own
//  to press. That is `NavCluster`'s rule, and this file is the same three
//  assertions `ControlStateTests` makes about the chevrons in it.
//

import XCTest
import BrowserKit
@testable import Luna

@MainActor
final class SpaceDotPressTests: XCTestCase {

    private func event(_ type: NSEvent.EventType, at point: NSPoint) -> NSEvent {
        NSEvent.mouseEvent(
            with: type,
            location: point,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        )!
    }

    private func space(_ name: String) -> Space {
        Space(name: name, symbolName: "square.grid.2x2", gradient: .defaultSpace)
    }

    private func dot() -> SpaceDotView {
        let dot = SpaceDotView(space: space("Work"), position: 1, of: 2)
        dot.frame = NSRect(x: 0, y: 0, width: Tokens.Metric.spaceDotPitch, height: Tokens.Metric.spaceDotsPill.height)
        dot.markCentreX = Tokens.Metric.spaceDotPitch / 2
        dot.layoutSubtreeIfNeeded()
        dot.updateLayer()
        return dot
    }

    /// The chip is the layer under the mark, and the mark is the one inside it.
    private func chip(_ dot: SpaceDotView) -> CALayer? {
        dot.layer?.sublayers?.first { !($0 is CAGradientLayer) }
    }

    /// Nothing at rest, `Surface.hover` under the pointer, `Surface.selected`
    /// under a press, and back down the same steps.
    func testADotWearsTheHoverWashAndADeeperOneUnderAPress() {
        let dot = dot()
        guard let chip = chip(dot) else { return XCTFail("the dot should carry a chip under its mark") }
        XCTAssertEqual(chip.backgroundColor?.alpha ?? 0, 0, accuracy: 0.001, "§30.7: nothing at rest")

        dot.mouseEntered(with: event(.mouseMoved, at: NSPoint(x: 7, y: 11)))
        XCTAssertEqual(chip.backgroundColor?.alpha ?? 0, Tokens.Surface.hover.cgColor.alpha, accuracy: 0.001)

        dot.mouseDown(with: event(.leftMouseDown, at: NSPoint(x: 7, y: 11)))
        XCTAssertEqual(
            chip.backgroundColor?.alpha ?? 0,
            Tokens.Surface.selected.cgColor.alpha,
            accuracy: 0.001,
            "the press is the hover wash one step up — §3.4's selected"
        )

        dot.mouseUp(with: event(.leftMouseUp, at: NSPoint(x: 7, y: 11)))
        XCTAssertEqual(chip.backgroundColor?.alpha ?? 0, Tokens.Surface.hover.cgColor.alpha, accuracy: 0.001)

        dot.mouseExited(with: event(.mouseMoved, at: NSPoint(x: 40, y: 40)))
        XCTAssertEqual(chip.backgroundColor?.alpha ?? 1, 0, accuracy: 0.001)
    }

    /// The chip is the slot, not the mark: a 6 pt hover target is no target,
    /// and it is centred on the mark rather than in the slot, which is the
    /// alignment rule the whole strip is built on.
    func testTheChipIsTheDotsWholeSlotCentredOnTheMark() {
        let dot = dot()
        guard let chip = chip(dot) else { return XCTFail("no chip") }
        XCTAssertEqual(chip.frame.width, Tokens.Metric.spaceDotChip, accuracy: 0.001)
        XCTAssertEqual(chip.frame.midX, dot.markCentreX, accuracy: 0.5)
        XCTAssertEqual(chip.frame.midY, dot.bounds.midY, accuracy: 0.5)
        XCTAssertEqual(chip.cornerRadius, Tokens.Metric.spaceDotChip / 2, accuracy: 0.001)
    }

    /// A dot has no material of its own, so it hands the press to the pill —
    /// and the pill is what swells. `NavCluster` for the chevrons, this for the
    /// dots, one rule.
    func testThePressIsHandedToThePillWhichIsWhatSwells() {
        let strip = SpaceDotsView(frame: NSRect(x: 0, y: 0, width: 56, height: Tokens.Metric.spaceDotsPill.height))
        let spaces = [space("Work"), space("Home")]
        strip.show(spaces: spaces, activeSpaceID: spaces[0].id)
        strip.layoutSubtreeIfNeeded()
        guard let dot = strip.subviews.compactMap({ $0 as? SpaceDotView }).first else {
            return XCTFail("the strip should hold one view per Space")
        }
        XCTAssertEqual(strip.layer?.transform.m11 ?? 0, 1, accuracy: 0.001)

        dot.mouseDown(with: event(.leftMouseDown, at: NSPoint(x: 7, y: 11)))
        XCTAssertEqual(
            strip.layer?.transform.m11 ?? 0,
            Tokens.Motion.pressSwell,
            accuracy: 0.001,
            "a held dot should leave the pill sitting swollen, not on its way back"
        )
        XCTAssertEqual(dot.layer?.transform.m11 ?? 0, 1, accuracy: 0.001, "the dot itself does not scale")

        dot.mouseUp(with: event(.leftMouseUp, at: NSPoint(x: 7, y: 11)))
        XCTAssertEqual(strip.layer?.transform.m11 ?? 0, 1, accuracy: 0.001)
    }

    /// A pointer that slides off the dot with the button still down is no
    /// longer pressing it, and the pill has to settle before the mouse comes up.
    func testThePressLetsGoWhenThePointerLeavesTheDot() {
        let dot = dot()
        var reported: [Bool] = []
        dot.onPressChange = { reported.append($0) }

        dot.mouseDown(with: event(.leftMouseDown, at: NSPoint(x: 7, y: 11)))
        dot.mouseDragged(with: event(.leftMouseDragged, at: NSPoint(x: 200, y: 11)))
        XCTAssertEqual(reported, [true, false])
        XCTAssertEqual(chip(dot)?.backgroundColor?.alpha ?? 1, 0, accuracy: 0.001)

        dot.mouseDragged(with: event(.leftMouseDragged, at: NSPoint(x: 7, y: 11)))
        XCTAssertEqual(reported, [true, false, true], "and it comes back when the pointer does")
    }

    /// AppKit sends no `mouseExited` while a button is down, so a release off
    /// the dot has to put the chip out itself — and must not switch Space.
    func testAReleaseOffTheDotClearsTheChipAndDoesNotActivate() {
        let dot = dot()
        var activated = 0
        dot.onActivate = { activated += 1 }

        dot.mouseEntered(with: event(.mouseMoved, at: NSPoint(x: 7, y: 11)))
        dot.mouseDown(with: event(.leftMouseDown, at: NSPoint(x: 7, y: 11)))
        dot.mouseUp(with: event(.leftMouseUp, at: NSPoint(x: 400, y: 11)))

        XCTAssertEqual(activated, 0, "a press that slid off the dot is a press the user called off")
        XCTAssertEqual(chip(dot)?.backgroundColor?.alpha ?? 1, 0, accuracy: 0.001)
    }
}
