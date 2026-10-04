//
//  LunaWebView+Focus.swift
//  Luna
//
//  A page cannot take the keyboard from a field in Luna's own chrome.
//
//  A page that focuses one of its inputs as it loads — a search page, a
//  sign-in form — has WebKit make its web view first responder, and the field
//  being typed into goes dead mid-word: ⌘T's bar, Find, a tab being renamed.
//  The page gets the keyboard when the user gives it: a click into it, Tab out
//  of the field, or Luna handing it over (`takeFocus`).
//

import AppKit

extension LunaWebView {

    /// Luna's own hand-over: the Command Bar closing, Find putting the page
    /// back, a page staged for Luna Control.
    @discardableResult
    func takeFocus() -> Bool {
        isTakingFocusDeliberately = true
        defer { isTakingFocusDeliberately = false }
        return window?.makeFirstResponder(self) ?? false
    }

    /// Whether the page may take the keyboard now. Asked by `LunaWindow` before
    /// the field gives it up: by the time the page's own `becomeFirstResponder`
    /// runs, the field has already resigned and nothing is left to protect.
    func mayTakeFocus() -> Bool {
        guard !isTakingFocusDeliberately, let window, Self.chromeFieldIsTyping(in: window) else { return true }
        return Self.userIsGivingFocus(to: self, in: window)
    }

    /// One of Luna's text fields has the keyboard. A page's own inputs are
    /// drawn by WebKit and never borrow AppKit's field editor, so the field
    /// editor being first responder is always a field of Luna's.
    static func chromeFieldIsTyping(in window: NSWindow) -> Bool {
        (window.firstResponder as? NSTextView)?.isFieldEditor == true
    }

    /// The event being handled is the user's, aimed at this page: a press
    /// inside it, or Tab moving the keyboard on.
    static func userIsGivingFocus(to page: NSView, in window: NSWindow) -> Bool {
        guard let event = NSApp.currentEvent, event.window === window else { return false }
        switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            return page.bounds.contains(page.convert(event.locationInWindow, from: nil))
        case .keyDown:
            return event.keyCode == 48
        default:
            return false
        }
    }
}
