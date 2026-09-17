//
//  TabListController+Table.swift
//  Luna
//
//  The `NSTableView` half of §3.4: data source, delegate, §6.6 drag and drop,
//  and the table subclass that carries the keyboard (§7.4, §20.2).
//
//  Modified arrows are swallowed rather than passed on — an unhandled `⌘⌥←`
//  reaching `NSResponder` is the system beep, which is the single most obvious
//  "this app is not native" tell.
//

import AppKit
import BrowserKit

// MARK: - Data source

extension TabListController: NSTableViewDataSource {

    func numberOfRows(in tableView: NSTableView) -> Int {
        list.count
    }

    /// §6.6 source: only a tab travels. `Archive` and `+ Add Tab` are commands.
    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
        guard case let .tab(id)? = list[row] else { return nil }
        return SidebarDrag.item(for: id)
    }

    func tableView(
        _ tableView: NSTableView,
        validateDrop info: any NSDraggingInfo,
        proposedRow row: Int,
        proposedDropOperation dropOperation: NSTableView.DropOperation
    ) -> NSDragOperation {
        guard SidebarDrag.tabID(in: info) != nil else { return [] }
        // Nothing may land inside the leading command group, and a row never
        // accepts a drop *onto* it — §6.6 reorders, it does not nest.
        let clamped = max(row, SidebarList.leading.count)
        if clamped != row || dropOperation != .above {
            table.setDropRow(clamped, dropOperation: .above)
        }
        return .move
    }

    func tableView(
        _ tableView: NSTableView,
        acceptDrop info: any NSDraggingInfo,
        row: Int,
        dropOperation: NSTableView.DropOperation
    ) -> Bool {
        guard let id = SidebarDrag.tabID(in: info) else { return false }
        var target = list.dropTarget(insertingAt: max(row, SidebarList.leading.count))
        // `reorderTab` takes the index the tab should end up at, so a move
        // *down* within its own section has to account for its own removal.
        if let source = list.listed.firstIndex(where: { $0.id == id }),
           list.listed[source].kind == target.kind,
           sectionIndex(of: source) < target.index {
            target.index -= 1
        }
        onMoveTab?(id, target.kind, target.index)
        return true
    }

    /// A tab's index within its own section, which is what `reorderTab` counts.
    private func sectionIndex(of listedIndex: Int) -> Int {
        let kind = list.listed[listedIndex].kind
        return list.listed[..<listedIndex].filter { $0.kind == kind }.count
    }
}

// MARK: - Delegate

extension TabListController: NSTableViewDelegate {

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        list[row] == .separator ? Tokens.Metric.rowInset : Tokens.Metric.rowHeight
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if list[row] == .separator {
            return tableView.makeView(withIdentifier: SeparatorRowView.reuseIdentifier, owner: self)
                ?? SeparatorRowView()
        }
        let view = tableView.makeView(withIdentifier: SidebarRowView.reuseIdentifier, owner: self)
            as? SidebarRowView ?? SidebarRowView()
        view.configure(content(for: row))
        view.isSelected = row == table.selectedRow
        view.isHovered = row == hoveredRow
        view.onTrailing = { [weak self] in self?.trailingTapped(at: row) }
        return view
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        list.isSelectable(row)
    }

    /// §7.4's type-ahead, for free.
    func tableView(_ tableView: NSTableView, typeSelectStringFor tableColumn: NSTableColumn?, row: Int) -> String? {
        content(for: row).title
    }

    /// Keeps the two shared pills behind the rows AppKit keeps adding.
    func tableView(_ tableView: NSTableView, didAdd rowView: NSTableRowView, forRow row: Int) {
        sendPillsToBack()
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        movePills()
        guard !isApplyingSelection, case let .tab(id)? = list[table.selectedRow] else { return }
        onActivateTab?(id)
    }

    private func trailingTapped(at row: Int) {
        guard case let .tab(id)? = list[row] else { return }
        // §3.4: the trailing slot is the speaker until the row is hovered, at
        // which point it is close/archive. Whatever is drawn is what is hit.
        if row == hoveredRow {
            onCloseTab?(id)
        } else {
            onToggleMute?(id)
        }
    }
}

/// The §3.4 rule between the command rows and the tabs. A row rather than a
/// header so the list stays one flat, reusable table.
@MainActor
final class SeparatorRowView: NSView {

    static let reuseIdentifier = NSUserInterfaceItemIdentifier("dk.novapps.luna.sidebar.separator")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        identifier = Self.reuseIdentifier
        wantsLayer = true
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    override var wantsUpdateLayer: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        Tokens.Line.hairline.setFill()
        let rule = NSRect(
            x: Tokens.Metric.rowInset,
            y: (bounds.height - Tokens.Metric.hairline) / 2,
            width: bounds.width - 2 * Tokens.Metric.rowInset,
            height: Tokens.Metric.hairline
        )
        rule.fill()
    }
}

/// The list's keyboard and hover surface. Everything else about the table is
/// configured from `TabListController`; this exists only for the overrides.
@MainActor
final class SidebarTableView: NSTableView {

    enum Command { case previousTab, nextTab, confirm, close }

    var onCommandKey: ((Command) -> Bool)?
    var onFocusChange: (() -> Void)?
    /// The row under the pointer, or nil when the pointer left the list.
    var onHover: ((Int?) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        defer { onFocusChange?() }
        return super.becomeFirstResponder()
    }

    override func resignFirstResponder() -> Bool {
        defer { onFocusChange?() }
        return super.resignFirstResponder()
    }

    override func keyDown(with event: NSEvent) {
        guard let command = Self.command(for: event), onCommandKey?(command) == true else {
            super.keyDown(with: event)
            return
        }
        // Handled: deliberately not forwarded, or AppKit beeps (§20.2).
    }

    private static func command(for event: NSEvent) -> Command? {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        switch event.specialKey {
        case .leftArrow where modifiers == [.command, .option]: return .previousTab
        case .rightArrow where modifiers == [.command, .option]: return .nextTab
        case .carriageReturn, .enter: return .confirm
        case .delete, .backspace, .deleteForward: return .close
        default: return nil
        }
    }

    // MARK: - Hover

    /// One tracking area for the whole list rather than one per row: a row's
    /// area would have to be rebuilt on every scroll, which is exactly the
    /// per-frame work §19.1 cannot afford.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where area.owner === self { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let row = self.row(at: point)
        onHover?(row < 0 ? nil : row)
    }

    override func mouseExited(with event: NSEvent) {
        onHover?(nil)
    }
}
