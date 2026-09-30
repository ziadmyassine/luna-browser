//
//  WindowScoped.swift
//  Luna
//
//  §22.6: chrome belongs to one window, and says so.
//
//  A sidebar, a top bar, a page bar and a Command Bar are built per window
//  over a shared session. What has one answer for the whole app — the Spaces,
//  the tab list, a tab's title — is asked of the session directly. "Which tab
//  is selected" and "which Space am I showing" are a window's own: asked of
//  the session flatly they get the front window's answer, and a background
//  window's column follows the selection in the window the user moved to.
//
//  So the members below shadow the session's spelling with the window's: an
//  adopter's `session.activeTabID` becomes `activeTabID`. `session` is
//  internal on the adopters because a protocol requirement cannot be
//  fileprivate.
//

import BrowserKit
import Foundation

@MainActor
protocol WindowScoped: AnyObject {
    var session: BrowserSession { get }
    /// The window this view is in. Handed over at init and never changes — a
    /// view does not move between windows, it is rebuilt in the new one.
    var windowID: UUID { get }
}

extension WindowScoped {

    /// The tab this window has on screen, or nil when it has none (§19.4).
    var activeTabID: UUID? { session.activeTabID(inWindow: windowID) }

    /// The Space this window is showing (§5.3).
    var activeSpaceID: UUID { session.activeSpaceID(inWindow: windowID) }

    /// The tabs in that Space, in the order §3.4 draws them.
    var windowTabs: [Tab] { session.tabs(inWindow: windowID) }

    /// §3.3's tiles in that Space.
    var windowEssentials: [Tab] { session.favorites(inWindow: windowID) }

    /// One of §3.4's tiers in that Space, as slots.
    func windowSlots(inTier kind: TabKind) -> [SidebarSlot] {
        session.slots(inTier: kind, inWindow: windowID)
    }

    /// §9.1's bar, as this window put it up. Nil until one is wired, which is
    /// an honest degradation rather than a dead key — see `AppDelegate.newTab`.
    var presentCommandBar: BrowserSession.CommandBarPresenter? { session.commandBar(inWindow: windowID) }

    /// `⌘L`, as this window's address bar answers it.
    var focusURLField: (() -> Void)? { session.urlField(inWindow: windowID) }

    func activateTab(_ id: UUID) { session.activateTab(id, inWindow: windowID) }

    func switchSpace(_ id: UUID) { session.switchSpace(id, inWindow: windowID) }
}
