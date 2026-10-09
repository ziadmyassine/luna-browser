//
//  ControlService+Folders.swift
//  Luna
//
//  Each agent session's sidebar folder: which one it is, what it is called,
//  what it wears (the app's icon, an outline in the app's colour), and the
//  folder open when the session connects, so the tabs it is about to open
//  are in view.
//

import BrowserKit
import Foundation
import LunaControl

extension ControlService {

    /// Which app each Luna Control folder belongs to, kept across launches:
    /// a folder is named after its session, which says nothing about the app
    /// to a launch that has not heard from the session yet.
    static let folderAppsKey = "control.folderApps"

    /// A client connected or went.
    func clientsChanged() {
        // A call's own word on the session is newer than the handshake's.
        for client in clients where agents[client.session] == nil { agents[client.session] = client }
        let now = Set(clients.map(\.session))
        if let session {
            for client in clients where !connectedSessions.contains(client.session) {
                guard let folder = folder(of: client, in: session), folder.isCollapsed else { continue }
                session.setGroupCollapsed(false, forGroup: folder.id)
            }
        }
        connectedSessions = now
        refreshFaces()
    }

    /// The app name the user knows an agent by, for its capsule, pointer and
    /// requests.
    func displayName(of agent: String) -> String {
        if Self.astroTasks[agent] != nil { return String(localized: "Astro") }
        return agents[agent]?.displayName ?? ControlClient.fallbackName
    }

    func appID(of agent: String) -> String? {
        if Self.astroTasks[agent] != nil { return ControlFace.astro }
        if agents[agent]?.displayName == "Luna Control" { return ControlFace.lunaControl }
        return agents[agent].flatMap { ControlApp.app(forClient: $0.rawName)?.id }
    }

    /// What the session's folder should be called: its task (`name_task`),
    /// else the session's own name, else the app's, numbered when another
    /// session already has a folder of that name.
    func folderName(for client: ControlClient, in session: BrowserSession) -> String {
        let base = taskNames[client.session] ?? Self.astroTasks[client.session] ?? client.sessionName ?? client.displayName
        let taken = Set(folders.filter { $0.key != client.session }.compactMap { session.group($0.value)?.name })
        guard taken.contains(base) else { return base }
        return (2...).lazy.map { "\(base) \($0)" }.first { !taken.contains($0) } ?? base
    }

    /// The session's folder in the Space the user is in, made if there is
    /// none there. A folder in another Space is left where it is: the tabs
    /// an agent opens belong where the user can see them.
    func folderInActiveSpace(for client: ControlClient, in session: BrowserSession) -> TabGroup {
        folder(inSpace: session.activeSpaceID, for: client, in: session)
    }

    /// The session's folder in `space`, made if there is none there.
    func folder(inSpace space: UUID, for client: ControlClient, in session: BrowserSession) -> TabGroup {
        let owned = Set(folders.filter { $0.key != client.session }.map(\.value))
        let group = session.controlFolder(
            named: folderName(for: client, in: session), previously: folders[client.session], excluding: owned, in: space
        )
        take(group, for: client)
        return group
    }

    /// Takes back the session's folder from an earlier launch on its first
    /// call of this one, and follows the session's name. `folders` starts
    /// empty, so without this its work on the tabs already in the folder
    /// leaves the folder's spark dark, and those tabs do not count as its own.
    func adoptFolder(of client: ControlClient, in session: BrowserSession) {
        if folders[client.session] == nil, let group = folder(of: client, in: session) {
            take(group, for: client)
        }
        guard let id = folders[client.session], let group = session.group(id),
              group.name == folderNames[client.session] else { return }
        let name = folderName(for: client, in: session)
        guard name != group.name else { return }
        session.renameControlFolder(id, to: name)
        folderNames[client.session] = name
    }

    /// `name_task`: the folder takes the task's name now if it has one, and
    /// when it is made if not. A folder the user renamed keeps their name.
    func nameTask(_ title: String, icon: String? = nil, for client: ControlClient, in session: BrowserSession) -> ControlResult {
        taskNames[client.session] = title
        Self.taskIcons[client.session] = Self.folderIcon(icon, title: title, astro: Self.astroTasks[client.session] != nil)
            ?? Self.taskIcons[client.session]
        if let id = folders[client.session] { dress(id, for: client.session, in: session) }
        if let id = folders[client.session], let group = session.group(id), group.name == folderNames[client.session] {
            let name = folderName(for: client, in: session)
            if name != group.name {
                session.renameControlFolder(id, to: name)
                folderNames[client.session] = name
            }
        }
        NotificationCenter.default.post(
            name: Self.taskNamed, object: self, userInfo: ["session": client.session, "title": title]
        )
        return .text("Your folder is called “\(title)”.")
    }

    /// Puts a tab the agent is about to take over into its folder, so every
    /// tab an agent works in is in a folder the user can see is the agent's.
    /// Only a loose tab of today's: a saved tab, one in the user's own folder
    /// or one in another agent's stays where the user or that agent put it.
    ///
    /// In the tab's own Space, which need not be the one in front, or a tab in
    /// another Space stays loose with no sign an agent has used it.
    func enfold(_ id: UUID, for client: ControlClient, in session: BrowserSession) {
        guard let tab = session.tab(id), tab.kind == .today, tab.groupID == nil else { return }
        let current = folders[client.session].flatMap(session.group)
        let folder = current?.spaceID == tab.spaceID ? current : nil
        session.moveControlledTab(id, into: (folder ?? self.folder(inSpace: tab.spaceID, for: client, in: session)).id)
    }

    /// Every Luna Control folder's app.
    ///
    /// A folder is the session's once it has opened a tab in it this launch
    /// (`folders`). Before that, one Luna made in an earlier launch is known
    /// by its icon and the app it was last seen with, so it wears its app's
    /// face from the start.
    func refreshFaces() {
        guard let session else { return }
        let owners = Dictionary(folders.map { ($0.value, $0.key) }, uniquingKeysWith: { first, _ in first })
        let remembered = defaults.dictionary(forKey: Self.folderAppsKey) as? [String: String] ?? [:]
        var faces: [UUID: ControlFace] = [:]
        for group in session.list.groupsBySpace.values.joined()
        where owners[group.id] != nil || group.symbolName == BrowserSession.controlFolderSymbol
            || remembered[group.id.uuidString] != nil {
            let app = owners[group.id].flatMap(appID(of:))
                ?? remembered[group.id.uuidString]
                ?? ControlApp.all.first { $0.folderName == group.name }?.id
            // A folder of the user's that happens to wear sparkles is not one.
            guard app != nil || owners[group.id] != nil else { continue }
            faces[group.id] = ControlFace(appID: app)
        }
        session.setControlFaces(faces)
    }

    /// Forgets the faces of folders that no longer exist. Only ever removes,
    /// so it settles in one pass: recomputing every face on each change
    /// could answer another change with a different set, and two services
    /// on one session did that to each other until the stack ran out.
    func dropClosedFaces() {
        guard let session else { return }
        let kept = session.controlFaces.filter { session.list.group($0.key) != nil }
        if kept.count != session.controlFaces.count { session.setControlFaces(kept) }
    }

    private func take(_ group: TabGroup, for client: ControlClient) {
        let isNew = folders[client.session] != group.id
        folders[client.session] = group.id
        folderNames[client.session] = group.name
        guard isNew else { return }
        if let session { dress(group.id, for: client.session, in: session) }
        if let app = appID(of: client.session) {
            var remembered = defaults.dictionary(forKey: Self.folderAppsKey) as? [String: String] ?? [:]
            remembered[group.id.uuidString] = app
            defaults.set(remembered, forKey: Self.folderAppsKey)
        }
        refreshFaces()
    }

    /// The folder `openTab` would use for the session, if there is one yet:
    /// its own, else one from an earlier launch by the name it would get
    /// that no other session has taken.
    private func folder(of client: ControlClient, in session: BrowserSession) -> TabGroup? {
        if let id = folders[client.session], let group = session.group(id) { return group }
        let owned = Set(folders.values)
        let name = client.sessionName ?? client.displayName
        return session.groups.first {
            $0.name == name && $0.symbolName == BrowserSession.controlFolderSymbol && !owned.contains($0.id)
        }
    }
}
