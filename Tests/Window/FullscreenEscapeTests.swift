//
//  FullscreenEscapeTests.swift
//  LunaTests
//
//  Leaving fullscreen takes two Escapes, the second while the first one's
//  toast is still down.
//

import AppKit
import XCTest
@testable import Luna

@MainActor
final class FullscreenEscapeTests: XCTestCase {

    func testOnePressDoesNotLeave() {
        var escape = DoubleEscape()
        XCTAssertFalse(escape.press(at: Date(timeIntervalSinceReferenceDate: 0)))
    }

    func testASecondPressInTimeLeaves() {
        var escape = DoubleEscape()
        let start = Date(timeIntervalSinceReferenceDate: 0)
        _ = escape.press(at: start)
        XCTAssertTrue(escape.press(at: start.addingTimeInterval(DoubleEscape.window / 2)))
    }

    /// Too late is a first press again, so the toast comes back and the next
    /// press in time leaves.
    func testALatePressStartsOver() {
        var escape = DoubleEscape()
        let start = Date(timeIntervalSinceReferenceDate: 0)
        _ = escape.press(at: start)
        let late = start.addingTimeInterval(DoubleEscape.window + 0.1)
        XCTAssertFalse(escape.press(at: late))
        XCTAssertTrue(escape.press(at: late.addingTimeInterval(0.2)))
    }

    /// Leaving uses both presses up: a third does not leave again.
    func testTheTwoPressesAreSpentOnLeaving() {
        var escape = DoubleEscape()
        let start = Date(timeIntervalSinceReferenceDate: 0)
        _ = escape.press(at: start)
        _ = escape.press(at: start.addingTimeInterval(0.2))
        XCTAssertFalse(escape.press(at: start.addingTimeInterval(0.4)))
    }

    /// The toast's glyph is a real SF Symbol, or the pill shows none.
    func testTheToastHasItsGlyph() {
        XCTAssertNotNil(NSImage(systemSymbolName: "escape", accessibilityDescription: nil))
    }

    /// Out of fullscreen Escape is AppKit's as before.
    func testOutOfFullscreenEscapeIsLeftAlone() {
        let window = LunaWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.titled], backing: .buffered, defer: true
        )
        window.cancelOperation(nil)
        XCTAssertFalse(window.styleMask.contains(.fullScreen))
    }
}
