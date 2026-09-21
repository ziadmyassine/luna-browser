//
//  HistoryListView.swift
//  Luna
//
//  §6.4's rows, highlighted the way §9.1's are: one glass pill that moves,
//  not a fill per row.
//
//  This is `CommandBarResultsView`'s behaviour, deliberately — the two lists are
//  the same list of the same things over the same page, and a history panel that
//  highlighted differently from the Command Bar would be two designs in one app.
//  The pill is `.control` glass at `rowCornerRadius`, inset `rowInset` from each
//  edge, and it slides on §6's `selectedRowMove`; a rebuilt list places it
//  without animating, because a list that just changed has no continuity for a
//  slide to describe.
//
//  **It is an `NSTableView`, and it used to be an `NSStackView` with a row in
//  it per archived tab.** The archive is the one list in Luna with no ceiling:
//  §6.3 keeps a closed tab for thirty days, which is four figures of rows for
//  an ordinary week. Every one of them was a built view — six subviews, three
//  `NSTextField`s and seven constraints each — inside one stack that tied all
//  of them into a single Auto Layout engine, and all of it was constructed
//  before `PopoutController` let the pop-out animate in. Measured at 1163 ms
//  for the 162-row archive this machine actually had, and 35 s for the thirty
//  days §6.3 has already promised: not a slow list, a frozen app, and getting
//  worse than linearly. `NSTableView` recycles row views and lays out only
//  what is visible, so the cost is the dozen rows the panel is tall and does
//  not depend on the archive at all — the same reasoning `TabListController`'s
//  header gives, for the same measurement.
//
//  Pointer and keyboard drive the same selection. The panel's filter field owns
//  the keystrokes — it is what has focus — and hands ↓/↑/↩ down here.
//

import AppKit

@MainActor
final class HistoryListView: NSView {

    /// A row was chosen — by click, or by `↩` on the highlighted one.
    var onActivate: ((HistoryEntry) -> Void)?
    /// An entry's icon, asked for as each row is filled.
    var iconProvider: ((HistoryEntry) -> NSImage?)?

    private(set) var entries: [HistoryEntry] = []
    private(set) var selectedID: UUID?

    private let scroll = NSScrollView()
    private let table = NSTableView()
    private let selection = RowPillView(role: .selected)
    private static let rowIdentifier = NSUserInterfaceItemIdentifier("history.row")

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
        // **The pill is placed from here as well as from the selection.** The
        // list is filled by `panelDidAppear`, which runs before the pop-out has
        // been laid out — so the first placement measures a table that has not
        // been given its width yet, and the pill came up the width of a favicon
        // and stayed there until the pointer moved it. The old stack-backed list
        // placed it from `layout` for exactly this reason.
        scroll.layoutSubtreeIfNeeded()
        movePill(animated: false)
    }

    // MARK: - Content

    func setEntries(_ new: [HistoryEntry]) {
        let changed = new.map(\.id) != entries.map(\.id)
        entries = new
        selectedID = new.first?.id
        guard changed else { return applySelection(animated: true) }
        table.reloadData()
        // A list that has just been replaced has no continuity for a slide to
        // describe, and the rows the pill would be sliding between are not the
        // same rows.
        applySelection(animated: false)
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
        table.scrollRowToVisible(next)
    }

    /// `↩`.
    func activateSelection() {
        guard let entry = entries.first(where: { $0.id == selectedID }) else { return }
        onActivate?(entry)
    }

    private func applySelection(animated: Bool) {
        for row in 0..<table.numberOfRows {
            guard let view = table.view(atColumn: 0, row: row, makeIfNecessary: false) as? HistoryRowView
            else { continue }
            view.isSelected = view.entry?.id == selectedID
        }
        movePill(animated: animated)
    }

    /// One pill for the whole list, standing behind the rows inside the table's
    /// own document view — so it scrolls with the rows for free, and a scroll
    /// costs it nothing.
    private func movePill(animated: Bool) {
        guard let index = entries.firstIndex(where: { $0.id == selectedID }), index < table.numberOfRows
        else {
            selection.fade(to: 0, animated: animated)
            return
        }
        selection.move(
            to: table.rect(ofRow: index).insetBy(dx: Tokens.Metric.rowInset, dy: Tokens.Metric.rowPillInset),
            spec: animated ? Tokens.Motion.selectedRowMove : nil
        )
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
        selection.fade(to: 0, animated: false)
        table.addSubview(selection, positioned: .below, relativeTo: nil)
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

    func numberOfRows(in tableView: NSTableView) -> Int { entries.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let view = table.makeView(withIdentifier: Self.rowIdentifier, owner: self) as? HistoryRowView
            ?? makeRow()
        let entry = entries[row]
        view.configure(entry, icon: iconProvider?(entry))
        view.isSelected = entry.id == selectedID
        // AppKit adds each new row view on top of everything already in the
        // table, the pill included, so the pill is put back underneath as the
        // rows that would cover it arrive.
        table.addSubview(selection, positioned: .below, relativeTo: nil)
        return view
    }

    private func makeRow() -> HistoryRowView {
        let view = HistoryRowView()
        view.identifier = Self.rowIdentifier
        view.onClick = { [weak self, weak view] in
            guard let entry = view?.entry else { return }
            self?.onActivate?(entry)
        }
        view.onHover = { [weak self, weak view] in
            guard let entry = view?.entry else { return }
            self?.select(entry.id, animated: true)
        }
        return view
    }
}
