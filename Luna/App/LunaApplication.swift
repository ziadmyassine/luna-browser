//
//  LunaApplication.swift
//  Luna
//
//  Luna's `NSApplication`, for the one thing only the application object
//  sees: key events WebKit hands back from a Luna Control stage, which the
//  main menu must never act on (`ControlStage.absorbs`).
//

import AppKit

final class LunaApplication: NSApplication {
    override func sendEvent(_ event: NSEvent) {
        if ControlStage.absorbs(event) { return }
        super.sendEvent(event)
    }
}
