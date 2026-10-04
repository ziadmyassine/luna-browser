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

    /// A page may not take the keyboard from a field in Luna's chrome — see
    /// `LunaWebView+Focus.swift`.
    override func makeFirstResponder(_ responder: NSResponder?) -> Bool {
        if let page = responder as? LunaWebView, !page.mayTakeFocus() { return false }
        return super.makeFirstResponder(responder)
    }

    /// An Escape nothing else took reaches the window, and `NSWindow`'s own
    /// `cancelOperation` leaves fullscreen on it. One stray press — meant for a
    /// page, a field or a pop-out that had already closed — threw the window
    /// out of fullscreen, so it takes two: the first says so, the second
    /// leaves. A video in fullscreen is WebKit's own window and is not this.
    override func cancelOperation(_ sender: Any?) {
        let app = NSApp.delegate as? AppDelegate
        if let session = app?.session, Self.escapeEndsHiding(in: session) { return }
        if Self.escapeClosesFind(app?.windows.first { $0.controller.window === self }?.find) { return }
        guard styleMask.contains(.fullScreen) else { return super.cancelOperation(sender) }
        if escape.press() {
            PageToast.escapeAgain.putAway(in: self)
            super.cancelOperation(sender)
        } else {
            PageToast.escapeAgain.show(in: self)
        }
    }
}

extension LunaWindow {

    /// One Escape ends hiding mode, wherever the keyboard is. The picker hears
    /// Escape in the page, and only while the page has focus; from the sidebar
    /// or a pop-out it came here instead and, in fullscreen, was taken for the
    /// first of the two presses that leave.
    /// - Returns: whether it did.
    static func escapeEndsHiding(in session: BrowserSession) -> Bool {
        guard session.isPickingElements else { return false }
        session.activeController?.stopPickingElements()
        return true
    }
}

extension LunaWindow {

    /// One Escape closes §18.1's find field with the keyboard in the page, as
    /// it does with the keyboard in the field — and is then not the first of
    /// the two that leave fullscreen either.
    /// - Returns: whether it did.
    static func escapeClosesFind(_ find: FindController?) -> Bool {
        guard let find, find.isOpen else { return false }
        find.close()
        return true
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
