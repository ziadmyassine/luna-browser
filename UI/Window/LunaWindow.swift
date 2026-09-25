//
//  LunaWindow.swift
//  Luna
//
//  The browser window. The one thing it changes is minimising in fullscreen,
//  where the yellow light is kept lit (`TrafficLightLayoutManager.applyPressability`)
//  and its press has to come to nothing: a fullscreen window cannot be
//  minimised, and AppKit's answer to being asked anyway is not one Luna chose.
//

import AppKit

final class LunaWindow: NSWindow {

    override func miniaturize(_ sender: Any?) {
        guard !styleMask.contains(.fullScreen) else { return }
        super.miniaturize(sender)
    }

    override func performMiniaturize(_ sender: Any?) {
        guard !styleMask.contains(.fullScreen) else { return }
        super.performMiniaturize(sender)
    }
}
