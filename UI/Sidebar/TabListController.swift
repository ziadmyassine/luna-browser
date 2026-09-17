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
    var onOpenArchive: (() -> Void)?
    var onAddTab: (() -> Void)?
    /// §6.6: a row was dropped into a section at an index.
    var onMoveTab: ((UUID, TabKind, Int) -> Void)?

    private(set) var list = SidebarList()
    /// Live per-tab state, pushed in by `BrowserSession.onTabStateChange`.
    var liveStates: [UUID: TabState] = [:]
    /// Muted tabs. Local because neither `BrowserSession` nor `TabController`
    /// exposes a mute — see the milestone report.
    var mutedTabIDs: Set<UUID> = []

    let table = SidebarTableView()
    private let selectionPill = SelectionPillView()
    private let hoverPill = Glass.backing(.control, cornerRadius: Tokens.Metric.rowCornerRadius)
    private(set) var hoveredRow: Int?
    private var activeTabID: UUID?
    var isApplyingSelection = false

    override init() {
        super.init()
        buildTable()
        buildScrollView()
        table.registerForDraggedTypes([SidebarDrag.tabType])
        table.setDraggingSourceOperationMask(.move, forLocal: true)
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
        table.target = self
        table.action = #selector(rowClicked)
        table.onCommandKey = { [weak self] command in self?.handle(command) ?? false }
        table.onFocusChange = { [weak self] in self?.movePills() }
        table.onHover = { [weak self] row in self?.setHovered(row) }

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

    /// Keeps the two shared pills behind the row views AppKit keeps adding.
    func sendPillsToBack() {
        for pill in [selectionPill, hoverPill] where pill.superview === table {
            table.addSubview(pill, positioned: .below, relativeTo: nil)
        }
    }

    func content(for row: Int) -> SidebarRowContent {
        switch list[row] {
        case .archive:
            return SidebarRowContent(title: "Archive", symbolName: "folder", tintsSymbolWithAccent: true)
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
        let target = table.rect(ofRow: row).insetBy(dx: Tokens.Metric.rowInset, dy: 0)
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

    @objc private func rowClicked() {
        switch list[table.clickedRow] {
        case .archive: onOpenArchive?()
        case .addTab: onAddTab?()
        default: break // Tabs activate through the selection change.
        }
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
            case .archive: onOpenArchive?()
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
        let visible = table.rows(in: table.visibleRect)
        for row in visible.lowerBound ..< visible.upperBound {
            (table.view(atColumn: 0, row: row, makeIfNecessary: false) as? SidebarRowView)?
                .accessibilityDisplayOptionsChanged()
        }
    }
}

/// The §3.4 selected-row pill: clear glass with a **visible hairline border**,
/// promoted to the accent colour when the list has keyboard focus (§20.2).
@MainActor
final class SelectionPillView: NSView {

    var isFocused = false { didSet { needsDisplay = true } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        Glass.apply(.control, to: self, cornerRadius: Tokens.Metric.rowCornerRadius)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        guard let layer else { return }
        layer.cornerRadius = Tokens.Metric.rowCornerRadius
        layer.borderWidth = Tokens.Metric.hairline
        layer.borderColor = (isFocused ? Tokens.Accent.tint : Tokens.Line.border).cgColor
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
