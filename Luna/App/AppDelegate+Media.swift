//
//  AppDelegate+Media.swift
//  Luna
//
//  §18.4a's app-wide half: Mute All Tabs across every window, and Picture
//  in Picture's way back to the tab its video came from. Both ask about
//  windows rather than a session — a private window has a session of its
//  own, and a tab can be on screen in a window that is not in front.
//

import AppKit
import BrowserKit

extension AppDelegate {

    /// Each session once: ordinary windows share one.
    private var sessions: [BrowserSession] {
        windows.reduce(into: []) { found, window in
            if !found.contains(where: { $0 === window.session }) { found.append(window.session) }
        }
    }

    @objc func muteAllTabs(_ sender: Any?) {
        sessions.forEach { $0.muteAllTabs() }
        PageToast.allTabs(muted: true).show(in: session?.hostWindow)
    }

    @objc func unmuteAllTabs(_ sender: Any?) {
        sessions.forEach { $0.unmuteAllTabs() }
        PageToast.allTabs(muted: false).show(in: session?.hostWindow)
    }

    /// Mute All dims once every awake tab is muted, Unmute All once none is.
    func validateMediaCommand(_ item: NSMenuItem) -> Bool? {
        switch item.action {
        case #selector(muteAllTabs(_:)): sessions.contains { $0.canMuteAllTabs }
        case #selector(unmuteAllTabs(_:)): sessions.contains { !$0.mutedTabIDs.isEmpty }
        default: nil
        }
    }

    /// The Picture in Picture window's "back to tab": that tab, in a window
    /// already showing it if there is one, else in the front window of its
    /// session, which moves to the tab's Space first. Then the window comes
    /// forward, over whatever app the user was in.
    func returnToTab(_ id: UUID, in session: BrowserSession) {
        let own = windows.filter { $0.session === session }
        guard let window = own.first(where: { session.activeTabID(inWindow: $0.id) == id })
            ?? own.first(where: { $0 === front }) ?? own.first,
            let tab = session.tab(id)
        else { return }
        if !session.tabs(inWindow: window.id).contains(where: { $0.id == id }) {
            session.switchSpace(tab.spaceID, inWindow: window.id)
        }
        session.activateTab(id, inWindow: window.id)
        window.controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}
