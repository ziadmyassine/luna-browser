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
    /// §3.4a's menu, bound to one tab — `BrowserSession.tabMenuActions(for:)`. Nil leaves
    /// the rows with no context menu rather than a shorter one: a second, smaller answer
    /// to the same right-click is exactly what §3.4a exists to avoid.
    var menuActions: ((UUID) -> TabMenu.Actions?)?

    private(set) var list = SidebarList()
    /// Live per-tab state, pushed in by `BrowserSession.onTabStateChange`.
    var liveStates: [UUID: TabState] = [:]
    /// Muted tabs (§3.4a), mirrored from `BrowserSession.mutedTabIDs` so a row can draw
    /// its speaker without asking. The session is the truth — it is what re-asserts the
    /// mute on a tab waking from hibernation — and `SidebarViewController.refresh()` is
    /// what keeps the two in step.
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

    /// **No scroller at all**, which `.overlay` is not: overlay draws *over* the
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
            // **"New Tab", and it opens §9.1 rather than an empty page.** The
            // row used to be `+ Add Tab` and used to make a blank tab, which is
            // the one tab nobody wants: the next thing you do with it is reach
            // for the address bar. It now asks the question the blank tab was
            // standing in for.
            return SidebarRowContent(title: "New Tab", symbolName: "plus")
        case .separator, .none:
            return SidebarRowContent()
        case .tab:
            guard let tab = list.tab(at: row) else { return SidebarRowContent() }
            return tabContent(tab)
        }
    }

    private func tabContent(_ tab: Tab) -> SidebarRowContent {
        let state = liveStates[tab.id]
        // §3.4a: a name the user typed outranks both the live title and the stored one.
        // The live title is the page's most current answer to a question the user has
        // already overruled.
        let pageTitle = state?.title.isEmpty == false ? (state?.title ?? "") : tab.title
        let title = tab.customTitle ?? pageTitle
        // **Where the tab is now, not where the snapshot left it.** `tab` is the
        // copy taken at the last `notifyChange()`, and an in-tab navigation
        // raises none — it writes the tab and publishes a `TabState`. Reading
        // the host off the snapshot is what kept the row wearing the icon of the
        // site it had already left.
        let url = state?.url ?? tab.url
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
            title: title.isEmpty ? URLPillView.domain(of: url) : title,
            // §3.4a: a chosen symbol replaces the favicon, so the row draws its symbol
            // slot instead — which is the path `+ Add Tab` has always taken.
            symbolName: tab.customSymbolName ?? SidebarRowContent.siteFallbackSymbol,
            favicon: tab.customSymbolName == nil ? SidebarIcons.favicon(for: url) : nil,
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
    /// `animated: false` where the move is not the pill's own — a spring
    /// chasing a live resize drag arrives after the row it belongs to.
    func movePills(animated: Bool = true) {
        selectionPill.isFocused = table.window?.firstResponder === table
        let selected = table.selectedRow >= 0 ? table.selectedRow : nil
        place(selectionPill, at: selected, spec: animated ? Tokens.Motion.selectedRowMove : nil)
        let hovered = hoveredRow.flatMap { list.isSelectable($0) && $0 != selected ? $0 : nil }
        place(hoverPill, at: hovered, spec: animated ? Tokens.Motion.rowHover : nil)
    }

    private func place(_ pill: NSView, at row: Int?, spec: MotionSpec?) {
        guard let row, row < table.numberOfRows else {
            fade(pill, to: 0)
            return
        }
        // `rowHeight` is pitch; `rowPillHeight` is paint. Insetting vertically
        // is what stops two adjacent selected pills fusing into one slab.
        let target = table.rect(ofRow: row)
            .insetBy(dx: Tokens.Metric.rowInset, dy: Tokens.Metric.rowPillInset)
        let wasParked = pill.alphaValue == 0 || pill.frame == .zero
        if !wasParked, let spring = spec?.springAnimation(keyPath: "position") {
            let from = pill.layer?.position ?? .zero
            pill.frame = target
            spring.fromValue = NSValue(point: from)
            spring.toValue = NSValue(point: pill.layer?.position ?? .zero)
            pill.layer?.add(spring, forKey: "position")
        } else {
            // Layer-backed frames animate themselves; `SidebarRowView.layout`
            // takes the same precaution for the same reason.
            Tokens.Motion.immediately {
                pill.layer?.removeAnimation(forKey: "position")
                pill.frame = target
            }
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
