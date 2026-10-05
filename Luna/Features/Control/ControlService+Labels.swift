//
//  ControlService+Labels.swift
//  Luna
//
//  `label_tab`, and Astro's own tasks. An agent names its tabs for what they
//  are for in the task ("Flights", "Hotels") and gives each an icon on a
//  coloured tile, so a folder of an agent's tabs reads like the plan it is
//  carrying out rather than a row of page titles.
//
//  Astro's tasks are Claude Code or Codex sessions like any other, but Luna
//  started them: their folders wear no app's face, only Astro at the row's
//  end while it works, and they are named from the task before the agent has
//  said a word.
//

import AppKit
import LunaControl

extension ControlService {

    /// The sessions Astro started, by Luna Control's session id, with the
    /// name their folder takes until the agent names the task itself.
    static var astroTasks: [String: String] = [:]

    /// The icon each session chose for its folder (`name_task`'s `icon`).
    static var taskIcons: [String: String] = [:]

    /// An icon a folder can wear: one emoji, or a symbol macOS has. Without
    /// one, Astro's folder takes the emoji its name suggests, as a folder the
    /// user names does (`FolderEmoji`).
    static func folderIcon(_ icon: String?, title: String, astro: Bool) -> String? {
        if let icon, icon.count == 1, FolderEmoji.suggestion(for: icon) == icon { return icon }
        if let icon, NSImage(systemSymbolName: icon, accessibilityDescription: nil) != nil { return icon }
        return astro ? FolderEmoji.suggestion(for: title) : nil
    }

    /// Puts the session's chosen icon on its folder, without an undo step:
    /// the agent chose it, not the user.
    func dress(_ folder: UUID, for agent: String, in session: BrowserSession) {
        guard let icon = Self.taskIcons[agent] else { return }
        session.undoManager.disableUndoRegistration()
        session.setIcon(icon, forGroup: folder)
        session.undoManager.enableUndoRegistration()
    }

    /// Astro's tasks that are working right now: their folders and tabs
    /// wear Astro for the whole turn, not only while a call is in flight.
    func setAstroWorking(_ sessions: Set<String>) {
        guard let session else { return }
        session.setAstroWorking(Set(sessions.compactMap { folders[$0] }))
    }

    /// `label_tab`: only on a tab in the agent's own folder, and a symbol
    /// macOS does not have is left off rather than drawn as nothing.
    func label(_ id: UUID?, _ command: ControlCommand, for client: ControlClient, in session: BrowserSession) -> ControlResult {
        guard case let .labelTab(title, symbol, colour) = command else { return .error("Luna cannot do that here.") }
        guard let id, let tab = session.tab(id), let folder = folders[client.session], tab.groupID == folder else {
            return .error("Only tabs in your own folder can be labelled. Open one with tab_open first.")
        }
        let known = symbol.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) == nil ? nil : $0 }
        session.labelControlledTab(id, title: title, symbol: known, colour: known == nil ? nil : colour)
        var said = "The tab is labelled" + (title.map { " “\($0)”" } ?? "") + "."
        if symbol != nil, known == nil { said += " There is no SF Symbol called \(symbol ?? ""), so it keeps its icon." }
        return .text(said)
    }
}

extension ControlFace {

    /// The `appID` of a folder Astro is working in.
    static let astro = "astro"

    var isAstro: Bool { appID == Self.astro }
}
