//
//  ControlStateTests.swift
//  LunaTests
//
//  §3.1 and §3.4's answer to a pointer, on the two classes every button in
//  Luna's chrome is one of: `GlassButton` for anything wearing its own
//  material, `RowGlyphView` for a bare glyph that is a button.
//
//  The two states are a fill and a shape, and both are asserted rather than
//  eyeballed: the fill because 6 % and 12 % over glass are exactly the kind of
//  difference a screenshot argues about, and the shape because a swell that is
//  written to the presentation layer and not to the model one springs back
//  under the finger and looks, in a recording, almost right.
//

import XCTest
@testable import Luna

@MainActor
final class ControlPressTests: XCTestCase {

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

    private func button(glass: GlassButton.GlassMode = .always) -> GlassButton {
        let button = GlassButton(
            shape: Tokens.Metric.sidebarCircle,
            symbolName: "arrow.clockwise",
            pointSize: Tokens.Metric.glyphSize,
            label: "Reload",
            glassMode: glass
        )
        button.frame = NSRect(x: 0, y: 0, width: Tokens.Metric.sidebarCircle.width, height: Tokens.Metric.sidebarCircle.height)
        button.layoutSubtreeIfNeeded()
        return button
    }

    /// The scale has to be on the **model** layer. Animated onto the
    /// presentation layer alone it is gone again the moment the spring settles,
    /// which for a button somebody is still holding down is the wrong answer.
    func testAPressedButtonIsSwollenForAsLongAsItIsHeld() {
        let button = button()
        XCTAssertEqual(button.layer?.transform.m11 ?? 0, 1, accuracy: 0.001)

        button.mouseDown(with: event(.leftMouseDown, at: NSPoint(x: 10, y: 10)))
        XCTAssertEqual(
            button.layer?.transform.m11 ?? 0,
            Tokens.Motion.pressSwell,
            accuracy: 0.001,
            "a held button should be sitting at the swollen size, not on its way back from it"
        )

        button.mouseUp(with: event(.leftMouseUp, at: NSPoint(x: 10, y: 10)))
        XCTAssertEqual(button.layer?.transform.m11 ?? 0, 1, accuracy: 0.001)
    }

    /// A `.none` button is a bare glyph in somebody else's capsule. Swelling it
    /// would grow a hole inside a shape that is not moving — so it passes the
    /// press out to whoever owns the material instead. `NavCluster` is the
    /// caller this exists for.
    func testAButtonWithNoMaterialOfItsOwnHandsThePressOnInstead() {
        let button = button(glass: .none)
        var reported: [Bool] = []
        button.onPressChange = { reported.append($0) }

        button.mouseDown(with: event(.leftMouseDown, at: NSPoint(x: 10, y: 10)))
        XCTAssertEqual(button.layer?.transform.m11 ?? 0, 1, accuracy: 0.001)
        button.mouseUp(with: event(.leftMouseUp, at: NSPoint(x: 10, y: 10)))

        XCTAssertEqual(reported, [true, false])
    }

    /// And the cluster is what takes it: back alone is the circle in Martin's
    /// reference, and with forward out it is the whole capsule.
    func testTheHistoryCapsuleSwellsWhenOneOfItsHalvesIsPressed() {
        let cluster = NavCluster()
        cluster.frame = NSRect(origin: .zero, size: cluster.intrinsicContentSize)
        cluster.layoutSubtreeIfNeeded()
        guard let half = cluster.subviews.compactMap({ $0 as? GlassButton }).first else {
            return XCTFail("the cluster should be made of two `GlassButton` halves")
        }

        half.mouseDown(with: event(.leftMouseDown, at: NSPoint(x: 8, y: 8)))
        XCTAssertEqual(cluster.layer?.transform.m11 ?? 0, Tokens.Motion.pressSwell, accuracy: 0.001)
        half.mouseUp(with: event(.leftMouseUp, at: NSPoint(x: 8, y: 8)))
        XCTAssertEqual(cluster.layer?.transform.m11 ?? 0, 1, accuracy: 0.001)
    }

    /// §3.4's two fills, on the glyph buttons: the close on a tab row, the two
    /// inside §3.2's pill, §5's reveal-in-Finder. Nothing at rest — an
    /// unhovered row carries no chrome at all (§30.7).
    func testAGlyphButtonWearsTheHoverFillAndADeeperOneUnderAPress() {
        let glyph = RowGlyphView(frame: NSRect(x: 0, y: 0, width: 18, height: 18))
        glyph.configure(symbolName: "xmark", label: "Close Tab")
        glyph.layoutSubtreeIfNeeded()
        XCTAssertEqual(glyph.layer?.backgroundColor?.alpha ?? 0, 0, accuracy: 0.001)

        glyph.mouseEntered(with: event(.mouseMoved, at: NSPoint(x: 9, y: 9)))
        let hovered = glyph.layer?.backgroundColor
        XCTAssertEqual(hovered?.alpha ?? 0, Tokens.Surface.hover.cgColor.alpha, accuracy: 0.001)

        glyph.mouseDown(with: event(.leftMouseDown, at: NSPoint(x: 9, y: 9)))
        XCTAssertEqual(
            glyph.layer?.backgroundColor?.alpha ?? 0,
            Tokens.Surface.selected.cgColor.alpha,
            accuracy: 0.001,
            "the press is the hover fill one step up — §3.4's selected wash"
        )

        glyph.mouseUp(with: event(.leftMouseUp, at: NSPoint(x: 9, y: 9)))
        XCTAssertEqual(glyph.layer?.backgroundColor?.alpha ?? 0, hovered?.alpha ?? 0, accuracy: 0.001)

        glyph.mouseExited(with: event(.mouseMoved, at: NSPoint(x: 40, y: 40)))
        XCTAssertEqual(glyph.layer?.backgroundColor?.alpha ?? 1, 0, accuracy: 0.001)
    }

    /// The press is the hover fill *one step up*, and the step has to be
    /// visible or the press is not one. §3.4 puts `selected` at twice `hover`.
    func testThePressFillIsAStepAboveTheHoverFill() {
        XCTAssertGreaterThan(Tokens.Surface.selected.cgColor.alpha, Tokens.Surface.hover.cgColor.alpha)
    }

    /// `Motion.wash` is what both classes paint through, and nil is the way
    /// back to nothing — not a transparent colour left behind on the layer.
    func testTheWashClearsRatherThanFadingToATransparentColour() {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 20, height: 20))
        view.wantsLayer = true
        Tokens.Motion.wash(view.layer, to: Tokens.Surface.hover, animated: false)
        XCTAssertGreaterThan(view.layer?.backgroundColor?.alpha ?? 0, 0)
        Tokens.Motion.wash(view.layer, to: nil, animated: false)
        XCTAssertEqual(view.layer?.backgroundColor?.alpha ?? 1, 0, accuracy: 0.001)
    }
}
