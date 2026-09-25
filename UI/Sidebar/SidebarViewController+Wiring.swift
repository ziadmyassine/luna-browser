//
//  SidebarViewController+Wiring.swift
//  Luna
//
//  Where the column's controls are joined to the session: the control row, the
//  URL pill, §3.7's handle, the utility bar, §3.3's grid and §3.4's list.
//
//  Split out of `SidebarViewController.swift` when that class crossed
//  SwiftLint's type-body limit, and it is the right seam: everything here is
//  one closure being handed over and nothing here holds any state. The file it
//  came out of is left with what the column *is* — its views, its layout and
//  what it draws from the session.
//

import AppKit
import BrowserKit

extension SidebarViewController {

    func wireControls() {
        controlRow.onToggleSidebar = { [weak self] in self?.onToggleSidebar?() }
        controlRow.onBack = { [weak self] in self?.session.goBack() }
        controlRow.onForward = { [weak self] in self?.session.goForward() }
        // The pill hands off to §9.1 rather than opening itself, and §9.1
        // opens on the pill: the bar takes its place, at its width, and grows
        // down out of it (`CommandBarAnchor`). The field, the history, the
        // ranking and the list are all already there, and none of them would
        // fit in a 260 pt column. §3.2b's pill now does exactly the same.
        pill.onHandOff = { [weak self] in
            guard let self else { return }
            presentCommandBar?(.editCurrentURL, CommandBarAnchor(view: pill))
        }
        controlRow.onReloadOrStop = { [weak self] isLoading in
            guard let self else { return }
            if isLoading { session.stop() } else { session.reload() }
        }
        // §3.2's site settings are about the page, and every answer in them is
        // one the session already holds — so they open themselves rather than
        // being routed out to the coordinator and straight back in.
        pill.onSiteMenu = { [weak self] in
            guard let self else { return }
            SiteMenu.present(from: pill.siteMenuAnchor)
        }
        handle.onWidthChange = { [weak self] width in self?.onWidthChange?(width) }
        handle.onWidthCommitted = { [weak self] width in self?.onWidthChange?(width) }

        utility.onProfile = { [weak self] in self?.onProfileMenu?() }
        // §6.2 lives in Settings and there is one window of it, so the foot of
        // the sidebar asks the app for it rather than growing its own copy —
        // the same route §3.2's site settings take to the Advanced section.
        utility.onEditSpaces = { [weak self] in self?.spaces?.editSpaces() }
        utility.onNewSpace = { [weak self] in self?.spaces?.createSpace() }
        utility.onManageProfiles = { [weak self] in self?.spaces?.editSpaces() }
        utility.onHistory = { [weak self] in self?.onOpenHistory?() }
        utility.onDownloads = { [weak self] in self?.onOpenDownloads?() }
        utility.onSwitchSpace = { [weak self] id in self?.switchSpace(id) }
        // §8.2 / §13.6. The failure is silent on purpose: a colour that did not
        // persist is a cosmetic disappointment on the next launch, not
        // something to interrupt the user mid-browse with a dialog.
        utility.onSetGradient = { [weak self] space, gradient in
            Task { try? await self?.session.setGradient(gradient, forSpace: space) }
        }

        essentials.onActivate = { [weak self] id in self?.activateTab(id) }
        essentials.onUnpin = { [weak self] id in self?.session.unpinTab(id) }
        // §3.4a's menu, on the §3.3 tiles as well as the §3.4 rows: a tile is a tab, and
        // a menu that changed its mind about what you can do to one depending on which
        // half of the sidebar it is standing in would be two menus, not one.
        essentials.menuActions = { [weak self] id in self?.session.tabMenuActions(for: id) }
        essentials.isMuted = { [weak self] id in self?.session.isMuted(id) ?? false }
    }

    func wireList() {
        // §5.6: no kept tier, so §3.4b's rule never comes out and the top half
        // of `New Tab` is not a place a drop can pin something.
        list.allowsPinning = session.allowsPinning
        list.icons = session.icons
        list.onActivateTab = { [weak self] id in self?.activateTab(id) }
        list.onCloseTab = { [weak self] id in self?.session.closeTab(id) }
        // §9.1, not a blank tab. The Command Bar opens in `.newTab` — so what
        // it lands on is a new tab — and closing it without choosing leaves
        // the list exactly as it was rather than one empty page longer.
        list.onAddTab = { [weak self] in self?.presentCommandBar?(.newTab, nil) }
        list.menuActions = { [weak self] id in self?.session.tabMenuActions(for: id) }
        list.groupMenuActions = { [weak self] id in self?.session.groupMenuActions(for: id) }
        // §3.4b: a folder is made empty and named on its own row. The session
        // says when the row exists; the column is what opens the field on it.
        list.onNewGroup = { [weak self] in
            self?.session.createGroup(name: BrowserSession.untitledGroupName)
        }
        list.onRenameGroup = { [weak self] id, name in self?.session.renameGroup(id, to: name) }
        list.onRenameTab = { [weak self] id, name in self?.session.renameTab(id, to: name) }
        list.onSetGroupIcon = { [weak self] id, symbol in self?.session.setIcon(symbol, forGroup: id) }
        session.onGroupCreated = { [weak self] id in self?.list.beginRenaming(group: id) }
        // §3.4b: folding is a fact about the group, so it goes through the
        // session and comes back as a change like any other. The rows are
        // diffed, which is what makes the tabs fade out rather than vanish.
        list.onToggleGroup = { [weak self] id in
            guard let self, let group = session.group(id) else { return }
            // A folder whose agent is waiting for the user opens its request
            // instead of folding: the click is how the user answers the mark.
            if let header = list.headerView(ofGroup: id), ControlApprovalCard.showIfWaiting(forFolder: id, from: header) {
                return
            }
            session.setGroupCollapsed(!group.isCollapsed, forGroup: id)
        }
        wireDrag()
        list.onToggleMute = { [weak self] id in
            guard let self else { return }
            // The session owns the answer — it is what silences the page and what puts the
            // mute back when a cold tab wakes up. The list's copy follows it rather than
            // leading, so the row's speaker and the sound cannot disagree.
            session.setMuted(!session.isMuted(id), tab: id)
            list.mutedTabIDs = session.mutedTabIDs
            if let state = session.controller(for: id)?.state { list.update(id, state: state) }
            onToggleMute?(id)
        }
    }
}
