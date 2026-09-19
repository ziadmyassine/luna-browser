//
//  TrafficLightSpace.swift
//  Luna
//
//  Where the three window buttons are, in some other view's coordinates — the
//  one question two pieces of chrome both have to ask, and exactly one place
//  that answers it.
//
//  `TrafficLightLayoutManager` owns their *frames*; this owns the read. They
//  are separate because the read is the half that races: AppKit resets the
//  buttons' origins on every window resize and the manager puts them back a
//  beat later, so a view that lays out in between and believes what it sees
//  draws itself against a placement that is about to be replaced.
//
//  **Sizes are measured; positions are derived.** What AppKit owns and never
//  changes is the buttons' size and the spacing between them; what Luna owns is
//  `trafficLightInset`, the single number the manager places them with. Measure
//  the first, derive the second, and a caller lands on the lights whatever
//  order the two passes run in.
//

import AppKit

enum TrafficLightSpace {

    /// The rectangle the three lights occupy, in `view`'s coordinates — or nil
    /// when there are none to clear: while the chrome that hosts them is off
    /// screen, and while `⌘S` has given the page the whole window.
    ///
    /// **Fullscreen is not one of those.** It used to be — macOS takes the
    /// titlebar out of the window there and hangs it off the top of the screen
    /// — but `TrafficLightLayoutManager` now catches the lights on the way out
    /// and keeps them in the window's corner, so a fullscreen sidebar has the
    /// same three circles to clear as a windowed one.
    @MainActor
    static func rect(in view: NSView) -> NSRect? {
        guard let window = view.window,
              let close = window.standardWindowButton(.closeButton),
              let zoom = window.standardWindowButton(.zoomButton),
              !zoom.isHiddenOrHasHiddenAncestor,
              let root = window.contentView
        else { return nil }
        let inset = Tokens.Metric.trafficLightInset
        // Close's leading edge to zoom's trailing edge: AppKit's own spacing,
        // whatever it is, and the same distance wherever the caller sits.
        let span = zoom.frame.maxX - close.frame.minX
        let corner = view.convert(NSPoint(x: root.bounds.minX, y: root.bounds.maxY), from: root)
        return NSRect(
            x: corner.x + inset,
            y: corner.y - inset - zoom.frame.height,
            width: max(span, zoom.frame.width),
            height: zoom.frame.height
        )
    }
}
