//
//  BrowserSession+Popups.swift
//  Luna
//
//  Where §17's pop-up blocker meets the chrome: the notice, and the three ways
//  a blocked pop-up is opened after all — the notice's two words and the
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
        guard PopupNoticeSettings.notifies, controller.id == activeTabID else { return }
        let toast = popupNotice.next(
            url,
            shortcut: KeyBindings.primary(for: .openBlockedPopup)?.display,
            open: { [weak self] in self?.newTab(url: url) },
            allow: { [weak self, weak controller] in
                if let host = controller?.state.url?.host() {
                    controller?.sitePermissions.setAllowed(true, .popups, forHost: host)
                }
                self?.newTab(url: url)
            }
        )
        toast.show(in: hostWindow)
    }

    /// A blank pop-up whose destination was refused. Off the undo stack — the
    /// user did not close it — and back to the tab that opened it, so the
    /// notice the opener is about to show lands on the page it is about.
    func tabControllerWantsToClose(_ controller: TabController) {
        let parent = tab(controller.id)?.parentTabID
        undoManager.disableUndoRegistration()
        closeTab(controller.id)
        undoManager.enableUndoRegistration()
        if let parent, tab(parent) != nil { activateTab(parent) }
    }

    /// The active tab's most recent blocked pop-up, whether the notice is
    /// down or not.
    var latestBlockedPopup: URL? {
        activeTabID.flatMap { controller(for: $0) }?.popups.blocked.first?.url
    }

    func openLatestBlockedPopup() {
        guard let url = latestBlockedPopup else { return }
        popupNotice.putAway(in: hostWindow)
        newTab(url: url)
    }
}
