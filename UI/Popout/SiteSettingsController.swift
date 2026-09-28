//
//  SiteSettingsController.swift
//  Luna
//
//  Puts §3.2's site settings up on the glyph that was pressed, whichever
//  chrome it is in, and runs a chosen action once the pop-out is on its way
//  out.
//

import AppKit

@MainActor
final class SiteSettingsController: PopoutController {

    /// Set by `toggle(in:from:edge:content:)` before the panel is built.
    private var edge: PopoutEdge = .below
    private var content = SiteSettingsContent(heading: "")
    /// Where the keyboard was before the pop-out took it for its arrow keys.
    private weak var focusBefore: NSResponder?
    private weak var focused: PopoutPanelView?

    func toggle(in window: NSWindow, from anchor: NSView, edge: PopoutEdge, content: SiteSettingsContent) {
        self.edge = edge
        self.content = content
        toggle(in: window, from: anchor)
    }

    override func makePanel(in root: NSView) -> PopoutPanelView {
        let panel = SiteSettingsPanel(frame: root.bounds, edge: edge, content: content)
        panel.onAction = { [weak self] action in
            self?.dismiss()
            action.run()
        }
        return panel
    }

    override func panelDidAppear(_ panel: PopoutPanelView) {
        focusBefore = panel.window?.firstResponder
        focused = panel
        panel.window?.makeFirstResponder(panel)
    }

    /// Given back, because a panel on its way out keeps the keyboard
    /// otherwise: Escape then never reached the page to end the picker, and
    /// Space no longer scrolled it.
    override func panelDidDisappear() {
        content = SiteSettingsContent(heading: "")
        guard let panel = focused, let window = panel.window, window.firstResponder === panel else { return }
        window.makeFirstResponder(focusBefore)
    }
}
