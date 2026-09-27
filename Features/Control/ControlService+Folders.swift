//
//  ControlService+Folders.swift
//  Luna
//
//  What a client's sidebar folder shows of it: the app's icon, an outline in
//  the app's colour, and the folder open when the app connects, so the tabs
//  it is about to open are in view.
//

import BrowserKit
import Foundation
import LunaControl

extension ControlService {

    /// A client connected or went.
    func clientsChanged() {
        let now = Set(clientNames.map(ControlClient.displayName(for:)))
        if let session {
            for name in now.subtracting(connectedNames) {
                guard let folder = folder(named: name, in: session), folder.isCollapsed else { continue }
                session.setGroupCollapsed(false, forGroup: folder.id)
            }
        }
        connectedNames = now
        refreshFaces()
    }

    /// Every Luna Control folder's app.
    ///
    /// A folder is the client's once it has opened a tab in it this launch
    /// (`folders`). Before that, one Luna made in an earlier launch is known
    /// by its name and its icon, so it wears its app's face from the start.
    func refreshFaces() {
        guard let session else { return }
        let connected = Dictionary(
            clientNames.map { (ControlClient.displayName(for: $0), $0) }, uniquingKeysWith: { first, _ in first }
        )
        let adopted = Set(folders.values)
        var faces: [UUID: ControlFace] = [:]
        for group in session.list.groupsBySpace.values.joined()
        where adopted.contains(group.id) || group.symbolName == BrowserSession.controlFolderSymbol {
            let app = connected[group.name].flatMap(ControlApp.app(forClient:))
                ?? ControlApp.all.first { $0.folderName == group.name }
            // A folder of the user's that happens to wear sparkles is not one.
            guard app != nil || adopted.contains(group.id) else { continue }
            faces[group.id] = ControlFace(appID: app?.id)
        }
        session.setControlFaces(faces)
    }

    /// The folder `openTab` would use for `name`, if there is one yet.
    private func folder(named name: String, in session: BrowserSession) -> TabGroup? {
        if let id = folders[name], let group = session.group(id) { return group }
        return session.groups.first { $0.name == name && $0.symbolName == BrowserSession.controlFolderSymbol }
    }
}
