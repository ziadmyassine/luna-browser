//
//  ControlStage.swift
//  Luna
//
//  Trusted input for Luna Control: a tab the user is not looking at is lent
//  to an off-screen window for the length of one call, and mouse and key
//  events are handed straight to its web view. The page sees them as a
//  person's (`isTrusted`), and nothing reaches the user's screen, focus,
//  pointer or menus. Measured by the Phase 0 spike; the recipe's parts are
//  load-bearing and `BrowserKit/Tests/ControlStageTests` holds each to it.
//
//  AppKit only, and no Luna types, so that test target can compile this
//  very file.
//

import AppKit
import LunaControl
import WebKit

/// Borderless, off every screen, and never key or main: it cannot take
/// focus from the user's window. It answers `isKeyWindow` all the same,
/// because WebKit decides whether the page has focus by asking, and a page
/// without focus drops typed keys.
final class ControlStageWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override var isKeyWindow: Bool { true }
}

@MainActor
final class ControlStage {

    static let shownMessage = """
    The user has this tab on screen, so Luna will not send it input: that would be typing into a page \
    someone is looking at. Wait until they leave it, or ask them.
    """

    let webView: WKWebView
    private let window: ControlStageWindow
    private let savedFrame: NSRect
    private let savedAutoresizing: Bool
    private var menuWatch: (any NSObjectProtocol)?
    private var released = false
    private var eventNumber = 0

    /// Every window that has been a stage, by number, with its web view.
    /// Kept after release because WebKit hands unhandled keys back to
    /// `NSApp.sendEvent` asynchronously, and a late Cmd+W must still be
    /// recognised as the agent's. ponytail: grows by one entry per trusted
    /// call; prune by age if that ever shows up.
    private static var stagedWindows: [Int: Weak] = [:]
    private struct Weak { weak var webView: WKWebView? }

    /// Refuses a web view that is in any window: in the user's, taking it
    /// would take their first responder; in another stage, a call is
    /// already driving it.
    init(adopting webView: WKWebView) throws {
        if webView.window is ControlStageWindow {
            throw ControlError("Another call is driving this tab. Wait for it to finish, then retry.")
        }
        guard webView.window == nil else { throw ControlError(Self.shownMessage) }
        self.webView = webView
        savedFrame = webView.frame
        savedAutoresizing = webView.translatesAutoresizingMaskIntoConstraints
        let size = NSSize(width: max(savedFrame.width, 320), height: max(savedFrame.height, 240))
        window = ControlStageWindow(
            contentRect: NSRect(origin: NSPoint(x: -20000, y: -20000), size: size),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.transient, .ignoresCycle]
        window.isExcludedFromWindowsMenu = true
        webView.translatesAutoresizingMaskIntoConstraints = true
        webView.frame = NSRect(origin: .zero, size: size)
        window.contentView?.addSubview(webView)
        // Regardless: Luna may not be active, and must not become so.
        window.orderFrontRegardless()
        window.makeFirstResponder(webView)
        Self.stagedWindows[window.windowNumber] = Weak(webView: webView)
        menuWatch = NotificationCenter.default.addObserver(
            forName: NSMenu.didBeginTrackingNotification, object: nil, queue: nil
        ) { _ in MainActor.assumeIsolated { Self.escapeMenu() } }
    }

    /// Gives the web view back, windowless and at its old frame, unless the
    /// user has since put it on screen — then it is theirs and left alone.
    func release() {
        guard !released else { return }
        released = true
        if let menuWatch { NotificationCenter.default.removeObserver(menuWatch) }
        if webView.window === window {
            webView.removeFromSuperview()
            webView.frame = savedFrame
            webView.translatesAutoresizingMaskIntoConstraints = savedAutoresizing
        }
        window.orderOut(nil)
        window.close()
    }

    // MARK: - Input

    /// Left or right. Not the middle button: `mouseEvent` makes every
    /// other-button event button 0, which the page reads as a left click, and
    /// a Quartz copy with the button set lands at a point it does not place
    /// consistently for a window off every screen. The middle button goes as
    /// page events.
    func click(at point: CGPoint, right: Bool = false, count: Int = 1, modifiers: ControlInput.Modifiers = []) throws {
        let (down, up): (NSEvent.EventType, NSEvent.EventType) = right
            ? (.rightMouseDown, .rightMouseUp) : (.leftMouseDown, .leftMouseUp)
        try move(to: point)
        for clicks in 1 ... max(count, 1) {
            try deliver(mouse(down, at: point, modifiers: modifiers, clicks: clicks))
            try deliver(mouse(up, at: point, modifiers: modifiers, clicks: clicks))
        }
    }

    /// Not a hover on its own: WebKit does not turn a moved event into
    /// `mouseover` for a page on the stage (measured: nothing fires until a
    /// button goes down), so `hover` goes as page events.
    private func move(to point: CGPoint) throws {
        try deliver(mouse(.mouseMoved, at: point))
    }

    /// Press, ten moves, let go — with a beat between moves, which pointer
    /// handlers that sample on a timer need to see motion at all.
    func drag(from start: CGPoint, to end: CGPoint) async throws {
        try move(to: start)
        try deliver(mouse(.leftMouseDown, at: start, clicks: 1))
        try await Task.sleep(for: .milliseconds(50))
        for step in 1 ... 10 {
            let t = Double(step) / 10
            let point = CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t)
            try deliver(mouse(.leftMouseDragged, at: point, clicks: 1))
            try await Task.sleep(for: .milliseconds(20))
        }
        try deliver(mouse(.leftMouseUp, at: end, clicks: 1))
    }

    func type(_ keys: [ControlInput.Key]) async throws {
        for key in keys {
            for type in [NSEvent.EventType.keyDown, .keyUp] {
                guard let event = NSEvent.keyEvent(
                    with: type, location: .zero, modifierFlags: Self.flags(key.modifiers),
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
                    characters: key.characters, charactersIgnoringModifiers: key.charactersIgnoringModifiers,
                    isARepeat: false, keyCode: key.keyCode
                ) else { continue }
                try deliver(event)
            }
            // WebKit sends a key on only once the page has answered the one
            // before; unpaced, a call returned with a third of a sentence typed.
            try await Task.sleep(for: .milliseconds(15))
        }
    }

    // MARK: - Delivery

    /// Straight to the web view's responder methods, never `window.sendEvent`
    /// or `CGEvent.post`: the first routes through the window's own handling,
    /// the second moves the user's real pointer.
    private func deliver(_ event: NSEvent) throws { // swiftlint:disable:this cyclomatic_complexity
        // Checked per event: the user may have selected the tab mid-call, and
        // then the web view is in their window.
        guard !released, webView.window === window else { throw ControlError(Self.shownMessage) }
        switch event.type {
        case .keyDown:
            if event.modifierFlags.contains(.command), webView.performKeyEquivalent(with: event) { return }
            webView.keyDown(with: event)
        case .keyUp: webView.keyUp(with: event)
        case .mouseMoved: webView.mouseMoved(with: event)
        case .leftMouseDown: webView.mouseDown(with: event)
        case .leftMouseDragged: webView.mouseDragged(with: event)
        case .leftMouseUp: webView.mouseUp(with: event)
        case .rightMouseDown: webView.rightMouseDown(with: event)
        case .rightMouseUp: webView.rightMouseUp(with: event)
        default: break
        }
    }

    /// `point` is in CSS pixels from the viewport's top left, the space
    /// `read_page`, `find` and screenshots use.
    private func mouse(
        _ type: NSEvent.EventType, at point: CGPoint, modifiers: ControlInput.Modifiers = [], clicks: Int = 0
    ) throws -> NSEvent {
        let scale = webView.pageZoom * webView.magnification
        let inset = webView.obscuredContentInsets
        let x = inset.left + point.x * scale, y = inset.top + point.y * scale
        let local = webView.isFlipped ? NSPoint(x: x, y: y) : NSPoint(x: x, y: webView.bounds.height - y)
        eventNumber += 1
        let pressed: Set<NSEvent.EventType> = [.leftMouseDown, .leftMouseDragged, .rightMouseDown]
        guard let event = NSEvent.mouseEvent(
            with: type, location: webView.convert(local, to: nil), modifierFlags: Self.flags(modifiers),
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
            eventNumber: eventNumber, clickCount: clicks, pressure: pressed.contains(type) ? 1 : 0
        ) else { throw ControlError("Luna could not make that mouse event.") }
        return event
    }

    private static func flags(_ modifiers: ControlInput.Modifiers) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers.contains(.shift) { flags.insert(.shift) }
        if modifiers.contains(.control) { flags.insert(.control) }
        if modifiers.contains(.option) { flags.insert(.option) }
        if modifiers.contains(.command) { flags.insert(.command) }
        return flags
    }

    // MARK: - What must not reach the user

    /// For `LunaApplication.sendEvent`. WebKit hands a key the page did not
    /// handle back to `NSApp.sendEvent`, so the menus can have it; for a
    /// stage that is the user's main menu answering an agent's keystroke —
    /// Cmd+W closing the tab in front of them. Every key event for a stage
    /// window is dropped there: delivery never goes through `sendEvent`, so
    /// anything arriving is such a resend. Select All is the one editing
    /// command done for it, on the stage's own web view; the clipboard ones
    /// are dropped, so an agent never reads or overwrites the user's.
    static func absorbs(_ event: NSEvent) -> Bool {
        guard [.keyDown, .keyUp, .flagsChanged].contains(event.type),
              let staged = stagedWindows[event.windowNumber] else { return false }
        if event.type == .keyDown, event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.charactersIgnoringModifiers == "a", let webView = staged.webView, webView.window is ControlStageWindow {
            webView.selectAll(nil)
        }
        return true
    }

    /// The backstop behind the library's stage mode, which prevents the
    /// page's context menu and select popup: a native menu runs a modal loop
    /// on the user's screen, and neither `willOpenMenu` nor `cancelTracking`
    /// ends one WebKit has started. An Escape posted to this app's own queue
    /// does. Armed only while a stage is up, so a menu the user opens in
    /// that moment closes too, which is the lesser harm.
    private static func escapeMenu() {
        guard let escape = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
            characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53
        ) else { return }
        NSApp.postEvent(escape, atStart: true)
    }
}
