//
//  ButtonFeedbackTests.swift
//  LunaTests
//
//  Every button in Luna answers a press, and this is the list of them.
//
//  §3.1 has always said a hover lifts the fill and §6 has had `controlPress`
//  since the chrome got its washes — but a rule that lives only in prose is
//  applied by whoever remembers it, and the press reached the sidebar's own
//  buttons and then stopped: the top bar, both action capsules, Settings'
//  chevrons, its push button, the two appearance chips and the palette button
//  all shipped with a hover and nothing under the finger. Six months of
//  "every button" meaning "every button somebody checked".
//
//  So the register is here instead. A new button type that does not swell
//  fails this file, which is the only way a rule about all of something
//  survives the next person who adds one. See CLAUDE.md, "Buttons answer".
//
//  The swell is what is asserted, not the wash. Both are part of the
//  answer, but the wash is a colour on a layer that several of these controls
//  paint in different places — a plate, a subview, a gradient's ring — while
//  `Motion.swell` writes one transform to the control (or to the capsule that
//  owns its material) in every case. One assertion, no per-control exceptions.
//
//  Absent on purpose: §14.3's picker rows — `CredentialRowView` and
//  `PopoverActionRowView`. They are list rows under CLAUDE.md's rule, not
//  buttons: a full-width row growing 5 % reads as the list jumping. They answer
//  with a hover wash and nothing else, and belong here only if that rule
//  changes. §14.4's chip is built from `SettingsPushButton`, which is already
//  covered below.
//

import XCTest
@testable import Luna
@testable import BrowserKit

@MainActor
final class ButtonFeedbackTests: XCTestCase {

    /// `Motion.swell` writes the scale to the model layer, so it can be read
    /// back the moment the press lands — no animation to wait for.
    private func scale(of view: NSView) -> CGFloat {
        view.layer?.transform.m11 ?? 1
    }

    private func mouse(_ type: NSEvent.EventType, in view: NSView) -> NSEvent {
        NSEvent.mouseEvent(
            with: type,
            location: NSPoint(x: view.bounds.midX, y: view.bounds.midY),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        ) ?? NSEvent()
    }

    /// Down and up through the view's own handlers. Not `performClick`:
    /// that is the action, and what is being tested is the answer to the
    /// gesture, which happens on either side of it.
    private func press(_ view: NSView, then body: (CGFloat) -> Void) {
        view.mouseDown(with: mouse(.leftMouseDown, in: view))
        body(scale(of: view))
        view.mouseUp(with: mouse(.leftMouseUp, in: view))
    }

    private func sized(_ view: NSView, _ side: CGFloat = 28) -> NSView {
        view.frame = NSRect(x: 0, y: 0, width: side, height: side)
        view.layoutSubtreeIfNeeded()
        return view
    }

    // MARK: - The controls that carry their own material

    /// Each of these is a plate, a disc or a pill of its own, so each swells
    /// itself. A new one belongs in this list.
    func testEveryButtonThatOwnsItsMaterialSwellsUnderTheFinger() {
        let swell = Tokens.Motion.pressSwell
        let buttons: [(String, NSView)] = [
            ("GlassButton", GlassButton(
                shape: Tokens.Metric.bottomCircle,
                symbolName: "star",
                pointSize: Tokens.Metric.glyphSize,
                label: "Star"
            )),
            ("SpaceEditorButton", SpaceEditorButton(title: "Create Space")),
            ("SpaceSwatchChip", SpaceSwatchChip(gradient: .defaultSpace, label: "Blue")),
            ("SpaceSymbolChip", SpaceSymbolChip(symbolName: "moon.stars", label: "Moon")),
            ("SettingsChoiceButton", SettingsChoiceButton(title: "Light")),
            ("SpaceAppearanceButton", SpaceAppearanceButton())
        ]
        for (name, button) in buttons {
            press(sized(button)) { held in
                XCTAssertEqual(held, swell, accuracy: 0.001, "\(name) does not swell under a press")
            }
            XCTAssertEqual(scale(of: button), 1, accuracy: 0.001, "\(name) stays swollen after the release")
        }
    }

    // MARK: - The controls whose material belongs to a capsule

    /// A button inside a capsule hands the gesture up rather than growing a
    /// fifth of a point inside a shape that is not moving. What must be true
    /// is that something answers — and that it is the capsule.
    func testACapsuleAnswersOnBehalfOfTheButtonInsideIt() {
        let swell = Tokens.Motion.pressSwell

        let library = sized(SidebarActionCapsule(items: [
            (symbolName: "arrow.down.circle", label: "Downloads", action: {}),
            (symbolName: "clock", label: "History", action: {})
        ]), 68)
        guard let glyph = descendants(of: library, ofType: GlassButton.self).first else {
            return XCTFail("the library capsule has no buttons")
        }
        press(sized(glyph)) { held in
            XCTAssertEqual(held, 1, accuracy: 0.001, "a glyph with no material of its own swelled")
            XCTAssertEqual(scale(of: library), swell, accuracy: 0.001, "the library capsule did not answer")
        }
        XCTAssertEqual(scale(of: library), 1, accuracy: 0.001, "the library capsule stayed swollen")

        let nav = sized(SettingsNavCapsule(), 56)
        guard let chevron = descendants(of: nav, ofType: SettingsNavChevron.self).first else {
            return XCTFail("the nav capsule has no chevrons")
        }
        press(sized(chevron)) { held in
            XCTAssertEqual(held, 1, accuracy: 0.001, "a chevron with no material of its own swelled")
            XCTAssertEqual(scale(of: nav), swell, accuracy: 0.001, "the nav capsule did not answer")
        }
        XCTAssertEqual(scale(of: nav), 1, accuracy: 0.001, "the nav capsule stayed swollen")
    }

    // MARK: - The two `NSButton`s

    /// `TopBarButton` and `SettingsPushButton` take their press around
    /// `NSControl`'s tracking loop, which does not return until the mouse comes
    /// back up — so `mouseDown` would hang a test. `highlight(_:)` is AppKit's
    /// own name for the same state and the same override answers it.
    func testTheAppKitButtonsSwellWhenAppKitSaysTheyAreDown() {
        let swell = Tokens.Motion.pressSwell

        let tile = TopBarButton(metric: TopBarMetrics.tile, glass: false)
        _ = sized(tile)
        tile.highlight(true)
        XCTAssertEqual(scale(of: tile), swell, accuracy: 0.001, "a tab tile does not swell")
        tile.highlight(false)
        XCTAssertEqual(scale(of: tile), 1, accuracy: 0.001, "a tab tile stays swollen")

        let push = SettingsPushButton(title: "Reset", isDestructive: false)
        _ = sized(push, 60)
        push.highlight(true)
        XCTAssertEqual(scale(of: push), swell, accuracy: 0.001, "the push button does not swell")
        push.highlight(false)
        XCTAssertEqual(scale(of: push), 1, accuracy: 0.001, "the push button stays swollen")
    }

    /// §4's action capsule applies one material for all of its items, so its
    /// items hand the press up exactly as the sidebar's do.
    func testATopBarCapsuleItemHandsItsPressToTheCylinder() {
        let capsule = TopBarActionCapsule()
        capsule.items = [TopBarActionItem(id: "one", symbolName: "clock", label: "History", action: {})]
        _ = sized(capsule, 40)
        guard let item = descendants(of: capsule, ofType: TopBarButton.self).first else {
            return XCTFail("the capsule has no items")
        }
        item.highlight(true)
        XCTAssertEqual(scale(of: item), 1, accuracy: 0.001, "a capsule item swelled inside its own cylinder")
        XCTAssertEqual(scale(of: capsule), Tokens.Motion.pressSwell, accuracy: 0.001, "the cylinder did not answer")
        item.highlight(false)
        XCTAssertEqual(scale(of: capsule), 1, accuracy: 0.001, "the cylinder stayed swollen")
    }

    private func descendants<T: NSView>(of root: NSView, ofType type: T.Type) -> [T] {
        var found: [T] = []
        for child in root.subviews {
            if let match = child as? T { found.append(match) }
            found += descendants(of: child, ofType: type)
        }
        return found
    }
}
