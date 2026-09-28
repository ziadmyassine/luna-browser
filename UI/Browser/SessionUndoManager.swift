//
//  SessionUndoManager.swift
//  Luna
//
//  The session's undo list, with one thing to do when it runs out: bring back
//  what was hidden on the page in front, the latest first.
//
//  A hidden part of a page is kept for good, and the list is not — it starts
//  empty at every launch. With no switch anywhere to show a hidden thing
//  again, ⌘Z is the only way back, so it has to reach hides from an earlier
//  visit as well as the ones still on the list.
//

import Foundation

final class SessionUndoManager: UndoManager {

    /// Runs when there is nothing on the list; says whether it did anything.
    var whenEmpty: (() -> Bool)?
    var canUndoWhenEmpty: (() -> Bool)?

    override var canUndo: Bool {
        super.canUndo || (canUndoWhenEmpty?() ?? false)
    }

    override func undo() {
        if super.canUndo {
            super.undo()
        } else {
            _ = whenEmpty?()
        }
    }
}
