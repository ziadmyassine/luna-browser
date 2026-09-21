//
//  TabListController.swift
//  Luna
//
//  The §3.4 list. An `NSTableView`, deliberately:
//
//  · §19.1 asks for 120 fps with 40+ rows. `NSTableView` recycles row views,
//    lays out only what is visible, and — with a fixed `rowHeight` — never asks
//    a row how tall it is while scrolling. A stack of 40 live views in a scroll
//    view (what the SwiftUI browsers ship) re-lays the whole column per frame.
//  · It hands us arrow-key traversal, type-ahead (`typeSelectStringFor`) and
//    per-row VoiceOver for free — §7.4 and §21.1 in one decision.
//  · `NSOutlineView` would add expand/collapse machinery for sections that do
//    not expand or collapse. The Essentials grid is a header above the scroll
//    view, not a parent node.
//
//  The selected pill and the hover fill are one view each, moved between rows,
//  rather than a background per row. §6 asks the selected pill to move on a
//  0.20 s spring, which only a single view can do, and it means a scroll
//  allocates no glass at all.
//

import AppKit
import BrowserKit

@MainActor
final class TabListController: NSObject {

    /// `SidebarScrollView`, not `NSScrollView`: §30.9's swipe is caught on the
    /// sidebar's plane, and a scroll view consumes both axes — so without the
    /// subclass the gesture would work everywhere except over the rows, which
    /// is most of the column and all of the part a hand rests on.
    let scrollView: NSScrollView = SidebarScrollView()

    var onActivateTab: ((UUID) -> Void)?
    var onCloseTab: ((UUID) -> Void)?
    var onToggleMute: ((UUID) -> Void)?
    var onAddTab: (() -> Void)?
    /// §3.4b: the chevron on a group header, or Enter on one.
    var onToggleGroup: ((UUID) -> Void)?
    /// §3.4b's group menu, bound to one group — `BrowserSession.groupMenuActions(for:)`.
    var groupMenuActions: ((UUID) -> GroupMenu.Actions?)?
    /// §3.4b: a right-click on the column's empty plane asked for a folder.
    var onNewGroup: (() -> Void)?
    /// §3.4b: a folder's name was typed on its own row and confirmed.
    var onRenameGroup: ((UUID, String) -> Void)?

    /// §3.4b's icon, picked from macOS's emoji palette on the folder's own row.
    var onSetGroupIcon: ((UUID, String) -> Void)?

    /// §3.4a's rename, typed on the row. Blank means "give the name back to the
    /// page" — `BrowserSession.renameTab` is where that is read.
    var onRenameTab: ((UUID, String) -> Void)?
    /// §3.4a's menu, bound to one tab — `BrowserSession.tabMenuActions(for:)`. Nil leaves
    /// the rows with no context menu rather than a shorter one: a second, smaller answer
    /// to the same right-click is exactly what §3.4a exists to avoid.
    var menuActions: ((UUID) -> TabMenu.Actions?)?

    private(set) var list = SidebarList()
    /// What the list was last handed, so a drag can rebuild the rows with
    /// §3.4b's rule revealed without the sidebar having to hand them over again.
    private var shown: (saved: [SidebarSlot], today: [SidebarSlot], essentials: [Tab]) = ([], [], [])
    /// A §6.6 lift is up, so the saved tier's rule is out whether or not
    /// anything is saved — see `SidebarList`'s header.
    private var isRevealingSaved = false
    /// The group header a lift is currently aimed inside, which is the only
    /// feedback a folded group can give: there are no rows in it to open a gap
    /// between.
    var groupDropRow: Int?
    /// Live per-tab state, pushed in by `BrowserSession.onTabStateChange`.
    var liveStates: [UUID: TabState] = [:]
    /// Muted tabs (§3.4a), mirrored from `BrowserSession.mutedTabIDs` so a row can draw
    /// its speaker without asking. The session is the truth — it is what re-asserts the
    /// mute on a tab waking from hibernation — and `SidebarViewController.refresh()` is
    /// what keeps the two in step.
    var mutedTabIDs: Set<UUID> = []

    let table = SidebarTableView()
    /// Not private, for the same reason `list` and `table` are not: the two
    /// pills and everything that places them live in
    /// `TabListController+Pills.swift`, and Swift's `private` is file-scoped.
    let selectionPill = RowPillView(role: .selected)
    let hoverPill = RowPillView(role: .hover)
    /// The row under the pointer. Internal for `+Content.swift`'s sake, which
    /// is what decides whether a row draws its close chip or its speaker.
    private(set) var hoveredRow: Int?
    var activeTabID: UUID?
    var isApplyingSelection = false
    /// A press landed on a tab row. `SidebarTabDragController` runs the rest
    /// of the gesture from here — see `SidebarTabDrag.swift` for why the list
    /// does not use `NSTableView`'s own drag and drop for this.
    /// - Returns: whether the press became §6.6's lift. A folder's header uses
    ///   the answer to decide whether the gesture was a fold or a move.
    var onTabPress: ((_ row: Int, _ event: NSEvent) -> Bool)?
    /// The row being carried, while §6.6's lift is up. Its view is hidden: the
    /// lift is standing in for it. Internal because the gesture lives in
    /// `TabListController+Lift.swift`, as `isApplyingSelection` is for the
    /// delegate next door.
    var draggedRow: Int?
    /// Whether a lift is up over this list at all. Not the same question as
    /// `draggedRow != nil`: a tile carried down from the §3.3 grid has no row
    /// here to be carried from, and the gap it opens is still the list's to
    /// draw. See `beginIncomingDrag()`.
    var isDragging = false
    /// Where the lift would land, in row space — or nil while it is over the
    /// §3.3 grid, where the list's answer is "nowhere, close up".
    var gapRow: Int?

    override init() {
        super.init()
        buildTable()
        buildScrollView()
    }

    private func buildTable() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("row"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.headerView = nil
        table.style = .plain
        table.backgroundColor = .clear
        table.usesAutomaticRowHeights = false
        table.rowHeight = Tokens.Metric.rowHeight
        table.intercellSpacing = .zero
        table.gridStyleMask = []
        // §30.7: unselected rows have no background at all, and the selected
        // one is our own glass pill — AppKit must not paint either.
        table.selectionHighlightStyle = .none
        table.allowsMultipleSelection = false
        table.allowsEmptySelection = true
        table.dataSource = self
        table.delegate = self
        table.onRowPress = { [weak self] row, event in self?.press(row: row, event: event) }
        // The pills are not rows: §3.7's resize re-lays every row and leaves
        // them at the old width until the next click. This is what moves them.
        table.onLayout = { [weak self] in
            self?.restoreGap()
            self?.movePills(animated: false)
        }
        table.onCommandKey = { [weak self] command in self?.handle(command) ?? false }
        table.onFocusChange = { [weak self] in self?.movePills() }
        table.onHover = { [weak self] row in self?.setHovered(row) }
        table.onContextMenu = { [weak self] row in self?.contextMenu(forRow: row) }

        for pill in [selectionPill, hoverPill] {
            pill.alphaValue = 0
            table.addSubview(pill, positioned: .below, relativeTo: nil)
        }
    }

    /// No scroller at all, which `.overlay` is not: overlay draws over the
    /// content, and the content is a pill inset 8 pt from the sidebar's edge
    /// with the close affordance a `rowInset` inside that — so it came down on
    /// the one strip of the row the pointer is already on, narrow as it faded
    /// in and then knob-and-track wide as soon as the pointer neared it, which
    /// over this list is nearly always: the pointer is here to use the list.
    ///
    /// Nothing is lost with it gone: a scroller is a place to drag and a
    /// read-out of position; the first is the wheel, the trackpad, the arrow
    /// keys and `scrollRowToVisible`, and the second the rows say better.
    /// Hence the property, not a scroller subclass drawing nothing: that is
    /// still a view AppKit lays out, hit-tests and hands to VoiceOver.
    private func buildScrollView() {
        scrollView.documentView = table
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.horizontalScrollElasticity = .none
        scrollView.contentView.drawsBackground = false
        scrollView.automaticallyAdjustsContentInsets = false
    }

    // MARK: - Content

    /// The rows, and whether what changed is an edit to this list or a
    /// different list entirely.
    ///
    /// A Space switch is the second, and it used to be treated as the
    /// first. `apply` is §6's insert: it fades the outgoing rows over
    /// `tabInsert`, which is exactly right when one tab closes and wrong for
    /// every row at once — `NSTableView` keeps a row being removed on screen
    /// for the length of its animation, so the Space you had just left stayed
    /// drawn, fading, over the Space you had just arrived in. That is the flash
    /// of old tabs. `SidebarViewController` is already cross-fading the whole
    /// column for this; the rows must not bring a second transition to it.
    func show(
        saved: [SidebarSlot],
        today: [SidebarSlot],
        essentials: [Tab],
        activeTabID: UUID?,
        replacing: Bool = false
    ) {
        shown = (saved, today, essentials)
        rebuild(activeTabID: .some(activeTabID), replacing: replacing)
    }

    /// Re-derives the rows from what was last handed over and diffs them in.
    ///
    /// Separate from `show` because two things change the rows without changing
    /// the tabs: a §3.4b group folding, and a lift starting or ending — which
    /// brings the saved tier's rule out and puts it away again.
    /// - Parameter activeTabID: the selection to apply, or nothing at all to
    ///   keep the one already on screen. Two different answers, which is why it
    ///   is a double optional: `.some(nil)` is "no row is selected", and the
    ///   single optional this used to take could not say it — a Space whose
    ///   last page had just been closed handed over a nil that read as "leave
    ///   it alone", so §3.4's pill stayed lying on the row the user had closed
    ///   and the next `⌘W` let that row go.
    func rebuild(activeTabID: UUID?? = nil, replacing: Bool = false) {
        let next = SidebarList(
            saved: shown.saved,
            today: shown.today,
            essentials: shown.essentials,
            revealingSaved: isRevealingSaved
        )
        let diff = next.rows.difference(from: list.rows)
        list = next
        if replacing {
            table.reloadData()
            table.needsLayout = true
        } else if diff.isEmpty {
            refreshVisibleRows()
        } else {
            apply(diff)
        }
        // The selection pill springs from the row it was on to the row it is
        // on, which across a replacement is a spring between two unrelated
        // rows — it has to be placed, not flown.
        setActive(activeTabID ?? self.activeTabID, movingPills: !replacing)
    }

    /// §3.4b: the rule comes out for the length of a drag, because a zone you
    /// cannot see is a zone you cannot aim at. A no-op once something is saved,
    /// where the rule is already there.
    func setRevealingSaved(_ revealing: Bool) {
        guard isRevealingSaved != revealing else { return }
        isRevealingSaved = revealing
        rebuild()
    }

    /// Rebuilds every row from scratch and re-places the pills.
    ///
    /// `show(_:activeTabID:)` diffs and does nothing when the rows are
    /// unchanged, which is right on every path but one: coming back from a
    /// layout where this list was hidden, the rows are unchanged and the row
    /// views are gone. This is the path for that.
    func reload() {
        table.reloadData()
        table.needsLayout = true
        movePills()
    }

    /// One tab's live state changed — title, loading, audio (§4.3). Only that
    /// row is touched, so a busy page does not redraw the list.
    func update(_ id: UUID, state: TabState) {
        liveStates[id] = state
        guard let row = list.row(of: id), let view = table.view(atColumn: 0, row: row, makeIfNecessary: false) else {
            return
        }
        (view as? SidebarRowView)?.configure(content(for: row))
    }

    private func apply(_ diff: CollectionDifference<SidebarRow>) {
        // §6: 0.22 s, fade, no list jump. `CollectionDifference` iterates
        // removals descending then insertions ascending, which is exactly the
        // order `NSTableView` wants.
        let effect: NSTableView.AnimationOptions = Tokens.Motion.reduceMotion ? [] : .effectFade
        Tokens.Motion.animate(Tokens.Motion.tabInsert) { _ in
            table.beginUpdates()
            for change in diff {
                switch change {
                case let .remove(offset, _, _): table.removeRows(at: [offset], withAnimation: effect)
                case let .insert(offset, _, _): table.insertRows(at: [offset], withAnimation: effect)
                }
            }
            table.endUpdates()
        }
        refreshVisibleRows()
    }

    private func refreshVisibleRows(movingPills animated: Bool = true) {
        let visible = table.rows(in: table.visibleRect)
        for row in visible.lowerBound ..< visible.upperBound {
            guard let view = table.view(atColumn: 0, row: row, makeIfNecessary: false) as? SidebarRowView else {
                continue
            }
            view.configure(content(for: row))
            view.isSelected = row == table.selectedRow
            view.isHovered = row == hoveredRow
        }
        movePills(animated: animated)
    }

    // MARK: - Selection and hover

    private func setActive(_ id: UUID?, movingPills animated: Bool = true) {
        activeTabID = id
        isApplyingSelection = true
        if let id, let row = list.row(of: id) {
            table.selectRowIndexes([row], byExtendingSelection: false)
        } else {
            table.deselectAll(nil)
        }
        isApplyingSelection = false
        refreshVisibleRows(movingPills: animated)
    }

    private func setHovered(_ row: Int?) {
        guard row != hoveredRow else { return }
        let previous = hoveredRow
        hoveredRow = row
        for index in [previous, row].compactMap({ $0 }) {
            guard let view = table.view(atColumn: 0, row: index, makeIfNecessary: false) as? SidebarRowView else {
                continue
            }
            view.isHovered = index == row
            view.configure(content(for: index))
        }
        movePills()
    }

    // MARK: - Commands

    /// A press on a row, which is the whole mouse gesture: `NSTableView`'s own
    /// `mouseDown` runs a tracking loop that never lets go until mouse-up, and
    /// §6.6's lift needs the drags. See `SidebarTabDrag.swift`.
    private func press(row: Int, event: NSEvent) {
        table.window?.makeFirstResponder(table)
        switch list[row] {
        case .tab:
            // Selected on the press, exactly as a table selects: the page is up
            // before the gesture is over. The lift takes the rest of it.
            table.selectRowIndexes([row], byExtendingSelection: false)
            onTabPress?(row, event)
        case let .group(id):
            // A folder's header does two things, told apart by whether the hand
            // moved. Still there it folds — the whole header, not only the
            // chevron, because a heading over a list is the affordance and a
            // 16 pt glyph is a smaller target than the thing it is about. Moved
            // it lifts, because a folder is a slot in §3.4b's list like any
            // other and has to be movable to be arranged.
            //
            // The lift runs the event loop itself, so this cannot ask first: by
            // the time there is an answer the gesture is over, and the answer
            // is what it returns.
            guard onTabPress?(row, event) != true else { return }
            onToggleGroup?(id)
        case .addTab:
            guard Self.isClick(event, on: row, in: table) else { return }
            onAddTab?()
        case .separator, .none:
            // Furniture. Dragging it moves the window, like the rest of the
            // sidebar's plane (§30.1).
            table.window?.performDrag(with: event)
        }
    }

    /// Waits out the gesture and reports whether it ended on the same row —
    /// AppKit's own "did the click land" rule, which `super.mouseDown` would
    /// have applied for us.
    private static func isClick(_ event: NSEvent, on row: Int, in table: NSTableView) -> Bool {
        guard let window = table.window else { return false }
        while let next = window.nextEvent(matching: [.leftMouseUp, .leftMouseDragged]) {
            guard next.type == .leftMouseUp else { continue }
            return table.row(at: table.convert(next.locationInWindow, from: nil)) == row
        }
        return false
    }

    /// Moves the selection by `offset` tab rows and activates what it lands on
    /// (§7.4's `⌘⌥←/→`). Public so the window's key map can drive it.
    func selectAdjacentTab(offset: Int) {
        guard !list.listed.isEmpty else { return }
        let current = list.listed.firstIndex { $0.id == activeTabID } ?? 0
        let next = (current + offset + list.listed.count) % list.listed.count
        onActivateTab?(list.listed[next].id)
    }

    private func handle(_ command: SidebarTableView.Command) -> Bool {
        switch command {
        case .previousTab: selectAdjacentTab(offset: -1)
        case .nextTab: selectAdjacentTab(offset: 1)
        case .confirm:
            switch list[table.selectedRow] {
            case .addTab: onAddTab?()
            case let .group(id): onToggleGroup?(id)
            default: return false
            }
        case .close:
            guard case let .tab(id)? = list[table.selectedRow] else { return false }
            onCloseTab?(id)
        }
        return true
    }

    /// §21.2, contract rule 4: Increase Contrast is not an appearance.
    func accessibilityDisplayOptionsChanged() {
        selectionPill.needsDisplay = true
        hoverPill.needsDisplay = true
        let visible = table.rows(in: table.visibleRect)
        for row in visible.lowerBound ..< visible.upperBound {
            (table.view(atColumn: 0, row: row, makeIfNecessary: false) as? SidebarRowView)?
                .accessibilityDisplayOptionsChanged()
        }
    }
}
