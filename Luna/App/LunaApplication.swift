//
//  LunaApplication.swift
//  Luna
//
//  Luna's `NSApplication`, for the two things only the application object
//  sees: key events WebKit hands back from a Luna Control stage, which the
//  main menu must never act on (`ControlStage.absorbs`), and every action
//  sent through it, whose command titles a bug report lists
//  (`RecentCommands`).
//

import AppKit

final class LunaApplication: NSApplication {
    override func sendEvent(_ event: NSEvent) {
        if ControlStage.absorbs(event) { return }
        super.sendEvent(event)
    }

    /// Menu clicks, key equivalents, Command Bar rows and nil-targeted
    /// buttons all arrive here. Sidebar row clicks, swatches and swipes do not.
    override func sendAction(_ action: Selector, to target: Any?, from sender: Any?) -> Bool {
        let sent = super.sendAction(action, to: target, from: sender)
        RecentCommands.note(action)
        return sent
    }
}

/// The titles of the last ten commands, for a bug report's "Before this:"
/// line. Titles only, never an address, a page title or typed text, and in
/// memory only.
@MainActor
enum RecentCommands {
    private(set) static var titles: [String] = []

    /// The numbered families are not in `BrowserCommand.all`.
    private static let extras = [
        #selector(AppDelegate.switchToSpace(_:)): "Switch Space",
        #selector(AppDelegate.goToSidebarItem(_:)): "Go to Tab"
    ]

    static func note(_ action: Selector) {
        guard let title = BrowserCommand.all.first(where: { $0.action == action })?.title ?? extras[action] else { return }
        titles = (titles + [title]).suffix(10)
    }
}
