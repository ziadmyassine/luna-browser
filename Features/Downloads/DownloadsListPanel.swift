//
//  DownloadsListPanel.swift
//  Luna
//
//  TODO.md §15.3 / §30.15 — the persistent downloads list: history, retry,
//  reveal in Finder, open, clear.
//
//  **Deliberately plain.** §30.15 says the popover is the primary surface and
//  the panel is secondary, so this is a standard AppKit utility panel with a
//  table in it — no glass, no custom chrome, no motion. It is the surface a
//  user visits when something went wrong, and the useful property then is that
//  it behaves exactly like every other Mac panel: keyboard-navigable table,
//  Space/Return to act, a real title bar to close.
//

import AppKit

@MainActor
final class DownloadsListPanel: NSWindowController {

    private let manager: DownloadManager
    private let table = NSTableView()
    private var items: [DownloadItem] = []

    /// §5's popover is 330 wide, which is too narrow for a column of full
    /// filenames; the sidebar's maximum is the widest chrome span the design
    /// system names, and ten rows is a list, not a window.
    private static var contentSize: CGSize {
        CGSize(
            width: Tokens.Metric.sidebarWidth.max,
            height: Tokens.Metric.rowHeight * 10
        )
    }

    init(manager: DownloadManager) {
        self.manager = manager
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.contentSize),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = String(localized: "Downloads")
        panel.isReleasedWhenClosed = false
        super.init(window: panel)
        panel.delegate = self
        panel.contentView = buildContent()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    // MARK: - Content

    private func buildContent() -> NSView {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("download"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = Tokens.Metric.rowHeight
        table.style = .inset
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(openSelected)
        table.setAccessibilityLabel(String(localized: "Downloads"))

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false

        // Plain push buttons: AppKit sizes them, they are in the key loop, and
        // every one of them is reachable with Tab (§21.1, §20.2).
        let buttons = NSStackView(views: [
            button(String(localized: "Open"), #selector(openSelected)),
            button(String(localized: "Show in Finder"), #selector(revealSelected)),
            button(String(localized: "Retry"), #selector(retrySelected)),
            NSView(),
            button(String(localized: "Clear"), #selector(clearCompleted))
        ])
        buttons.orientation = .horizontal
        buttons.spacing = Tokens.Metric.panelInset
        buttons.distribution = .fill

        let stack = NSStackView(views: [scroll, buttons])
        stack.orientation = .vertical
        stack.spacing = Tokens.Metric.panelInset
        stack.edgeInsets = NSEdgeInsets(
            top: Tokens.Metric.panelInset,
            left: Tokens.Metric.panelInset,
            bottom: Tokens.Metric.panelInset,
            right: Tokens.Metric.panelInset
        )
        stack.setHuggingPriority(.defaultLow, for: .vertical)
        return stack
    }

    private func button(_ title: String, _ action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        return button
    }

    // MARK: - Showing it

    func toggle() {
        if window?.isVisible == true {
            window?.performClose(nil)
        } else {
            reload()
            manager.onChange = { [weak self] in self?.reload() }
            showWindow(nil)
            window?.makeKeyAndOrderFront(nil)
        }
    }

    private func reload() {
        let selected = table.selectedRow
        items = manager.items
        table.reloadData()
        if selected >= 0, selected < items.count {
            table.selectRowIndexes(IndexSet(integer: selected), byExtendingSelection: false)
        }
    }

    private var selection: DownloadItem? {
        let row = table.selectedRow
        return row >= 0 && row < items.count ? items[row] : nil
    }

    // MARK: - Actions

    @objc private func openSelected() { selection.map(manager.open) }
    @objc private func revealSelected() { selection.map(manager.reveal) }
    @objc private func retrySelected() { selection.map(manager.retry) }
    @objc private func clearCompleted() {
        manager.clearCompleted()
        reload()
    }
}

// MARK: - Lifecycle

extension DownloadsListPanel: NSWindowDelegate {
    /// Progress KVO costs nothing while nobody is watching, which is the point
    /// of clearing the callback here rather than leaving it installed.
    func windowWillClose(_ notification: Notification) {
        manager.onChange = nil
    }
}

// MARK: - Table

extension DownloadsListPanel: NSTableViewDataSource, NSTableViewDelegate {

    func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    func tableView(_ tableView: NSTableView, viewFor column: NSTableColumn?, row: Int) -> NSView? {
        let item = items[row]
        let identifier = NSUserInterfaceItemIdentifier("DownloadRow")
        let view = tableView.makeView(withIdentifier: identifier, owner: self) as? DownloadListRowView
            ?? DownloadListRowView(identifier: identifier)
        view.show(item)
        return view
    }
}

/// `[icon 18] [filename] [state]` — the sidebar row's metrics, because it is
/// the same kind of row (§3.4).
@MainActor
private final class DownloadListRowView: NSTableCellView {

    private let icon = NSImageView()
    private let name = NSTextField(labelWithString: "")
    private let status = NSTextField(labelWithString: "")
    private var item: DownloadItem?

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        icon.imageScaling = .scaleProportionallyUpOrDown
        let stack = NSStackView(views: [icon, name, NSView(), status])
        stack.orientation = .horizontal
        stack.spacing = Tokens.Metric.panelInset
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: Tokens.Metric.faviconSize),
            icon.heightAnchor.constraint(equalToConstant: Tokens.Metric.faviconSize)
        ])
        applyTokens()
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(applyTokens),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    func show(_ item: DownloadItem) {
        self.item = item
        icon.image = item.icon
        name.stringValue = item.filename
        name.lineBreakMode = .byTruncatingMiddle
        status.stringValue = Self.status(of: item)
        setAccessibilityLabel(item.accessibilityLabel)
    }

    /// Words, not colour: §21.2's Differentiate Without Colour applies to a
    /// failed download exactly as it does to a Space.
    private static func status(of item: DownloadItem) -> String {
        switch item.state {
        case .finished: String(localized: "Done")
        case .cancelled: String(localized: "Cancelled")
        case .failed: String(localized: "Failed")
        case .inProgress:
            item.progress.map { String(localized: "\(Int($0.fractionCompleted * 100))%") }
                ?? String(localized: "Downloading")
        }
    }

    @objc private func applyTokens() {
        name.font = Tokens.TypeScale.sidebarRow
        name.textColor = Tokens.Text.primary
        status.font = Tokens.TypeScale.sectionLabel
        status.textColor = Tokens.Text.secondary
        needsDisplay = true
    }
}
