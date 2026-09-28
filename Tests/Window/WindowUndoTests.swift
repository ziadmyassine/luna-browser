//
//  WindowUndoTests.swift
//  LunaTests
//
//  ⌘Z in a browser window undoes what was done in the browser. The window
//  answers `undo:` itself, ahead of the app delegate, so its list has to be
//  the session's — and once that list is empty, ⌘Z brings back what was
//  hidden on the page.
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

    /// The list first; only once it is empty does ⌘Z bring back what was
    /// hidden on the page, one each time.
    func testTheSessionsListFallsBackOnlyWhenItIsEmpty() {
        let list = SessionUndoManager()
        var hidden = 2
        list.canUndoWhenEmpty = { hidden > 0 }
        list.whenEmpty = {
            guard hidden > 0 else { return false }
            hidden -= 1
            return true
        }
        let step = Step()
        list.registerUndo(withTarget: step) { $0.undone = true }

        XCTAssertTrue(list.canUndo)
        list.undo()
        XCTAssertTrue(step.undone)
        XCTAssertEqual(hidden, 2, "the fallback ran before the list was empty")
        list.undo()
        list.undo()
        XCTAssertEqual(hidden, 0)
        XCTAssertFalse(list.canUndo)
    }
}
