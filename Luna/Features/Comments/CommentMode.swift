//
//  CommentMode.swift
//  Luna
//
//  ⇧⌘M's comment mode, one per window: point at an element, write a note on
//  it, and export the notes as a bundle an agent can read. Made the first time
//  it is asked for and dropped when it ends, so nothing is resident while the
//  mode is off. `docs/plans/COMMENT-MODE.md` is the brief.
//
//  The shell only, for now: `toggle()` flips `isOn` and `export()` writes
//  nothing until the picker and the bundle writer are wired in.
//

import AppKit

@MainActor
final class CommentMode {

    private(set) var isOn = false

    func toggle() {
        isOn.toggle()
    }

    func export() {}
}
