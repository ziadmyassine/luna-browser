//
//  PageBarLights.swift
//  Luna
//
//  The one thing §3.2b's bar cannot work out from its own bounds: where the
//  traffic lights are, and when they have moved.
//
//  An extension rather than more of `PageChromeBar.swift`, which is at
//  SwiftLint's 400-line limit — the same reason `PageBarScroll` and
//  `PageBarSuggestions` are files of their own.
//

import AppKit

extension PageChromeBar {

    /// The traffic lights come and go without resizing this bar.
    ///
    /// `placeControls` lays the three circles out against the lights
    /// (`TrafficLightSpace`), and macOS takes them out of the window on the way
    /// into fullscreen and hands them back on the way out. Neither edge changes
    /// this view's bounds, so nothing marks it dirty and the bar keeps whichever
    /// placement it happened to have: the buttons a light's width off wherever
    /// the pane is the whole window, and the open pill off the centre line the
    /// collapsed one shares — which turns §3.2b's dissolve into a move, in
    /// fullscreen only.
    ///
    /// §3.1's control row has exactly this dependency and is fixed exactly this
    /// way, in `BrowserWindowController.relayoutChrome`. That pass walks the
    /// chrome host's subviews, and this bar is not one of them: it is an
    /// overlay on the content card (`ContentCardView.setOverlay`), so the pass
    /// never reached it and it has to hear the two notifications itself.
    ///
    /// `object: nil` because the bar is built long before it is in a window —
    /// there is nothing to scope the registration to, so `lightsMoved` scopes
    /// it instead. The observers are selector-based, like the rest of the
    /// chrome's: `NotificationCenter` holds them weakly and zeroes them on
    /// dealloc, so there is nothing to remove.
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
