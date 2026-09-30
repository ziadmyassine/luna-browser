//
//  LunaWindow.swift
//  Luna
//
//  The browser window. It changes two things about fullscreen. Minimising:
//  the yellow light is kept lit (`TrafficLightLayoutManager.applyPressability`)
//  and its press has to come to nothing, since a fullscreen window cannot be
//  minimised and AppKit's answer to being asked anyway is not one Luna chose.
//  And Escape: leaving takes two presses.
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

    private var escape = DoubleEscape()

    /// An Escape nothing else took reaches the window, and `NSWindow`'s own
    /// `cancelOperation` leaves fullscreen on it. One stray press — meant for a
    /// page, a field or a pop-out that had already closed — threw the window
    /// out of fullscreen, so it takes two: the first says so, the second
    /// leaves. A video in fullscreen is WebKit's own window and is not this.
    override func cancelOperation(_ sender: Any?) {
        guard styleMask.contains(.fullScreen) else { return super.cancelOperation(sender) }
        if escape.press() {
            PageToast.escapeAgain.putAway(in: self)
            super.cancelOperation(sender)
        } else {
            PageToast.escapeAgain.show(in: self)
        }
    }
}

/// The two presses: the second counts while the first one's toast is still
/// down to say what it will do.
struct DoubleEscape {

    static let window = Tokens.Motion.toastDwell

    private var first: Date?

    /// Whether this press is the second.
    mutating func press(at now: Date = Date()) -> Bool {
        if let first, now.timeIntervalSince(first) < Self.window {
            self.first = nil
            return true
        }
        first = now
        return false
    }
}
