//
//  ChipPanel.swift
//  Luna
//
//  The panel under the chip that floats over the page: §14.4's save chip.
//  §17's pop-up chip stood on it too, until it became a page toast.
//
//  A panel resolves its appearance from the app, not from the window it is a
//  child of. The browser window, and a page bar that dresses itself for the
//  page, can be light while the app is dark — and then the chip's glass and
//  ink resolved dark over a light page: white words on a pale chip. So the
//  panel wears the appearance of the view it stands on, and keeps following it.
//
//  No window shadow: on a borderless panel it drew a hard dark ring round the
//  capsule. The material is the chip's edge, as it is the URL pill's.
//

import AppKit

@MainActor
enum ChipPanel {

    static func make() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.transient, .ignoresCycle]
        panel.animationBehavior = .utilityWindow
        return panel
    }

    /// Gives `panel` the appearance `source` has now and every time it changes.
    /// Hold the observation for as long as the panel is up.
    static func follow(_ source: NSView, with panel: NSPanel) -> NSKeyValueObservation {
        panel.appearance = source.effectiveAppearance
        return source.observe(\.effectiveAppearance, options: [.new]) { [weak panel] view, _ in
            MainActor.assumeIsolated { panel?.appearance = view.effectiveAppearance }
        }
    }
}
