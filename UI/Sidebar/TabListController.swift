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
//  The **selected pill and the hover fill are one view each**, moved between
//  rows, not a background per row. §6 asks the selected pill to *move* on a
//  0.20 s spring, which only a single view can do — and it means a scroll
//  allocates no glass at all.
//

import AppKit
import BrowserKit

@MainActor
final class TabListController: NSObject {

    let scrollView = NSScrollView()

    var onActivateTab: ((UUID) -> Void)?
    var onCloseTab: ((UUID) -> Void)?
    var onToggleMute: ((UUID) -> Void)?
    var onAddTab: (() -> Void)?
    /// Right-click → Pin Tab. The tab becomes a tile in the §3.3 grid.
    var onPinTab: ((UUID) -> Void)?

    private(set) var list = SidebarList()
    /// Live per-tab state, pushed in by `BrowserSession.onTabStateChange`.
    var liveStates: [UUID: TabState] = [:]
    /// Muted tabs. Local because neither `BrowserSession` nor `TabController`
    /// exposes a mute — see the milestone report.
    var mutedTabIDs: Set<UUID> = []

    let table = SidebarTableView()
    private let selectionPill = RowPillView(role: .selected)
    private let hoverPill = RowPillView(role: .hover)
    private(set) var hoveredRow: Int?
    private var activeTabID: UUID?
    var isApplyingSelection = false
    /// A press landed on a **tab** row. `SidebarTabDragController` runs the rest
    /// of the gesture from here — see `SidebarTabDrag.swift` for why the list
    /// does not use `NSTableView`'s own drag and drop for this.
    var onTabPress: ((_ row: Int, _ event: NSEvent) -> Void)?
    /// The row being carried, while §6.6's lift is up. Its view is hidden: the
    /// lift is standing in for it. Internal because the gesture lives in
    /// `TabListController+Lift.swift`, as `isApplyingSelection` is for the
    /// delegate next door.
    var draggedRow: Int?
    /// Whether a lift is up over this list at all. Not the same question as
    /// `draggedRow != nil`: a tile carried down from the §3.3 grid has no row
    /// here to be carried *from*, and the gap it opens is still the list's to
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
        table.onLayout = { [weak self] in self?.restoreGap() }
        table.onCommandKey = { [weak self] command in self?.handle(command) ?? false }
        table.onFocusChange = { [weak self] in self?.movePills() }
        table.onHover = { [weak self] row in self?.setHovered(row) }
        table.onContextMenu = { [weak self] row in self?.contextMenu(forRow: row) }

        for pill in [selectionPill, hoverPill] {
            pill.alphaValue = 0
            table.addSubview(pill, positioned: .below, relativeTo: nil)
        }
    }

    private func buildScrollView() {
        scrollView.documentView = table
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.contentView.drawsBackground = false
        scrollView.automaticallyAdjustsContentInsets = false
    }

    // MARK: - Content

    func show(_ tabs: [Tab], activeTabID: UUID?) {
        let next = SidebarList(tabs: tabs)
        let diff = next.rows.difference(from: list.rows)
        list = next
        if diff.isEmpty {
            refreshVisibleRows()
        } else {
            apply(diff)
        }
        setActive(activeTabID)
    }

    /// Rebuilds every row from scratch and re-places the pills.
    ///
    /// `show(_:activeTabID:)` diffs and does nothing when the rows are
    /// unchanged, which is right on every path but one: coming back from a
    /// layout where this list was hidden, the rows are unchanged *and* the row
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

    private func refreshVisibleRows() {
        let visible = table.rows(in: table.visibleRect)
        for row in visible.lowerBound ..< visible.upperBound {
            guard let view = table.view(atColumn: 0, row: row, makeIfNecessary: false) as? SidebarRowView else {
                continue
            }
            view.configure(content(for: row))
            view.isSelected = row == table.selectedRow
            view.isHovered = row == hoveredRow
        }
        movePills()
    }

    /// Parks both row fills, or brings them back. §6.6's lift carries §3.4's
    /// selected pill itself, so while one is up the list's own would be a
    /// second highlight lying in the row's old place.
    func setPillsHidden(_ hidden: Bool) {
        guard hidden else {
            movePills()
            return
        }
        for pill in [selectionPill, hoverPill] { fade(pill, to: 0) }
    }

    /// Keeps the two shared pills behind the row views AppKit keeps adding.
    func sendPillsToBack() {
        for pill in [selectionPill, hoverPill] where pill.superview === table {
            table.addSubview(pill, positioned: .below, relativeTo: nil)
        }
    }

    func content(for row: Int) -> SidebarRowContent {
        switch list[row] {
        case .addTab:
            return SidebarRowContent(title: "Add Tab", symbolName: "plus")
        case .separator, .none:
            return SidebarRowContent()
        case .tab:
            guard let tab = list.tab(at: row) else { return SidebarRowContent() }
            return tabContent(tab)
        }
    }

    private func tabContent(_ tab: Tab) -> SidebarRowContent {
        let state = liveStates[tab.id]
        let title = state?.title.isEmpty == false ? (state?.title ?? "") : tab.title
        let muted = mutedTabIDs.contains(tab.id)
        let trailing: SidebarRowContent.Trailing
        if hoveredRow.flatMap({ list[$0] }) == .tab(tab.id) {
            trailing = .close
        } else if state?.isPlayingAudio == true || muted {
            trailing = .audio(muted: muted)
        } else {
            trailing = .none
        }
        return SidebarRowContent(
            title: title.isEmpty ? URLPillView.domain(of: tab.url) : title,
            favicon: SidebarIcons.favicon(for: tab),
            hasUnread: tab.hasUnread,
            isLoading: state?.isLoading ?? false,
            trailing: trailing
        )
    }

    // MARK: - Selection and hover

    private func setActive(_ id: UUID?) {
        activeTabID = id
        isApplyingSelection = true
        if let id, let row = list.row(of: id) {
            table.selectRowIndexes([row], byExtendingSelection: false)
        } else {
            table.deselectAll(nil)
        }
        isApplyingSelection = false
        refreshVisibleRows()
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

    /// The two shared pills follow the rows instead of each row owning a fill.
    func movePills() {
        selectionPill.isFocused = table.window?.firstResponder === table
        let selected = table.selectedRow >= 0 ? table.selectedRow : nil
        place(selectionPill, at: selected, spec: Tokens.Motion.selectedRowMove)
        let hovered = hoveredRow.flatMap { list.isSelectable($0) && $0 != selected ? $0 : nil }
        place(hoverPill, at: hovered, spec: Tokens.Motion.rowHover)
    }

    private func place(_ pill: NSView, at row: Int?, spec: MotionSpec) {
        guard let row, row < table.numberOfRows else {
            fade(pill, to: 0)
            return
        }
        // `rowHeight` is pitch; `rowPillHeight` is paint. Insetting vertically
        // is what stops two adjacent selected pills fusing into one slab.
        let target = table.rect(ofRow: row)
            .insetBy(dx: Tokens.Metric.rowInset, dy: Tokens.Metric.rowPillInset)
        let wasParked = pill.alphaValue == 0 || pill.frame == .zero
        if !wasParked, let spring = spec.springAnimation(keyPath: "position") {
            let from = pill.layer?.position ?? .zero
            pill.frame = target
            spring.fromValue = NSValue(point: from)
            spring.toValue = NSValue(point: pill.layer?.position ?? .zero)
            pill.layer?.add(spring, forKey: "position")
        } else {
            pill.frame = target
        }
        fade(pill, to: 1)
    }

    private func fade(_ pill: NSView, to alpha: CGFloat) {
        guard pill.alphaValue != alpha else { return }
        Tokens.Motion.animate(Tokens.Motion.rowHover) { context in
            context.allowsImplicitAnimation = true
            pill.animator().alphaValue = alpha
        }
    }

    // MARK: - Commands

    /// Only tabs have a menu: `+ Add Tab` and the rule are commands, and a
    /// context menu on a command is a menu with nothing in it.
    private func contextMenu(forRow row: Int) -> NSMenu? {
        guard case let .tab(id)? = list[row] else { return nil }
        let menu = NSMenu()
        menu.addItem(SidebarMenu.item(title: "Pin Tab") { [weak self] in self?.onPinTab?(id) })
        menu.addItem(.separator())
        menu.addItem(SidebarMenu.item(title: "Close Tab") { [weak self] in self?.onCloseTab?(id) })
        return menu
    }

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
