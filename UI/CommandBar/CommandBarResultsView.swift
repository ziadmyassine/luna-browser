//
//  CommandBarResultsView.swift
//  Luna
//
//  §9.2's result list. A plain stack of rows, not an `NSTableView`: the list is
//  capped at `CommandBarMetrics.visibleRows` so it never scrolls, which means
//  view reuse would buy nothing and cost a data source, a delegate and a row
//  identity scheme that §9.7 would then have to keep honest.
//
//  Selection is carried by `CommandBarResult.id` — a normalised URL — and never
//  by an index. §9.7: "results must never reorder under the user's cursor while
//  they are moving through them", and an index cannot survive a merge that
//  inserts a row above it. The controller enforces the no-reorder rule; this view
//  makes it observable, by putting the highlight back on the same *result*.
//
//  UI-SPEC §3.4 supplies the look: a filled translucent pill at `rowCornerRadius`
//  inset `rowInset` from each edge, with a visible hairline border and no
//  background at all on the unselected rows. One pill that moves, rather than a
//  fill per row — it is cheaper, and it is what §6's `selectedRowMove` describes.
//

import AppKit
import BrowserKit

@MainActor
final class CommandBarResultsView: NSView {

    /// Called when a row is clicked. Keyboard commits go through the input field.
    var onActivate: ((CommandBarResult) -> Void)?

    private(set) var results: [CommandBarResult] = []
    private(set) var selectedID: String?

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
        setAccessibilityLabel("Results")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    var selectedResult: CommandBarResult? {
        results.first { $0.id == selectedID }
    }

    /// Replaces the list. `keepingSelection` is the controller's promise from
    /// §9.7 — when the user has moved the highlight, the row under it stays put.
    func setResults(_ new: [CommandBarResult], selecting id: String?) {
        let contentChanged = new.map(\.id) != results.map(\.id)
        results = new
        selectedID = id ?? new.first?.id

        if contentChanged {
            rebuildRows()
            // The new rows have no frames yet, so the pill is placed from
            // `layout()` instead — and unanimated, because a rebuilt list has no
            // continuity for a slide to describe.
            needsLayout = true
        } else {
            // Only the highlight moved: frames are valid and §6's
            // `selectedRowMove` is exactly what this is.
            moveSelectionPill(animated: true)
        }
        for case let row as CommandBarRowView in rows.arrangedSubviews {
            row.isSelected = row.result.id == selectedID
        }
    }

    override func layout() {
        super.layout()
        moveSelectionPill(animated: false)
    }

    func select(id: String?) {
        setResults(results, selecting: id)
    }

    // MARK: - Rows

    private func rebuildRows() {
        for view in rows.arrangedSubviews { view.removeFromSuperview() }
        for result in results {
            let row = CommandBarRowView(result: result)
            row.onClick = { [weak self] in self?.onActivate?(result) }
            rows.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: rows.widthAnchor).isActive = true
        }
    }

    private func moveSelectionPill(animated: Bool) {
        guard let row = rows.arrangedSubviews.first(where: { ($0 as? CommandBarRowView)?.result.id == selectedID })
        else {
            selection.isHidden = true
            return
        }
        let target = convert(row.frame, from: rows).insetBy(dx: Tokens.Metric.rowInset, dy: 0)
        selection.isHidden = false
        guard animated else {
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

/// `[favicon 18] [title 15 pt] [subtitle] [Space badge]` in a 40 pt row (§3.4).
@MainActor
private final class CommandBarRowView: NSView {

    let result: CommandBarResult
    var onClick: (() -> Void)?

    var isSelected = false {
        didSet {
            guard isSelected != oldValue else { return }
            applyTokens()
            setAccessibilitySelected(isSelected)
        }
    }

    private let icon = NSImageView()
    private let title = NSTextField(labelWithString: "")
    private let subtitle = NSTextField(labelWithString: "")
    private let badgeDot = NSView()
    private let badgeName = NSTextField(labelWithString: "")

    init(result: CommandBarResult) {
        self.result = result
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        build()
        applyTokens()

        // §21.2 / contract rule 4: Increase Contrast is not an appearance on macOS
        // 26.5, so every token colour assigned here has to be assigned again when
        // the setting flips. A row that skips this ignores the setting for its
        // whole life, and these rows are almost entirely text.
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(accessibilityDisplayOptionsChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )

        setAccessibilityRole(.row)
        setAccessibilityLabel(accessibilityText)
        setAccessibilityElement(true)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    @objc private func accessibilityDisplayOptionsChanged() {
        applyTokens()
        needsDisplay = true
    }

    private func build() {
        icon.image = NSImage(systemSymbolName: result.symbolName, accessibilityDescription: nil)
        icon.imageScaling = .scaleProportionallyUpOrDown
        title.stringValue = result.title
        title.lineBreakMode = .byTruncatingTail
        subtitle.stringValue = result.subtitle
        subtitle.lineBreakMode = .byTruncatingMiddle
        badgeName.stringValue = result.badge?.name ?? ""
        badgeDot.wantsLayer = true
        badgeDot.layer?.cornerRadius = Tokens.Metric.spaceDot / 2
        // §21.2 "Differentiate Without Colour": the Space's *name* is always next
        // to the dot, so the badge never depends on the colour to be readable.
        let showBadge = result.badge != nil
        badgeDot.isHidden = !showBadge
        badgeName.isHidden = !showBadge

        let stack = NSStackView(views: [icon, title, subtitle, badgeDot, badgeName])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = Tokens.Metric.panelInset
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.setHuggingPriority(.defaultHigh, for: .horizontal)
        // The title yields to the subtitle last: a truncated title is a row you
        // cannot identify, a truncated URL is still a URL.
        title.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        subtitle.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(stack)

        let inset = Tokens.Metric.rowInset + Tokens.Metric.panelInset
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: Tokens.Metric.rowHeight),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: Tokens.Metric.faviconSize),
            icon.heightAnchor.constraint(equalToConstant: Tokens.Metric.faviconSize),
            badgeDot.widthAnchor.constraint(equalToConstant: Tokens.Metric.spaceDot),
            badgeDot.heightAnchor.constraint(equalToConstant: Tokens.Metric.spaceDot)
        ])
    }

    private func applyTokens() {
        title.font = Tokens.TypeScale.sidebarRow
        subtitle.font = Tokens.TypeScale.sidebarRow
        badgeName.font = Tokens.TypeScale.sectionLabel
        // §3.4: the selected row has "brighter text"; §1 forbids separating tiers
        // by alpha alone, so the step is primary vs secondary, not a fade.
        title.textColor = isSelected ? Tokens.Text.primary : Tokens.Text.secondary
        subtitle.textColor = Tokens.Text.tertiary
        badgeName.textColor = Tokens.Text.tertiary
        icon.contentTintColor = isSelected ? Tokens.Text.primary : Tokens.Text.secondary
        // A Space colour is a fill, which is the one thing §1 permits it to be.
        badgeDot.layer?.backgroundColor = result.badge.map { NSColor($0.colour).cgColor }
    }

    private var accessibilityText: String {
        // VoiceOver gets the site name and the source, never a bare URL (UI-SPEC §8).
        [result.title, result.badge?.name, sourceDescription]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    private var sourceDescription: String {
        switch result.source {
        case .adaptive: "frequently chosen"
        case .directURL: "open address"
        case .openTab: "open tab"
        case .history: "history"
        case .archive: "archived tab"
        case .command: "command"
        case .search: "search"
        }
    }

    /// Swallowed, not ignored: the panel's backdrop dismisses the bar on
    /// `mouseDown`, and letting a row's press walk up there would tear the panel
    /// down before the `mouseUp` that was meant to choose this row ever arrived.
    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        onClick?()
    }
}
