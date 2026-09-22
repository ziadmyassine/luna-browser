//
//  AppDelegate+PrivateWindow.swift
//  Luna
//
//  §5.6's window: `⌘⇧N`.
//
//  It is private by being separate rather than by being filtered. A normal
//  window shares the app's one session, because the tab list is a database and
//  two copies of it would race onto disk; this one gets a session of its own
//  over a database of its own, in a throwaway directory that is deleted the
//  moment the window closes. Nothing here has to remember to skip a write —
//  history, tabs, Spaces and §9.3's use counts all land in a file that does not
//  outlive the window.
//
//  Cookies and storage are the other half and are WebKit's: the session is
//  marked private and hands every Space a non-persistent data store, so the
//  jar lives in memory and dies with the web views (`ProfileStore` is not
//  consulted at all).
//
//  What that leaves is a window that cannot be restored, cannot be undone into
//  the real session, and shows up in no search of the user's own history —
//  because there is nothing to restore it from and nothing to search.
//

import AppKit
import BrowserKit

extension AppDelegate {

    /// Builds the session behind a §5.6 window and puts it in `controller`.
    ///
    /// Async because a database is a file. The window is already on screen by
    /// then — empty for the instant it takes, which is the same instant a cold
    /// launch spends and for the same reason.
    func openPrivateWindow(in controller: BrowserWindowController) async {
        do {
            let home = Self.privateDatabaseRoot().appending(path: UUID().uuidString)
            let store = try BrowserStore(path: home.appending(path: "luna.sqlite"))
            let session = try await BrowserSession.restored(store: store, isPrivate: true)
            // The seeded Space is called Personal and wears the default
            // gradient, which is the opposite of what this window is. Named and
            // coloured before the chrome reads it, so the column never draws
            // the wrong one and corrects itself.
            if let space = session.spaces.first {
                try? await session.renameSpace(space.id, to: String(localized: "Private"))
                try? await session.setGradient(Self.privateGradient, forSpace: space.id)
            }
            let window = BrowserWindow(session: session, controller: controller, privateHome: home)
            adopt(window)
            window.applyChromeLayout(animated: false)
            window.render()
        } catch {
            controller.close()
            NSApp.presentError(error)
        }
    }

    /// Ends a private session and takes its database with it.
    ///
    /// The web views go first and synchronously: a non-persistent store is held
    /// alive by the views built against it, and deleting the directory under a
    /// live one would leave the jar in memory with nowhere to land.
    func endPrivateSession(_ session: BrowserSession, home: URL) {
        session.tearDown()
        // Detached rather than awaited: the window has gone and nothing is
        // waiting on the bytes. A directory that survives a crash here is swept
        // by the next launch — see `sweepPrivateDatabases`.
        Task.detached { try? FileManager.default.removeItem(at: home) }
    }

    /// Clears out any private database a crash or a hard quit left behind.
    /// Called at launch, where the answer is always "none of these are in use".
    static func sweepPrivateDatabases() {
        let root = privateDatabaseRoot()
        guard let left = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        else { return }
        for directory in left { try? FileManager.default.removeItem(at: directory) }
    }

    /// Mulberry, which is not in the first few a user's own Spaces are handed
    /// and reads as deliberate rather than decorative. §5.6 asks for a tint the
    /// window can be told apart by, and Luna already has one surface for that:
    /// §8.2a's wash, down the column and across the head of the page.
    private static var privateGradient: GradientPair { Tokens.Gradient.spacePalette[3] }

    static func privateDatabaseRoot() -> URL {
        URL.temporaryDirectory.appending(path: "dk.novapps.luna.private")
    }
}
