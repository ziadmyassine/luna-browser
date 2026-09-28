//
//  WindowUndoTests.swift
//  LunaTests
//
//  ⌘Z in a browser window undoes what was done in the browser. The window
//  answers `undo:` itself, ahead of the app delegate, so its list has to be
//  the session's.
//

import AppKit
import XCTest
@testable import Luna

@MainActor
final class WindowUndoTests: XCTestCase {

    private final class Step {
        var undone = false
    }

    func testTheWindowUndoesFromTheListItIsGiven() throws {
        let controller = BrowserWindowController(remembersFrame: false)
        let list = UndoManager()
        controller.windowUndoManager = list
        let window = try XCTUnwrap(controller.window)
        XCTAssertTrue(window.undoManager === list)

        let step = Step()
        list.registerUndo(withTarget: step) { $0.undone = true }
        window.perform(Selector(("undo:")), with: nil)
        XCTAssertTrue(step.undone, "the window undid from a list of its own")
    }
}
