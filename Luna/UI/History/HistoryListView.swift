//
//  HistoryListView.swift
//  Luna
//
//  §6.4's rows, highlighted the way §9.1's are: one glass pill that moves,
//  not a fill per row. It is the same list of the same things as the Command
//  Bar, so it highlights the same way: `.control` glass at `rowCornerRadius`,
//  inset `rowInset`, sliding on §6's `selectedRowMove`. A rebuilt list places
//  the pill without animating.
//
//  An `NSTableView`, not a stack of built rows. A stack of 162 rows, each six
//  subviews and seven constraints in one Auto Layout engine, took 1163 ms to
//  build before the pop-out could animate in, and 35 s at four figures. The
//  table lays out only the dozen visible rows, however long the list.
//
//  The panel's filter field owns the keystrokes and hands ↓/↑/↩ and the delete
//  keys down here. Day headers and marking several rows (§11.3) are in
//  `HistoryListView+Marks.swift`.
//

import AppKit

@MainActor
final class HistoryListView: NSView {

    /// A row was chosen — by click, or by `↩` on the highlighted one.
    var onActivate: ((HistoryEntry) -> Void)?
    /// An entry's icon, asked for as each row is filled.
    var iconProvider: ((HistoryEntry) -> NSImage?)?
    /// These pages are to be deleted: the marked ones, or the one a key or a
    /// menu was aimed at.
    var onDelete: (([HistoryEntry]) -> Void)?
    /// The right-click menu for `pages` — the marked ones when the row clicked
    /// is among them, the row alone otherwise.
    var menuProvider: ((_ pages: [HistoryEntry]) -> NSMenu?)?

    private(set) var entries: [HistoryEntry] = []
    /// The highlighted page: where the pointer or ↓/↑ last stood, and what ↩
    /// opens.
    private(set) var selectedID: UUID?
    /// The pages marked with ⌘-click, ⇧-click or ⌘A, which the delete keys and
    /// the menu act on together.
    var markedIDs: Set<UUID> = []
    /// Where a ⇧-click range starts: the last row ⌘-clicked or ⇧-clicked.
    var anchorID: UUID?

    /// What the table shows, headers and pages in order.
    enum Item {
        case day(String)
        case page(HistoryEntry)
    }
    private(set) var items: [Item] = []
    /// Each page's row in `items`.
    var rowOfEntry: [UUID: Int] = [:]

    let table = NSTableView()
    private let scroll = NSScrollView()
    /// The highlight. Parked while rows are marked: each marked row then has a
    /// pill of its own, and `hover` stands where the pointer is.
    let selection = RowPillView(role: .selected)
    let hover = RowPillView(role: .hover)
    /// The marked rows' pills, by page.
    var markPills: [UUID: RowPillView] = [:]
    private static let rowIdentifier = NSUserInterfaceItemIdentifier("history.row")
    private static let dayIdentifier = NSUserInterfaceItemIdentifier("history.day")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        buildTable()
        buildScroll()
        addSubview(scroll)
        setAccessibilityRole(.list)
        setAccessibilityLabel(String(localized: "History"))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    var isEmpty: Bool { entries.isEmpty }

    override func layout() {
        super.layout()
        scroll.frame = bounds
        // The pill is placed from here as well as from the selection. The list
        // is filled by `panelDidAppear`, before the pop-out has been laid out,
        // so the first placement measures a table with no width yet and the
        // pill came up the width of a favicon until the pointer moved it.
        scroll.layoutSubtreeIfNeeded()
        movePills(animated: false)
    }

    // MARK: - Content

    func setEntries(_ new: [HistoryEntry]) {
        let changed = new.map(\.id) != entries.map(\.id)
        entries = new
        selectedID = new.first?.id
        guard changed else { return applySelection(animated: true) }
        items = Self.items(grouping: new)
        rowOfEntry = [:]
        for (row, item) in items.enumerated() {
            if case .page(let entry) = item { rowOfEntry[entry.id] = row }
        }
        markedIDs.formIntersection(rowOfEntry.keys)
        if let anchor = anchorID, rowOfEntry[anchor] == nil { anchorID = nil }
        table.reloadData()
        // A list that has just been replaced has no continuity for a slide to
        // describe, and the rows the pill would be sliding between are not the
        // same rows.
        applySelection(animated: false)
    }

    /// A header wherever the day changes. The entries come newest first, so
    /// one day's pages are already together.
    private static func items(grouping entries: [HistoryEntry]) -> [Item] {
        var items: [Item] = []
        var day: String?
        for entry in entries {
            if !entry.day.isEmpty, entry.day != day { items.append(.day(entry.day)) }
            day = entry.day
            items.append(.page(entry))
        }
        return items
    }

    // MARK: - Selection

    func select(_ id: UUID?, animated: Bool) {
        guard id != selectedID else { return }
        selectedID = id
        applySelection(animated: animated)
    }

    /// `↓` / `↑` from the filter field. Clamped rather than wrapped: a list you
    /// can fall off the end of is a list you have to count.
    func move(by offset: Int) {
        guard !entries.isEmpty else { return }
        let current = entries.firstIndex { $0.id == selectedID } ?? 0
        let next = min(max(current + offset, 0), entries.count - 1)
        select(entries[next].id, animated: true)
        if let row = rowOfEntry[entries[next].id] {
            // The first page of a day brings its header into view with it.
            let above = row > 0 && { if case .day = items[row - 1] { true } else { false } }()
            table.scrollRowToVisible(above ? row - 1 : row)
            table.scrollRowToVisible(row)
        }
    }

    /// `↩`.
    func activateSelection() {
        guard let entry = entries.first(where: { $0.id == selectedID }) else { return }
        onActivate?(entry)
    }

    func applySelection(animated: Bool) {
        for row in 0..<table.numberOfRows {
            guard let view = table.view(atColumn: 0, row: row, makeIfNecessary: false) as? HistoryRowView,
                  let id = view.entry?.id
            else { continue }
            view.isSelected = id == selectedID || markedIDs.contains(id)
        }
        movePills(animated: animated)
    }

    /// The fill's box for a page's row, or nil when it has none on screen.
    func pillBox(of id: UUID?) -> NSRect? {
        guard let id, let row = rowOfEntry[id], row < table.numberOfRows else { return nil }
        return table.rect(ofRow: row).insetBy(dx: Tokens.Metric.rowInset, dy: Tokens.Metric.rowPillInset)
    }

    // MARK: - Build

    private func buildTable() {
        let column = NSTableColumn(identifier: Self.rowIdentifier)
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.headerView = nil
        table.style = .plain
        table.backgroundColor = .clear
        table.usesAutomaticRowHeights = false
        table.rowHeight = Tokens.Metric.rowHeight
        table.intercellSpacing = .zero
        table.gridStyleMask = []
        // The highlight is the glass pill below, not AppKit's blue plate.
        table.selectionHighlightStyle = .none
        table.allowsEmptySelection = true
        table.dataSource = self
        table.delegate = self
        for pill in [selection, hover] {
            pill.fade(to: 0, animated: false)
            table.addSubview(pill, positioned: .below, relativeTo: nil)
        }
    }

    private func buildScroll() {
        scroll.documentView = table
        scroll.drawsBackground = false
        scroll.contentView.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.horizontalScrollElasticity = .none
        scroll.automaticallyAdjustsContentInsets = false
        // Overlay, so the scroller does not take width off the rows. A legacy
        // scroller is laid out beside the document, which would make the rows a
        // scroller narrower than the list they are measured against.
        scroll.scrollerStyle = .overlay
        // And a row's height of clear space at each end, so the first and last
        // rows are whole rather than sliced by the header above them and the
        // panel's own edge below.
        scroll.contentInsets = NSEdgeInsets(
            top: PopoutMetrics.padding,
            left: 0,
            bottom: PopoutMetrics.padding,
            right: 0
        )
    }
}

// MARK: - Rows

extension HistoryListView: NSTableViewDataSource, NSTableViewDelegate {

    func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        guard items.indices.contains(row), case .day = items[row] else { return Tokens.Metric.rowHeight }
        return Tokens.Metric.historyDayHeaderHeight
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        defer {
            // AppKit adds each new row view on top of everything already in
            // the table, the pills included, so they are put back underneath
            // as the rows that would cover them arrive.
            for pill in [selection, hover] + Array(markPills.values) {
                table.addSubview(pill, positioned: .below, relativeTo: nil)
            }
        }
        switch items[row] {
        case .day(let day):
            let view = table.makeView(withIdentifier: Self.dayIdentifier, owner: self) as? HistoryDayHeaderView
                ?? makeDayHeader()
            view.configure(day)
            return view
        case .page(let entry):
            let view = table.makeView(withIdentifier: Self.rowIdentifier, owner: self) as? HistoryRowView
                ?? makeRow()
            view.configure(entry, icon: iconProvider?(entry))
            view.isSelected = entry.id == selectedID || markedIDs.contains(entry.id)
            return view
        }
    }

    private func makeDayHeader() -> HistoryDayHeaderView {
        let view = HistoryDayHeaderView()
        view.identifier = Self.dayIdentifier
        return view
    }

    private func makeRow() -> HistoryRowView {
        let view = HistoryRowView()
        view.identifier = Self.rowIdentifier
        view.onClick = { [weak self, weak view] modifiers in
            guard let entry = view?.entry else { return }
            self?.click(entry, modifiers: modifiers)
        }
        view.onHover = { [weak self, weak view] in
            guard let entry = view?.entry else { return }
            self?.select(entry.id, animated: true)
        }
        view.onMenu = { [weak self, weak view] in
            guard let self, let entry = view?.entry else { return nil }
            return menuProvider?(pages(aimedAt: entry))
        }
        return view
    }
}
