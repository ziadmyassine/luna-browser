//
//  BrowserSession+TabMenu.swift
//  Luna
//
//  The four verbs §3.4a's context menu needed and the §6 lifecycle did not already have:
//  duplicate, rename, change icon and mute. Pin, copy link and close were
//  all already here (`pinTab`, `closeTab`) or are nothing to do with the session at all.
//
//  Split out of `BrowserSession+Tabs.swift` for that file's length limit.
//  Everything below is about a tab's identity — what it is called, what it looks
//  like, whether it may make a sound — rather than where it sits in the list or
//  whether it has a process.
//
//  Rename and Change Icon persist; Mute does not, and the asymmetry is
//  deliberate. A name and an icon are decisions about the tab, and one that came
//  back after a relaunch under the page's own name would have thrown one away. A
//  mute is a decision about the noise a page is making now: a tab that came back
//  silent on the next launch, with nothing on screen to say why, is a bug
//  report.
//

import AppKit
import BrowserKit

extension BrowserSession {

    // MARK: - Duplicate

    /// Opens a second tab on the same page, directly below the first (§3.4a).
    ///
    /// With its back/forward history, not just its address. Chrome and Safari both
    /// duplicate the session rather than the URL, and it is the behaviour that makes the
    /// command worth having: you duplicate a tab to keep the trail you are on and go
    /// somewhere else from it. The blob is read off the live controller where there is
    /// one — the row's copy is only as fresh as the last settled load (§6.2).
    ///
    /// A duplicate of a §3.3 tile is an ordinary tab. A tile is a place the user put
    /// something, capped at twelve per Profile; a second copy of one is a page you want
    /// open now, which is what `.today` means.
    ///
    /// - Returns: the new tab, or nil if `id` names nothing.
    @discardableResult
    func duplicateTab(_ id: UUID) -> UUID? {
        guard let original = list.tab(id) else { return nil }
        let kind: TabKind = original.kind == .essential ? .today : original.kind
        let copy = Tab(
            spaceID: original.spaceID,
            kind: kind,
            url: original.url,
            title: original.title,
            faviconKey: original.faviconKey,
            themeColor: original.themeColor,
            // The tab it came from, which is what `parentTabID` is for (§6.5). A popup and
            // a duplicate are the same relationship: this page opened that one.
            parentTabID: original.id,
            interactionState: controllers[id]?.captureInteractionState() ?? original.interactionState,
            customTitle: original.customTitle,
            customSymbolName: original.customSymbolName
        )
        // Directly under the original, unless it was a tile — a tile has no position in the
        // list to be under, so the copy opens where any new tab does.
        let index = kind == original.kind
            ? list.indexInSection(of: id).map { $0 + 1 }
            : TabList.openIndex(for: kind)
        persistAll(list.insert(copy, at: index))
        registerUndo("Duplicate Tab") { $0.closeTab(copy.id) }
        activateTab(copy.id)
        return copy.id
    }

    // MARK: - Rename and Change Icon (§3.4a)

    /// Names a tab, or — with nil or a blank string — gives it back to the page.
    ///
    /// Blank is normalised to nil rather than stored, because `""` and nil would look the
    /// same in the sidebar and behave differently forever after: a stored empty string
    /// would keep overriding the page's title with nothing.
    func renameTab(_ id: UUID, to name: String?) {
        guard var tab = list.tab(id) else { return }
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let next = (trimmed?.isEmpty ?? true) ? nil : trimmed
        guard next != tab.customTitle else { return }
        let previous = tab.customTitle
        tab.customTitle = next
        write(tab)
        registerUndo("Rename Tab") { $0.renameTab(id, to: previous) }
        notifyChange()
    }

    /// Gives a tab an icon of its own, or — with nil — gives it back to the site.
    ///
    /// The name is not validated here and cannot usefully be: `NSImage(systemSymbolName:)`
    /// is the only thing that knows whether a symbol exists, it lives in AppKit, and the
    /// callers pick from a curated list anyway (`TabMenu.symbols`). What this does promise
    /// is that an empty string never reaches the column — nil is the way back to the
    /// favicon, and there is exactly one of it.
    func setIcon(_ symbolName: String?, forTab id: UUID) {
        guard var tab = list.tab(id) else { return }
        let next = (symbolName?.isEmpty ?? true) ? nil : symbolName
        guard next != tab.customSymbolName else { return }
        let previous = tab.customSymbolName
        tab.customSymbolName = next
        write(tab)
        registerUndo("Change Icon") { $0.setIcon(previous, forTab: id) }
        notifyChange()
    }

    // MARK: - Mute (§3.4a)

    func isMuted(_ id: UUID) -> Bool { mutedTabIDs.contains(id) }

    /// Silences the tab's media, or lets it speak again.
    ///
    /// The set is the truth and the controller is told; a cold tab has no controller to
    /// tell and is caught on the way back up by `ensureController`. Not undoable — every
    /// other verb in this file changes something you would have to hunt for afterwards,
    /// and this one is a toggle sitting on the row it belongs to.
    func setMuted(_ muted: Bool, tab id: UUID) {
        guard list.tab(id) != nil, muted != mutedTabIDs.contains(id) else { return }
        if muted { mutedTabIDs.insert(id) } else { mutedTabIDs.remove(id) }
        controllers[id]?.isMuted = muted
        notifyChange()
    }

    // MARK: - The menu

    /// §3.4a's verbs, bound to one tab.
    ///
    /// One binding for all three surfaces — §3.4's rows, §3.3's tiles and §4's top-bar
    /// strip. Each of them knows a different thing about a tab (a row index, a grid slot, a
    /// scroll position) and none of them knows anything about these verbs, so the menu is
    /// handed the same closure set wherever it is summoned from. Three bindings would be
    /// three chances for one surface's Duplicate to quietly mean something else.
    ///
    /// Every closure carries a `UUID` and is weak on the session: the menu is modal and
    /// outlives nothing, but it is the menu holding these and a window can close under it.
    func tabMenuActions(for id: UUID) -> TabMenu.Actions {
        TabMenu.Actions(
            pin: { [weak self] in self?.pinTab(id) },
            unpin: { [weak self] in self?.unpinTab(id) },
            setSaved: { [weak self] saved in self?.setTabSaved(saved, tab: id) },
            setGroup: { [weak self] group in self?.moveTab(id, toGroup: group) },
            newGroup: { [weak self] name, symbol in
                self?.createGroup(name: name, symbolName: symbol, containing: [id])
            },
            duplicate: { [weak self] in self?.duplicateTab(id) },
            rename: { [weak self] name in self?.renameTab(id, to: name) },
            setIcon: { [weak self] symbol in self?.setIcon(symbol, forTab: id) },
            setMuted: { [weak self] muted in self?.setMuted(muted, tab: id) },
            close: { [weak self] in self?.closeTab(id) }
        )
    }

    /// §3.4b's five, bound to one group. Same shape and the same reasons: the menu is
    /// modal and outlives nothing, but it is the menu holding these and a window can
    /// close under it.
    func groupMenuActions(for id: UUID) -> GroupMenu.Actions {
        GroupMenu.Actions(
            rename: { [weak self] name in self?.renameGroup(id, to: name) },
            setIcon: { [weak self] symbol in self?.setIcon(symbol, forGroup: id) },
            setSaved: { [weak self] saved in self?.setGroupSaved(saved, group: id) },
            ungroup: { [weak self] in self?.ungroup(id) },
            close: { [weak self] in self?.closeGroup(id) }
        )
    }
}
