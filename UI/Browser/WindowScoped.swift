//
//  WindowScoped.swift
//  Luna
//
//  §22.6: chrome belongs to one window, and says so.
//
//  A sidebar, a top bar, a page bar and a Command Bar are built per window.
//  The session they read is shared, so the questions that have one answer for
//  the whole app — what Spaces there are, what is in the tab list, what a tab's
//  title is — are asked of it directly, as they always were.
//
//  The questions that do not are here. "Which tab is selected" and "which Space
//  am I showing" are a window's own, and a view asking the session flatly gets
//  the front window's answer: correct exactly while its own window is in front,
//  and wrong the rest of the time — a background window's column following the
//  selection in the window the user moved to.
//
//  So the four below shadow the session's spelling with the window's. A view
//  adopts this and its existing `session.activeTabID` becomes `activeTabID`,
//  which means the same thing it always meant on screen and now means it in
//  every window at once.
//
//  `session` is internal on the adopters rather than private for the reason it
//  is internal on `BrowserSession`'s own state: a protocol requirement cannot
//  be fileprivate, and nothing outside the view reads it.
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
