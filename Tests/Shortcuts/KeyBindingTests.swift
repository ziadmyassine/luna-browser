//
//  KeyBindingTests.swift
//  LunaTests
//
//  §3.6's value type: what a keystroke looks like stored, printed, and read off
//  an event.
//
//  Every test here is a shape that broke something during the first build of
//  this: `+` splitting a stored string in half, an arrow arriving as a
//  private-use scalar that does not survive a string round trip, and shift being
//  spelled two ways so a recorded shortcut and a declared one compared unequal.
//

import AppKit
import XCTest
@testable import Luna

@MainActor
final class KeyBindingTests: XCTestCase {

    /// ⌘+ is a real shortcut (Zoom In), and its stored form is `"cmd++"`.
    /// Splitting that on every `+` gives an empty key — which is why the parser
    /// cuts at the last separator.
    func testAPlusSurvivesBeingStored() throws {
        let zoomIn = KeyBinding("+")
        XCTAssertEqual(zoomIn.stored, "cmd++")
        XCTAssertEqual(KeyBinding(stored: zoomIn.stored), zoomIn)
    }

    /// An arrow is `NSLeftArrowFunctionKey` — a scalar in the private-use plane,
    /// not a character anybody can type into a plist. It is escaped going out
    /// and rebuilt coming back.
    func testAnArrowSurvivesBeingStored() throws {
        let previousSpace = KeyBinding(function: NSLeftArrowFunctionKey, [.control, .option])
        XCTAssertEqual(previousSpace.display, "⌃⌥←")
        let restored = try XCTUnwrap(KeyBinding(stored: previousSpace.stored))
        XCTAssertEqual(restored, previousSpace)
        XCTAssertEqual(restored.display, "⌃⌥←")
    }

    func testEveryShippedBindingSurvivesBeingStored() throws {
        for command in BrowserCommand.all {
            for binding in command.defaults {
                XCTAssertEqual(
                    KeyBinding(stored: binding.stored), binding,
                    "\(command.id)'s \(binding.display) did not survive a round trip"
                )
            }
        }
    }

    /// The normalisation the whole feature rests on: shift is a modifier, never
    /// a capital letter. Two spellings of ⇧⌘T that compare unequal means the
    /// conflict check misses and two menu items end up on one keystroke.
    func testShiftLivesInTheMaskAndNotInTheLetter() {
        let recorded = KeyBinding("T", [.command, .shift])
        XCTAssertEqual(recorded.key, "t")
        XCTAssertEqual(recorded, KeyBinding("t", [.command, .shift]))
        XCTAssertNotEqual(recorded, KeyBinding("t", .command))
        XCTAssertEqual(recorded.display, "⇧⌘T")
    }

    /// AppKit's own order, which is the order the menu prints and therefore the
    /// order the table has to print.
    func testDisplayUsesAppKitsModifierOrder() {
        XCTAssertEqual(KeyBinding("c", [.command, .option, .shift]).display, "⌥⇧⌘C")
        XCTAssertEqual(KeyBinding("k", [.command, .option]).display, "⌥⌘K")
    }

    /// Anything outside ⌘ ⌥ ⌃ ⇧ is dropped rather than stored — Caps Lock and
    /// the numeric-keypad flag both ride along on a real event.
    func testStrayModifiersAreNotPartOfTheKeystroke() {
        let noisy = KeyBinding("t", [.command, .capsLock, .numericPad])
        XCTAssertEqual(noisy, KeyBinding("t", .command))
    }

    // MARK: - Recording

    /// §3.6's floor: a menu key equivalent fires wherever the app is focused,
    /// so a shortcut with no ⌘, ⌃ or ⌥ would be taken out of the address bar
    /// and out of every text field on every page.
    func testALetterOnItsOwnIsNotAShortcut() {
        XCTAssertNil(KeyBinding(event: Self.keyDown("t", [])))
        XCTAssertNil(KeyBinding(event: Self.keyDown("T", .shift)), "shift alone is still typing")
    }

    func testAModifiedKeystrokeIsRecordedAsPressed() throws {
        let event = Self.keyDown("N", [.command, .shift])
        let recorded = try XCTUnwrap(KeyBinding(event: event))
        XCTAssertEqual(recorded, KeyBinding("n", [.command, .shift]))
        XCTAssertEqual(recorded.display, "⇧⌘N")
    }

    /// `charactersIgnoringModifiers` reports the character the layout makes,
    /// so ⇧⌘[ arrives as `{` on a US keyboard. Recorded as pressed, because
    /// that is what AppKit will be matching the event against — see
    /// `KeyBinding`'s header.
    func testAShiftedSymbolIsRecordedAsTheLayoutReportsIt() throws {
        let recorded = try XCTUnwrap(KeyBinding(event: Self.keyDown("{", [.command, .shift])))
        XCTAssertEqual(recorded.key, "{")
        XCTAssertTrue(recorded.modifiers.contains(.shift))
    }

    private static func keyDown(_ characters: String, _ flags: NSEvent.ModifierFlags) -> NSEvent {
        // `keyCode` is not read by anything under test; the characters are.
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: flags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: 0
        )!
    }
}
