//
//  ControlService+Labels.swift
//  Luna
//
//  `label_tab`, and Astro's own tasks. An agent names its tabs for what they
//  are for in the task ("Flights", "Hotels"), so a folder of an agent's tabs
//  reads like the plan it is carrying out rather than a row of page titles.
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

    /// Astro's tasks working right now, and the tab each last acted on.
    static var astroWorking: Set<String> = []
    static var astroLastTab: [String: UUID] = [:]

    /// Astro's tasks that are working right now: their folders wear Astro
    /// for the whole turn, not only while a call is in flight, and so does
    /// the tab each last acted on — Astro moves from tab to tab with it.
    func setAstroWorking(_ sessions: Set<String>) {
        Self.astroWorking = sessions
        guard let session else { return }
        session.setAstroWorking(
            Set(sessions.compactMap { folders[$0] }), tabs: Set(sessions.compactMap { Self.astroLastTab[$0] })
        )
    }

    /// An Astro call landed on `tab`: that is the tab it is on now.
    func astroActed(on tab: UUID?, for agent: String) {
        guard let tab, Self.astroTasks[agent] != nil, Self.astroLastTab[agent] != tab else { return }
        Self.astroLastTab[agent] = tab
        setAstroWorking(Self.astroWorking)
    }

    /// The calls about how the agent's work is shown: a tab's name, a document.
    func present(_ command: ControlCommand, tab id: UUID?, for client: ControlClient, in session: BrowserSession) async throws
        -> ControlResult {
        if case let .showDocument(title, markdown) = command {
            return try await showDocument(title: title, markdown: markdown, for: client, in: session)
        }
        return label(id, command, for: client, in: session)
    }

    /// `label_tab`: only on a tab in the agent's own folder.
    func label(_ id: UUID?, _ command: ControlCommand, for client: ControlClient, in session: BrowserSession) -> ControlResult {
        guard case let .labelTab(title) = command else { return .error("Luna cannot do that here.") }
        guard let id, let tab = session.tab(id), let folder = folders[client.session], tab.groupID == folder else {
            return .error("Only tabs in your own folder can be labelled. Open one with tab_open first.")
        }
        session.labelControlledTab(id, title: title)
        return .text("The tab is called “\(title)”.")
    }

    /// Where the agents' documents are kept: Luna's own folder, which needs
    /// no permission to write, one file per document.
    static var documentsFolder: URL {
        URL.applicationSupportDirectory
            .appending(path: Bundle.main.bundleIdentifier ?? "dev.novapps.luna")
            .appending(path: "Agent Documents", directoryHint: .isDirectory)
    }

    /// `show_document`: saved under the title, made unique, and opened like
    /// any tab the agent opens — Luna's reader takes a `.md` file over.
    func showDocument(title: String, markdown: String, for client: ControlClient, in session: BrowserSession) async throws
        -> ControlResult {
        let folder = Self.documentsFolder
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = title.components(separatedBy: CharacterSet(charactersIn: "/:\\\n")).joined(separator: " ")
        var file = folder.appending(path: name + ".md")
        for number in 2 ... 99 where FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) {
            file = folder.appending(path: "\(name) \(number).md")
        }
        try Data(markdown.utf8).write(to: file, options: .atomic)
        return try await openTab(file, in: session, for: client)
    }

    /// Agents once gave their tabs icons as well; tabs keep their sites'
    /// icons now, so the ones an agent set are taken off, once.
    static let oldTabTilesKey = "control.tabTiles"

    static func dropAgentTabIcons(in session: BrowserSession) {
        guard let saved = UserDefaults.standard.dictionary(forKey: oldTabTilesKey) else { return }
        for id in saved.keys.compactMap(UUID.init(uuidString:)) { session.clearControlledTabIcon(id) }
        UserDefaults.standard.removeObject(forKey: oldTabTilesKey)
    }
}

extension ControlFace {

    /// The `appID` of a folder Astro is working in.
    static let astro = "astro"
    /// The `appID` of a client that names itself after Luna rather than after
    /// itself, shown as Luna Control (`ControlClient.displayName`): the moon.
    static let lunaControl = "luna-control"

    var isAstro: Bool { appID == Self.astro }
}
