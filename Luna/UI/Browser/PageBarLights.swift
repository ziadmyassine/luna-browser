//
//  PageBarLights.swift
//  Luna
//
//  The one thing §3.2b's bar cannot work out from its own bounds: where the
//  traffic lights are, and when they have moved.
//
//  An extension rather than more of `PageChromeBar.swift` because it is the
//  bar's one dependency on the window rather than on its own bounds.
//

import AppKit

extension PageChromeBar {

    /// The traffic lights come and go without resizing this bar.
    ///
    /// `placeControls` lays the three circles out against the lights
    /// (`TrafficLightSpace`), and macOS takes them out of the window on the way
    /// into fullscreen and back on the way out without changing this view's
    /// bounds. Unheard, the bar keeps its old placement: the buttons a light's
    /// width off, and the open pill off the collapsed one's centre line, which
    /// turns §3.2b's dissolve into a move in fullscreen only.
    ///
    /// §3.1's control row is fixed the same way in
    /// `BrowserWindowController.relayoutChrome`, but that pass walks the chrome
    /// host's subviews and this bar is an overlay on the content card
    /// (`ContentCardView.setOverlay`), so it hears the notifications itself.
    ///
    /// `object: nil` because the bar is built long before it is in a window;
    /// `lightsMoved` does the scoping. Selector-based, so `NotificationCenter`
    /// holds the observer weakly and there is nothing to remove.
    func watchForTheLights() {
        for name: Notification.Name in [
            NSWindow.didEnterFullScreenNotification,
            NSWindow.didExitFullScreenNotification
        ] {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(lightsMoved),
                name: name,
                object: nil
            )
        }
    }

    /// Twice, for the reason `relayoutChrome` gives: AppKit restores the buttons
    /// after posting the exit notification, so the pass that has real frames to
    /// read is the one after this.
    @objc func lightsMoved(_ note: Notification) {
        guard let posted = note.object as? NSWindow, posted === window else { return }
        needsLayout = true
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.needsLayout = true }
        }
    }
}
