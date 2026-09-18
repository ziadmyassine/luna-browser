//
//  DownloadsPanelRow.swift
//  Luna
//
//  §5's downloads pop-out, row by row — and the list that holds them.
//
//  The shape is §6.4's history list, deliberately: one glass pill that moves
//  rather than a fill per row, `rowHeight` rows, a 16 pt icon, a title and a
//  quieter line under it. Two surfaces that both answer "what have I already
//  got" should not look like two designs.
//
//  **Middle truncation is required, not stylistic** (§5). A statement called
//  `97103328759-2026-01-01-2026-08-31.pdf` has to keep both ends: head
//  truncation destroys the account number, tail truncation destroys the
//  extension, and either leaves the user unable to tell which file landed.
//
//  Each row carries one trailing glyph and it is the *useful* one for that
//  row's state — Show in Finder for a file that is on disk, Retry for one that
//  is not. A row that offered both would be offering one that does nothing.
//

import AppKit

@MainActor
final class DownloadsPanelListView: NSView {

    /// The row was chosen — click, or `↩` on the highlighted one.
    var onOpen: ((DownloadItem) -> Void)?
    var onReveal: ((DownloadItem) -> Void)?
    var onRetry: ((DownloadItem) -> Void)?

    private(set) var items: [DownloadItem] = []
    private var selectedID: UUID?

    private let rows = NSStackView()
    private let selection = Glass.backing(.control, cornerRadius: Tokens.Metric.rowCornerRadius)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        rows.orientation = .vertical
        rows.spacing = 0
        // `.width`, not `.leading`: the stack itself is the one width every row
        // has, so the list is a straight edge rather than a ragged one.
        rows.alignment = .width
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
        setAccessibilityLabel(String(localized: "Downloads"))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    // MARK: - Content

    /// **Rows are rebuilt only when the list of downloads changes.** Progress
    /// arrives on every KVO tick, several times a second per live download, and
    /// rebuilding the stack that often would throw away the pointer's hover and
    /// restart the selection pill's slide on every frame.
    func setItems(_ new: [DownloadItem]) {
        let changed = new.map(\.id) != items.map(\.id)
        items = new
        guard changed else { return refreshRows() }
        selectedID = new.first?.id
        rebuildRows()
        needsLayout = true
        applySelection(animated: false)
    }

    private func rebuildRows() {
        for view in rows.arrangedSubviews { view.removeFromSuperview() }
        for item in items {
            let row = DownloadsPanelRowView(item: item)
            row.onClick = { [weak self] in self?.activate(item) }
            row.onAction = { [weak self] in self?.performTrailingAction(on: item) }
            row.onHover = { [weak self] in self?.select(item.id, animated: true) }
            rows.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: rows.widthAnchor).isActive = true
        }
    }

    private func refreshRows() {
        for case let row as DownloadsPanelRowView in rows.arrangedSubviews { row.refresh() }
    }

    /// Clicking the row does the obvious thing for its state: open what is on
    /// disk, retry what is not. Anything else — a download still running — is
    /// not an invitation.
    private func activate(_ item: DownloadItem) {
        if item.isOnDisk {
            onOpen?(item)
        } else if item.canRetry {
            onRetry?(item)
        }
    }

    private func performTrailingAction(on item: DownloadItem) {
        if item.isOnDisk {
            onReveal?(item)
        } else if item.canRetry {
            onRetry?(item)
        }
    }

    // MARK: - Selection

    func select(_ id: UUID?, animated: Bool) {
        guard id != selectedID else { return }
        selectedID = id
        applySelection(animated: animated)
    }

    /// `↓` / `↑` from the panel's key handling. Clamped rather than wrapped: a
    /// list you can fall off the end of is a list you have to count.
    func move(by offset: Int) {
        guard !items.isEmpty else { return }
        let current = items.firstIndex { $0.id == selectedID } ?? 0
        let next = min(max(current + offset, 0), items.count - 1)
        select(items[next].id, animated: true)
    }

    func activateSelection() {
        guard let item = items.first(where: { $0.id == selectedID }) else { return }
        activate(item)
    }

    private func applySelection(animated: Bool) {
        for case let row as DownloadsPanelRowView in rows.arrangedSubviews {
            row.isSelected = row.item.id == selectedID
        }
        moveSelectionPill(animated: animated)
    }

    override func layout() {
        super.layout()
        moveSelectionPill(animated: false)
    }

    private func moveSelectionPill(animated: Bool) {
        guard let row = rows.arrangedSubviews
            .first(where: { ($0 as? DownloadsPanelRowView)?.item.id == selectedID })
        else {
            selection.isHidden = true
            return
        }
        // One width, one inset, taken from the list itself; only `y` and the
        // height come from the row. See `HistoryListView` for what a per-row
        // width did to the panel's own rounded edge.
        let frame = convert(row.frame, from: rows)
        let target = NSRect(
            x: bounds.minX + Tokens.Metric.rowInset,
            y: frame.minY,
            width: max(bounds.width - 2 * Tokens.Metric.rowInset, 0),
            height: frame.height
        )
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
}

// MARK: - One row

@MainActor
final class DownloadsPanelRowView: NSView {

    let item: DownloadItem

    var onClick: (() -> Void)?
    /// The trailing glyph — Show in Finder, or Retry.
    var onAction: (() -> Void)?
    var onHover: (() -> Void)?

    var isSelected = false {
        didSet {
            guard isSelected != oldValue else { return }
            applyTokens()
            setAccessibilitySelected(isSelected)
        }
    }

    private let icon = NSImageView()
    private let name = NSTextField(labelWithString: "")
    private let status = NSTextField(labelWithString: "")
    private let action = RowGlyphView()

    init(item: DownloadItem) {
        self.item = item
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        icon.imageScaling = .scaleProportionallyUpOrDown
        name.lineBreakMode = .byTruncatingMiddle
        name.cell?.truncatesLastVisibleLine = true
        status.lineBreakMode = .byTruncatingTail
        action.chromed = true
        action.onActivate = { [weak self] in self?.onAction?() }

        let text = NSStackView(views: [name, status])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 0
        name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        status.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let stack = NSStackView(views: [icon, text, NSView(), action])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = Tokens.Metric.rowIconGap
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            // Two lines, so a row is taller than §3.4's single-line one.
            heightAnchor.constraint(equalToConstant: Tokens.Metric.rowHeight + Tokens.Metric.rowGap * 2),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Tokens.Metric.chromeGapWide),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Tokens.Metric.chromeGapWide),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: Tokens.Metric.essentialsIcon),
            icon.heightAnchor.constraint(equalToConstant: Tokens.Metric.essentialsIcon),
            action.widthAnchor.constraint(equalToConstant: Tokens.Metric.rowTrailingChip.width),
            action.heightAnchor.constraint(equalToConstant: Tokens.Metric.rowTrailingChip.height)
        ])

        refresh()
        // §21.2 / contract rule 4: Increase Contrast is not an appearance on
        // macOS 26.5, so every token colour is re-assigned when it flips.
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(accessibilityDisplayOptionsChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )

        setAccessibilityElement(true)
        setAccessibilityRole(.button)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    /// Re-reads the item. Called on every progress tick, so it assigns and does
    /// nothing else.
    func refresh() {
        icon.image = item.icon
        name.stringValue = item.filename
        status.stringValue = Self.status(of: item)
        // §21.1: the state is spelled out in words, not implied by a glyph.
        setAccessibilityLabel(item.accessibilityLabel)
        applyTrailingGlyph()
        applyTokens()
    }

    private func applyTrailingGlyph() {
        if item.isOnDisk {
            action.isHidden = false
            action.configure(
                symbolName: "folder",
                label: String(localized: "Show in Finder"),
                pointSize: Tokens.Metric.pillGlyphSize
            )
        } else if item.canRetry {
            action.isHidden = false
            action.configure(
                symbolName: "arrow.clockwise",
                label: String(localized: "Retry"),
                pointSize: Tokens.Metric.pillGlyphSize
            )
        } else {
            // A download still running has nothing to offer yet.
            action.isHidden = true
        }
    }

    /// The second line: what happened, in words.
    private static func status(of item: DownloadItem) -> String {
        switch item.state {
        case .finished:
            return item.destination?.deletingLastPathComponent().lastPathComponent ?? String(localized: "Finished")
        case .inProgress:
            guard let fraction = item.progress?.fractionCompleted else {
                return String(localized: "Downloading…")
            }
            return String(localized: "Downloading… \(Int(fraction * 100))%")
        case let .failed(reason):
            return reason
        case .cancelled:
            return String(localized: "Cancelled")
        }
    }

    @objc private func accessibilityDisplayOptionsChanged() {
        applyTokens()
    }

    private func applyTokens() {
        name.font = Tokens.TypeScale.sidebarRow
        status.font = Tokens.TypeScale.settingsCaption
        name.textColor = isSelected ? Tokens.Text.primary : Tokens.Text.secondary
        status.textColor = Tokens.Text.tertiary
        action.tint = isSelected ? Tokens.Text.primary : Tokens.Text.secondary
        needsDisplay = true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyTokens()
    }

    // MARK: - Hover

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where area.owner === self { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) { onHover?() }

    /// Swallowed, not ignored: the pop-out's sheet dismisses on `mouseDown`,
    /// and letting a row's press walk up there would tear the panel down before
    /// the `mouseUp` meant to choose this row arrived.
    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onClick?()
    }

    override func accessibilityPerformPress() -> Bool {
        onClick?()
        return true
    }
}
