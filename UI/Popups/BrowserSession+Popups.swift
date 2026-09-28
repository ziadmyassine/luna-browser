//
//  BrowserSession+Popups.swift
//  Luna
//
//  Where §17's pop-up blocker meets the chrome: the chip, and the three ways a
//  blocked pop-up is opened after all — the chip's two buttons and the
//  user's own shortcut. Which pop-ups are blocked is `PopupPolicy`'s, under
//  test in BrowserKit; this only shows the answer.
//
//  Active tab only, like the password chip: a pop-up blocked in a tab the user
//  is not looking at is in that tab's site menu when they get there.
//

import AppKit
import BrowserKit

extension BrowserSession {

    func tabController(_ controller: TabController, didBlockPopup url: URL) {
        // Notify off: the block and its entry in the site menu stand, and
        // nothing appears over the page.
        guard PopupChipSettings.notifies, controller.id == activeTabID,
              let window = hostWindow, let webView = controller.webView
        else { return }
        popupChip.onOpen = { [weak self] url in self?.newTab(url: url) }
        popupChip.onAlwaysAllow = { [weak self, weak controller] url in
            if let host = controller?.state.url?.host() {
                controller?.sitePermissions.setAllowed(true, .popups, forHost: host)
            }
            self?.newTab(url: url)
        }
        popupChip.present(url, in: window, over: webView, below: Self.siteMenuGlyph(in: window))
    }

    /// A blank pop-up whose destination was refused. Off the undo stack — the
    /// user did not close it — and back to the tab that opened it, so the chip
    /// the opener is about to show lands on the page it is about.
    func tabControllerWantsToClose(_ controller: TabController) {
        let parent = tab(controller.id)?.parentTabID
        undoManager.disableUndoRegistration()
        closeTab(controller.id)
        undoManager.enableUndoRegistration()
        if let parent, tab(parent) != nil { activateTab(parent) }
    }

    /// The active tab's most recent blocked pop-up, whether the chip is up or
    /// not.
    var latestBlockedPopup: URL? {
        activeTabID.flatMap { controller(for: $0) }?.popups.blocked.first?.url
    }

    func openLatestBlockedPopup() {
        guard let url = latestBlockedPopup else { return }
        popupChip.dismiss()
        newTab(url: url)
    }

    /// The glyph the site menu opens from, when one is showing: the sidebar's
    /// pill or the page bar's. The top bar's is on the selected tab, which is
    /// not a pill, so the chip takes the save chip's corner there.
    private static func siteMenuGlyph(in window: NSWindow) -> NSView? {
        guard let root = window.contentView else { return nil }
        var queue = [root]
        while !queue.isEmpty {
            let view = queue.removeFirst()
            if let pill = view as? URLPillView, !pill.isHiddenOrHasHiddenAncestor,
               !pill.siteMenuAnchor.isHidden, pill.siteMenuAnchor.alphaValue > 0 {
                return pill.siteMenuAnchor
            }
            queue += view.subviews
        }
        return nil
    }
}
