//
//  HistoryListView.swift
//  Luna
//
//  §6.4's rows, highlighted the way §9.1's are: **one glass pill that moves**,
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
//  Pointer and keyboard drive the same selection. The panel's filter field owns
//  the keystrokes — it is what has focus — and hands ↓/↑/↩ down here.
//

import AppKit

@MainActor
final class HistoryListView: NSView {

    /// A row was chosen — by click, or by `↩` on the highlighted one.
    var onActivate: ((HistoryEntry) -> Void)?
    /// An entry's icon, asked for as each row is built.
    var iconProvider: ((HistoryEntry) -> NSImage?)?

    private(set) var entries: [HistoryEntry] = []
    private(set) var selectedID: UUID?

    private let rows = NSStackView()
    private let selection = Glass.backing(.control, cornerRadius: Tokens.Metric.rowCornerRadius)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        rows.orientation = .vertical
        rows.spacing = 0
        rows.alignment = .leading
        rows.distribution = .fill
        rows.translatesAutoresizingMaskIntoConstraints = false

        selection.isHidden = true
        addSubview(selection)
        addSubview(rows)
        NSLayoutConstraint.activate([
            rows.leadingAnchor.constraint(equalTo: leadingAnchor),
            rows.trailingAnchor.constraint(equalTo: trailingAnchor),
            rows.topAnchor.constraint(equalTo: topAnchor),
            rows.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        setAccessibilityRole(.list)
        setAccessibilityLabel(String(localized: "History"))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    var isEmpty: Bool { entries.isEmpty }

    // MARK: - Content

    func setEntries(_ new: [HistoryEntry]) {
        let changed = new.map(\.id) != entries.map(\.id)
        entries = new
        selectedID = new.first?.id
        guard changed else { return applySelection(animated: true) }
        rebuildRows()
        // The new rows have no frames yet, so the pill is placed from `layout()`.
        needsLayout = true
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
        scrollSelectionIntoView()
    }

    /// `↩`.
    func activateSelection() {
        guard let entry = entries.first(where: { $0.id == selectedID }) else { return }
        onActivate?(entry)
    }

    // MARK: - Rows

    private func rebuildRows() {
        for view in rows.arrangedSubviews { view.removeFromSuperview() }
        for entry in entries {
            let row = HistoryRowView(entry: entry, icon: iconProvider?(entry))
            row.onClick = { [weak self] in self?.onActivate?(entry) }
            row.onHover = { [weak self] in self?.select(entry.id, animated: true) }
            rows.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: rows.widthAnchor).isActive = true
        }
    }

    private func applySelection(animated: Bool) {
        for case let row as HistoryRowView in rows.arrangedSubviews {
            row.isSelected = row.entry.id == selectedID
        }
        moveSelectionPill(animated: animated)
    }

    override func layout() {
        super.layout()
        moveSelectionPill(animated: false)
    }

    private func moveSelectionPill(animated: Bool) {
        guard let row = rows.arrangedSubviews.first(where: { ($0 as? HistoryRowView)?.entry.id == selectedID })
        else {
            selection.isHidden = true
            return
        }
        let target = convert(row.frame, from: rows).insetBy(dx: Tokens.Metric.rowInset, dy: 0)
        selection.isHidden = false
        guard animated, !Tokens.Motion.reduceMotion else {
            selection.frame = target
            return
        }
        Tokens.Motion.animate(Tokens.Motion.selectedRowMove) { context in
            context.allowsImplicitAnimation = true
            selection.animator().frame = target
        }
    }

    private func scrollSelectionIntoView() {
        guard let row = rows.arrangedSubviews.first(where: { ($0 as? HistoryRowView)?.entry.id == selectedID })
        else { return }
        scrollToVisible(convert(row.frame, from: rows))
    }
}
