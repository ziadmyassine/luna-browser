//
//  BrowserSession+Groups.swift
//  Luna
//
//  §3.4b's verbs: making a group, naming it, folding it, moving it across the
//  rule, taking it apart, and moving one tab in or out of one.
//
//  Split out of `BrowserSession+Tabs.swift` for that file's length limit, and it
//  is the right seam: everything here is about a *name around some tabs*, and
//  nothing here decides anything about a web view. Where the rows end up is
//  `TabList`'s, which is why none of this does arithmetic on an index.
//
//  Two rules hold the whole thing together:
//
//    · A group's tier is its tabs' tier. Drag a group above the rule and its
//      tabs are saved; drag it back and they are ordinary tabs again. So "is
//      this tab saved" is one question with one answer wherever it is asked,
//      and `closeTab` never has to look at a group to decide what a press means.
//    · Removing a group removes a name, never a page. `ungroup` leaves every
//      tab exactly where the group stood. The one command that does end the tabs
//      says so — and archives them one at a time, where undo can reach them.
//

import AppKit
import BrowserKit

extension BrowserSession {

    // MARK: - Reading

    /// The active Space's groups, in the order §3.4 draws them.
    var groups: [TabGroup] { list.groups(inSpace: activeSpaceID) }

    func group(_ id: UUID) -> TabGroup? { list.group(id) }

    func members(ofGroup id: UUID) -> [Tab] { list.members(ofGroup: id) }

    /// One of §3.4's two tiers, as the column draws it: the slots in order, each
    /// group carrying its own tabs.
    func slots(inTier kind: TabKind) -> [SidebarSlot] {
        list.drawnSlots(inSpace: activeSpaceID, kind: kind)
    }

    // MARK: - Making one

    /// Makes a group in the active Space and moves `tabs` into it, in the order
    /// given (§3.4b).
    ///
    /// It lands where the first tab going into it was standing, which is the
    /// only answer that does not move the list under the pointer: a group made
    /// from the row you right-clicked appears at that row. With no tabs it goes
    /// to the end of its section, because there is nowhere else it could mean.
    ///
    /// - Returns: nil for a blank name. A group is a label, and a label with no
    ///   text is a row the user cannot tell from any other.
    @discardableResult
    func createGroup(
        name: String,
        symbolName: String = TabGroup.defaultSymbolName,
        kind: TabKind = .today,
        containing tabs: [UUID] = []
    ) -> UUID? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let members = tabs.compactMap { list.tab($0) }.filter { $0.kind != .essential }
        let tier = TabGroup.sanitised(members.first?.kind ?? kind)
        // Only a loose tab has a slot to hand over. `indexInSection` counts a
        // grouped tab's place among its siblings, which is not a position in
        // this section at all — so a group made out of one is appended.
        let slot = members.first.flatMap { $0.groupID == nil ? list.indexInSection(of: $0.id) : nil }
        let group = TabGroup(spaceID: activeSpaceID, name: trimmed, symbolName: symbolName, kind: tier)
        persistAll(list.insertGroup(group, at: slot))
        for member in members { gather(member.id, into: group) }
        registerUndo("New Group") { $0.ungroup(group.id) }
        notifyChange()
        return group.id
    }

    // MARK: - Changing one

    /// Names a group. A blank name is refused rather than stored, for
    /// `createGroup`'s reason: there would be nothing on the row to read.
    func renameGroup(_ id: UUID, to name: String) {
        guard var group = list.group(id) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != group.name else { return }
        let previous = group.name
        group.name = trimmed
        commit(group)
        registerUndo("Rename Group") { $0.renameGroup(id, to: previous) }
    }

    /// Gives a group another icon. Not validated here and cannot usefully be —
    /// `NSImage(systemSymbolName:)` is the only thing that knows whether a
    /// symbol exists, it lives in AppKit, and the caller picks from a curated
    /// list for the reason §3.4a's icon picker gives.
    func setIcon(_ symbolName: String, forGroup id: UUID) {
        guard var group = list.group(id), !symbolName.isEmpty, symbolName != group.symbolName else { return }
        let previous = group.symbolName
        group.symbolName = symbolName
        commit(group)
        registerUndo("Change Icon") { $0.setIcon(previous, forGroup: id) }
    }

    /// Folds a group shut, or opens it. Not undoable: it changes nothing about
    /// any tab, and the chevron it happened on is sitting right there.
    func setGroupCollapsed(_ collapsed: Bool, forGroup id: UUID) {
        guard var group = list.group(id), group.isCollapsed != collapsed else { return }
        group.isCollapsed = collapsed
        commit(group)
    }

    /// Carries a group across §3.4b's rule, its tabs with it.
    func setGroupSaved(_ saved: Bool, group id: UUID) {
        guard let group = list.group(id), group.isSaved != saved else { return }
        let kind: TabKind = saved ? .pinned : .today
        moveGroup(id, to: list.slots(inSpace: group.spaceID, kind: kind).count, kind: kind)
    }

    /// §6.6's drop, for a group: a slot in one of the two sections.
    func moveGroup(_ id: UUID, to index: Int, kind: TabKind) {
        guard var group = list.group(id) else { return }
        let from = (index: group.order, kind: group.kind)
        group.kind = TabGroup.sanitised(kind)
        persistAll(list.insertGroup(group, at: index))
        // A tab carried across the rule inside its group needs the same
        // bookkeeping one carried on its own gets — the address it goes home to,
        // or none at all. `TabList` has already re-tiered them; this records
        // what that tier means.
        for member in list.members(ofGroup: id) {
            write(Self.keepingWhatItIsFor(member, wasKept: from.kind != .today))
        }
        registerUndo("Move Group") { $0.moveGroup(id, to: from.index, kind: from.kind) }
        notifyChange()
    }

    // MARK: - Taking one apart

    /// Removes the name and leaves the tabs where it stood (§3.4b's *Ungroup*).
    func ungroup(_ id: UUID) {
        guard let group = list.group(id) else { return }
        let members = list.members(ofGroup: id).map(\.id)
        let slot = group.order
        persistAll(list.removeGroup(id))
        forgetGroup(id)
        registerUndo("Ungroup") { session in
            session.persistAll(session.list.insertGroup(group, at: slot))
            for member in members { session.gather(member, into: group) }
            // Its own undo, so `⌘⇧Z` takes the group apart again. `gather` and
            // `insertGroup` register nothing — that is what makes them usable
            // from inside an undo in the first place.
            session.registerUndo("Ungroup") { $0.ungroup(group.id) }
            session.notifyChange()
        }
        notifyChange()
    }

    /// Closes every tab in the group and then removes it.
    ///
    /// The tabs go through `closeTab`, one at a time, so each lands in §6.3's
    /// archive and each registers its own undo — which is what makes `⌘Z` after
    /// this give the pages back rather than only the name. A saved group's tabs
    /// dim on the way rather than leaving, exactly as pressing close on each of
    /// them would, and pressing Close Group again is what finally lets them go.
    func closeGroup(_ id: UUID) {
        guard list.group(id) != nil else { return }
        let members = list.members(ofGroup: id)
        for member in members { closeTab(member.id) }
        guard list.members(ofGroup: id).isEmpty else {
            notifyChange()
            return
        }
        ungroup(id)
    }

    // MARK: - One tab

    /// Moves a tab into a group, or — with nil — out of whatever group it is in
    /// and back to a loose slot in the same section (§3.4b's menu).
    func moveTab(_ id: UUID, toGroup groupID: UUID?) {
        guard let tab = list.tab(id), tab.kind != .essential, tab.groupID != groupID else { return }
        guard let groupID, let group = list.group(groupID) else {
            reorderTab(id, to: list.slots(inSpace: tab.spaceID, kind: tab.kind).count, kind: tab.kind)
            return
        }
        reorderTab(id, to: list.members(ofGroup: group.id).count, kind: group.kind, group: group.id)
    }

    /// §3.4b's *Save* / *Remove from Saved*, for one tab.
    ///
    /// It comes out of any group on the way across. A group's tier is its tabs'
    /// tier, so a tab that stayed in an ordinary group while claiming to be
    /// saved would be the one row in the list whose section and behaviour
    /// disagreed — the thing this design exists to make impossible. Saving the
    /// whole group is the other command, and it is one item further down the
    /// same menu.
    func setTabSaved(_ saved: Bool, tab id: UUID) {
        guard let tab = list.tab(id), tab.kind != .essential else { return }
        let kind: TabKind = saved ? .pinned : .today
        guard tab.kind != kind || tab.groupID != nil else { return }
        let index = saved ? list.slots(inSpace: tab.spaceID, kind: kind).count : 0
        reorderTab(id, to: index, kind: kind)
    }

    func isSaved(_ id: UUID) -> Bool { list.tab(id)?.kind == .pinned }

    // MARK: - Plumbing

    /// Writes a group whose position has not changed — a name, an icon, a fold.
    private func commit(_ group: TabGroup) {
        list.updateGroup(group)
        enqueue { store in try? await store.upsert(group) }
        notifyChange()
    }

    /// Moves one tab to the end of a group, with no undo entry of its own: the
    /// callers that use this register one for the whole operation.
    func gather(_ id: UUID, into group: TabGroup) {
        guard var tab = list.tab(id), tab.kind != .essential else { return }
        let wasKept = tab.kind.keepsTabWhenPageCloses
        persistAll(list.remove(id))
        tab.kind = group.kind
        tab.groupID = group.id
        persistAll(list.insert(Self.keepingWhatItIsFor(tab, wasKept: wasKept)))
    }

    /// Drops the group from the store. In-memory removal is `TabList`'s; this is
    /// the row on disk, on the same write chain as the renumber that emptied it.
    private func forgetGroup(_ id: UUID) {
        enqueue { store in try? await store.delete(groupID: id) }
    }
}
