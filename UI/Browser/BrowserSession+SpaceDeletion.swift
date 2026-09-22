//
//  BrowserSession+SpaceDeletion.swift
//  Luna
//
//  Deleting a Space, and undoing it (spec §6.3, §13.7).
//
//  Split from `BrowserSession+Spaces.swift` because deletion is the half with a
//  policy, a snapshot and an undo, and the other half is field writes.
//
//  The rule the file is built around: a Space deletion never destroys a tab.
//  `tabs.spaceID` cascades, so every row moves to a surviving Space before the
//  Space row goes — archived under `.archiveTabs`, still open under
//  `.adopt(into:)`. Vivaldi closes every tab in a workspace with no undo. This
//  is the cheap place to beat that, because `closeTab` already archives.
//
//  What undo cannot give back is the website data. If the Space was the last one
//  its `WKWebsiteDataStore` is gone and WebKit has no un-remove.
//  The Space comes back logged out, and the deletion dialog has to have said so.
//

import AppKit
import BrowserKit

extension BrowserSession {

    // MARK: - Delete (§6.3)

    /// Deletes a Space, keeping its tabs.
    ///
    /// The last-Space guard and the teardown order are the ones this already
    /// had and they are right: tear every web view down, drop the rows, then
    /// remove the store — `remove(forIdentifier:)` fails while any live
    /// `WKWebView` still uses it. What is new is that nothing is destroyed on
    /// the way through, and that the whole thing is undoable.
    func deleteSpace(_ id: UUID, policy: SpaceDeletionPolicy = .archiveTabs) async throws {
        guard spaces.count > 1, let index = spaces.firstIndex(where: { $0.id == id }) else {
            throw SessionError.lastSpace
        }
        if case let .adopt(into: target) = policy {
            guard target != id, spaces.contains(where: { $0.id == target }) else {
                throw SessionError.unknownSpace
            }
        }
        let space = spaces[index]
        // Snapshot before anything moves, so undo restores what the user had
        // rather than what the deletion left behind.
        let snapshot = DeletedSpace(
            space: space,
            tabs: list[id].filter { $0.spaceID == id },
            archivedTabs: archived.filter { $0.spaceID == id },
            activeTabID: activeTabBySpace[id],
            policy: policy
        )

        evacuateTabs(of: id, policy: policy)

        spaces.remove(at: index)
        list.removeSpace(id)
        activeTabBySpace[id] = nil
        if activeSpaceID == id, let next = spaces.first { switchSpace(next.id) }
        // Drain first: every re-homed row above is a queued write, and the
        // cascade below would take any that had not landed yet.
        await writeChain?.value
        try await store.delete(spaceID: id)
        try await renumberSpaces()
        registerUndo(String(localized: "Delete Space")) { session in
            Task { try? await session.restoreSpace(snapshot) }
        }
        notifyChange()
        try await discardJar(of: space)
    }

    /// Removes the `WKWebsiteDataStore` a deleted Space owned (§6.3).
    ///
    /// Unconditional now. It used to ask whether any other Space still named
    /// the Profile, because several could; one Space, one jar, so the Space
    /// going is the jar going.
    private func discardJar(of space: Space) async throws {
        try await profileStore.remove(space)
    }

    /// Everything `deleteSpace` has to put back. Held by the undo closure only.
    struct DeletedSpace: Sendable {
        var space: Space
        var tabs: [Tab]
        var archivedTabs: [Tab]
        var activeTabID: UUID?
        var policy: SpaceDeletionPolicy
    }

    /// `⌘Z` after a Space deletion.
    ///
    /// The Space, its tabs and their history come back. The website data does
    /// not: `deleteSpace` removed the Space's `WKWebsiteDataStore`, and nothing
    /// in WebKit can un-remove one. The Space returns logged out — the honest
    /// half of an undo that is still worth having, since Vivaldi and Arc offer
    /// neither half.
    func restoreSpace(_ snapshot: DeletedSpace) async throws {
        guard space(snapshot.space.id) == nil else { return }
        var restored = snapshot.space
        restored.order = min(max(restored.order, 0), spaces.count)
        spaces.insert(restored, at: restored.order)
        list.addSpace(restored.id)
        try await store.upsert(restored)
        try await renumberSpaces()

        for tab in snapshot.tabs + snapshot.archivedTabs {
            var open = tab
            open.archivedAt = nil
            if list.tab(tab.id) != nil {
                discardController(tab.id)
                persistAll(list.remove(tab.id))
            }
            archived.removeAll { $0.id == tab.id }
            persistAll(list.insert(open))
        }
        for tab in snapshot.archivedTabs {
            var stowed = tab
            stowed.archivedAt = tab.archivedAt ?? Date()
            persistAll(list.remove(stowed.id))
            archived.insert(stowed, at: 0)
            write(stowed)
        }
        activeTabBySpace[restored.id] = snapshot.activeTabID
        registerUndo(String(localized: "Delete Space")) { session in
            Task { try? await session.deleteSpace(restored.id, policy: snapshot.policy) }
        }
        notifyChange()
    }

    /// Empties a doomed Space into a Space that survives it.
    private func evacuateTabs(of id: UUID, policy: SpaceDeletionPolicy) {
        let refuge: UUID
        switch policy {
        case let .adopt(into: target):
            refuge = target
        case .archiveTabs:
            // An archived tab is still a `tabs` row, so it needs a Space whose
            // foreign key will not cascade it away. The active Space is the one
            // the user will look in.
            refuge = spaces.first { $0.id != id && $0.id == activeSpaceID }?.id
                ?? spaces.first { $0.id != id }?.id ?? id
        }
        // A Favorite adopted into another Space lands in a jar that never saw
        // its login, and could blow that Space's cap besides. It is a login
        // tile; on the far side of a Space boundary it is a pinned tab.
        func section(_ tab: Tab) -> TabKind {
            tab.kind == .essential ? .pinned : tab.kind
        }
        for tab in list[id] where tab.spaceID == id {
            rehome(tab.id, to: refuge, as: section(tab), archiving: policy == .archiveTabs)
        }
        // The archive's own rows point at this Space too, and the cascade does
        // not care that they are archived.
        for tab in archived where tab.spaceID == id {
            var moved = tab
            moved.spaceID = refuge
            moved.kind = section(tab)
            archived.removeAll { $0.id == tab.id }
            archived.insert(moved, at: 0)
            write(moved)
        }
    }
}
