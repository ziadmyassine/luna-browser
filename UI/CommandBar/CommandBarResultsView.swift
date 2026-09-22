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
//  makes it observable, by putting the highlight back on the same result.
//
//  UI-SPEC §3.4 supplies the look: a filled translucent pill at
//  `rowCornerRadius`, inset `rowInset` from each edge, with a hairline border
//  and no background on the unselected rows. One pill that moves rather than a
//  fill per row — cheaper, and what §6's `selectedRowMove` describes.
//

import AppKit
import BrowserKit

@MainActor
final class CommandBarResultsView: NSView {

    /// Called when a row is clicked. Keyboard commits go through the input field.
    var onActivate: ((CommandBarResult) -> Void)?

    /// A result's favicon, asked for as each row is built. §4.7's icons are
    /// what make a list of eight sites scannable; a column of identical grey
    /// glyphs is not. Nil falls back to the row's own symbol, which is what a
    /// command and an un-cached site still get.
    var iconProvider: ((CommandBarResult) -> NSImage?)?

    private(set) var results: [CommandBarResult] = []
    private(set) var selectedID: String?

    private let rows = NSStackView()
    private let selection = Glass.backing(.control, cornerRadius: Tokens.Metric.rowCornerRadius)
    /// Whether the next placement is a §6 `selectedRowMove` — set by
    /// `setResults`, spent by `layout()`.
    private var slidesToNextRow = false

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
    ///
    /// Nothing here places the highlight; `layout()` does. It used to move
    /// the pill from this method whenever the list's ids had not changed, which
    /// is most of what happens while somebody types fast: the query re-ranks,
    /// the history lands, the engine's suggestions land, and each of those
    /// arrives with the same eight ids. The pill was then animated to a frame
    /// measured off rows that had not been laid out at their new size yet — so
    /// it slid to somewhere slightly wrong and the next layout pass snapped it
    /// back — the highlight that read as "moving around a bit weirdly".
    func setResults(_ new: [CommandBarResult], selecting id: String?) {
        let contentChanged = new.map(\.id) != results.map(\.id)
        let previous = selectedID
        results = new
        selectedID = id ?? new.first?.id

        if contentChanged { rebuildRows() }
        // §6's `selectedRowMove` describes one thing: the highlight travelling
        // from one row to another in a list that is standing still — ↓ and ↑.
        // A list that has just been rebuilt has no continuity for a slide to
        // describe, and a list that has not changed at all has nowhere to slide.
        slidesToNextRow = !contentChanged && selectedID != previous
        needsLayout = true

        for case let row as CommandBarRowView in rows.arrangedSubviews {
            row.isSelected = row.result.id == selectedID
        }
    }

    override func layout() {
        super.layout()
        // The rows first, then the pill that measures them. A view is laid
        // out before its children, so on the pass that follows a rebuild the
        // stack's rows still had no frames and the highlight was placed on a
        // zero rect — invisible. It stayed there until something else asked for
        // a layout, which on a freshly opened bar was the history query coming
        // back from SQLite: the highlight arrived about a second after the list
        // it belongs to, on a row that had been selected the whole time.
        rows.layoutSubtreeIfNeeded()
        moveSelectionPill(animated: slidesToNextRow)
        slidesToNextRow = false
    }

    func select(id: String?) {
        setResults(results, selecting: id)
    }

    // MARK: - Rows

    private func rebuildRows() {
        for view in rows.arrangedSubviews { view.removeFromSuperview() }
        for result in results {
            let row = CommandBarRowView(result: result, favicon: iconProvider?(result))
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
        guard selection.frame != target else { return }
        guard animated else {
            // Through `immediately`, because this is a consequence of a
            // layout and not a change to animate. A layout pass can run
            // inside somebody else's transaction — the bar's own opening
            // animation is one — and an implicitly animated frame on a glass
            // view sweeps the material across the list over the next few
            // frames.
            Tokens.Motion.immediately { selection.frame = target }
            return
        }
        Tokens.Motion.animate(Tokens.Motion.selectedRowMove) { context in
            context.allowsImplicitAnimation = true
            selection.animator().frame = target
        }
    }

}

// MARK: - One row

/// `[favicon 18] [title 15 pt] [subtitle]` in a 40 pt row (§3.4).
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
    /// §4.7's cached icon for this result, or nil for a command and for a site
    /// Luna has never fetched one from.
    private let favicon: NSImage?
    private let title = NSTextField(labelWithString: "")
    private let subtitle = NSTextField(labelWithString: "")

    init(result: CommandBarResult, favicon: NSImage?) {
        self.result = result
        self.favicon = favicon
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
        // A site's icon is its own colours, not chrome ink — so a favicon is
        // never a template and `applyTokens` leaves its tint alone.
        icon.image = favicon ?? NSImage(systemSymbolName: result.symbolName, accessibilityDescription: nil)
        favicon?.isTemplate = false
        icon.imageScaling = .scaleProportionallyUpOrDown
        title.stringValue = result.title
        title.lineBreakMode = .byTruncatingTail
        subtitle.stringValue = result.subtitle
        subtitle.lineBreakMode = .byTruncatingMiddle
        // No Space badge. Every row in the list is a row of the Space the bar
        // was opened in, so a chip naming it would be the same chip on every
        // row — and §21.2's reason for having one, telling two cookie jars
        // apart, cannot arise in a list that only ever holds one.
        let stack = NSStackView(views: [icon, title, subtitle])
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
            icon.heightAnchor.constraint(equalToConstant: Tokens.Metric.faviconSize)
        ])
    }

    private func applyTokens() {
        title.font = Tokens.TypeScale.commandBarRow
        subtitle.font = Tokens.TypeScale.commandBarRow
        // §3.4: the selected row has "brighter text"; §1 forbids separating tiers
        // by alpha alone, so the step is primary vs secondary, not a fade.
        title.textColor = isSelected ? Tokens.Text.primary : Tokens.Text.secondary
        subtitle.textColor = Tokens.Text.tertiary
        if favicon == nil {
            icon.contentTintColor = isSelected ? Tokens.Text.primary : Tokens.Text.secondary
        }
    }

    private var accessibilityText: String {
        // VoiceOver gets the site name and the source, never a bare URL (UI-SPEC §8).
        [result.title, sourceDescription]
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
        case .suggestion: "suggestion"
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
