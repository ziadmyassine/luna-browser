//
//  TabListController+Table.swift
//  Luna
//
//  The `NSTableView` half of §3.4: data source, delegate, and the table
//  subclass that carries the keyboard (§7.4, §20.2).
//
//  There is no drag and drop here at all. §6.6's reorder is a tracked
//  gesture — `SidebarTabDrag.swift` — and with the Essentials tiles moved onto
//  it as well, nothing in the sidebar is an `NSDraggingSource` or an
//  `NSDraggingDestination` any more. One gesture, one code path.
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
}

// MARK: - Delegate

extension TabListController: NSTableViewDelegate {

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        list[row] == .separator ? Tokens.Metric.separatorRowHeight : Tokens.Metric.rowHeight
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
        view.onTrailing = { [weak self, weak view] trailing in
            guard let view else { return }
            self?.trailingTapped(trailing, on: view)
        }
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

    /// §3.4: the trailing slot is the speaker until the row is hovered, at
    /// which point it is close. Whatever is drawn is what is hit — so the
    /// row reports the glyph it was actually showing rather than the list
    /// re-deriving it, which is a second chance to disagree.
    ///
    /// The row is looked up now, from the view. `viewFor` runs once and the
    /// table then moves that view between rows as tabs come and go, so a row
    /// index captured in the closure goes stale the moment a tab is inserted
    /// above it — which is how pressing close on one tab came to mute the tab
    /// underneath.
    private func trailingTapped(_ trailing: SidebarRowContent.Trailing, on view: SidebarRowView) {
        guard case let .tab(id)? = list[table.row(for: view)] else { return }
        switch trailing {
        case .close: onCloseTab?(id)
        case .audio: onToggleMute?(id)
        case .none: break
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

    /// Edge to edge, not inset like a row pill: the reference runs the rule the
    /// full width of the sidebar, which is what makes it read as the end of a
    /// section rather than as a very thin row.
    override func draw(_ dirtyRect: NSRect) {
        Tokens.Line.hairline.setFill()
        NSRect(
            x: 0,
            y: (bounds.height - Tokens.Metric.hairline) / 2,
            width: bounds.width,
            height: Tokens.Metric.hairline
        ).fill()
    }
}

/// The list's keyboard and hover surface. Everything else about the table is
/// configured from `TabListController`; this exists only for the overrides.
@MainActor
final class SidebarTableView: NSTableView {

    enum Command { case previousTab, nextTab, confirm, close }

    var onCommandKey: ((Command) -> Bool)?
    var onFocusChange: (() -> Void)?
    /// A press landed on row `n`. The list takes the whole gesture from here —
    /// see `TabListController.press(row:event:)`.
    var onRowPress: ((Int, NSEvent) -> Void)?
    /// The table re-placed its row views. §6.6's gap is drawn by offsetting
    /// those views, so it has to be put back after every pass that overwrites
    /// them — and the §3.3 grid opening a slot mid-drag resizes the scroll view,
    /// which is exactly such a pass.
    var onLayout: (() -> Void)?
    /// The row under the pointer, or nil when the pointer left the list.
    var onHover: ((Int?) -> Void)?
    /// Right-click on a row. Built on demand, and deliberately not through
    /// `NSTableView.menu`: a single menu on the table cannot know which row it
    /// was summoned from, and a menu per row view dies with the recycled view.
    var onContextMenu: ((Int) -> NSMenu?)?

    override var acceptsFirstResponder: Bool { true }

    /// The press is handed on whole, not passed to `super`.
    ///
    /// `NSTableView.mouseDown` runs its own tracking loop until the mouse comes
    /// up: it decides selection, and it decides whether the gesture was a drag.
    /// §6.6's lift needs those drags, so the loop has to be ours (see
    /// `SidebarTabDrag.swift`) and this is where it is taken over.
    ///
    /// A press below the last row is not a row at all. It is the sidebar's own
    /// plane, and the plane moves the window (§30.1) — which is what makes the
    /// whole column a drag handle rather than just its top bar.
    override func layout() {
        super.layout()
        onLayout?()
    }

    override func mouseDown(with event: NSEvent) {
        let row = row(at: convert(event.locationInWindow, from: nil))
        guard row >= 0, let onRowPress else {
            window?.performDrag(with: event)
            return
        }
        onRowPress(row, event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let row = row(at: convert(event.locationInWindow, from: nil))
        guard row >= 0 else { return super.menu(for: event) }
        return onContextMenu?(row) ?? super.menu(for: event)
    }

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
