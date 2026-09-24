//
//  BrowserWindowController+Delegate.swift
//  Luna
//
//  `NSWindowDelegate`: what the window does when macOS changes it underneath —
//  fullscreen, and the resize that follows.
//
//  Split out of `BrowserWindowController` when that file crossed SwiftLint's
//  400-line limit. A protocol conformance in its own file is the house pattern
//  anyway (`TabController+Delegates`, `TabListController+Table`). Nothing
//  changed on the way across.
//

import AppKit

extension BrowserWindowController {

    // MARK: - NSWindowDelegate

    func windowDidBecomeKey(_ notification: Notification) {
        onBecameKey?()
    }

    /// macOS fullscreen keeps the chrome — a browser without its tab list in
    /// fullscreen is unusable. Only the window's own corners change: the system
    /// frame is square there, and a rounded mask would show as black notches.
    func windowDidEnterFullScreen(_ notification: Notification) {
        (window?.contentView as? WindowRootView)?.isWindowFullScreen = true
        updatePeekEdgeWidth()
        relayoutChrome()
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        (window?.contentView as? WindowRootView)?.isWindowFullScreen = false
        updatePeekEdgeWidth()
        relayoutChrome()
    }

    /// The traffic lights change size without changing anyone's bounds.
    ///
    /// §3.1's control row lays its three circles out against the lights —
    /// measured, because `TrafficLightLayoutManager` owns their frames — and
    /// macOS takes the lights away in fullscreen and puts them back on the way
    /// out. Neither edge resizes the row, so nothing marks it dirty, and the
    /// row kept whichever placement it happened to have when it last laid out:
    /// the toggle sitting on top of the green light after a return to windowed.
    /// The same call fixes the peek, for the same reason.
    private func relayoutChrome() {
        guard let chrome else { return }
        for layout in chrome.subviews { layout.needsLayout = true }
        // AppKit restores the buttons after posting the notification on the
        // way out of fullscreen, so the pass that matters is the next one.
        DispatchQueue.main.async { [weak chrome] in
            guard let chrome else { return }
            for layout in chrome.subviews { layout.needsLayout = true }
        }
    }
}
