//
//  SettingsSectionList.swift
//  Luna
//
//  §2's section list: ten rows, exactly one selected, always.
//
//  It is the browser's sidebar with sections where the tabs are: same
//  material, pitch, pill, insets and springs. `SidebarRowView` and this class
//  are two lists of one design, and every number below is the token that list
//  reads.
//
//  Three things were not the sidebar before and are now:
//
//  · The fills are `RowPillView` — §3.4's glass, moved between rows, rather
//    than a flat wash painted on whichever row was selected. Clear glass over
//    the column's own glass is what makes the selection read as a raised
//    surface instead of a grey band.
//  · No tile behind the symbol. A rounded square carrying `Surface.selected`
//    sat under every glyph, which made ten section icons into ten buttons.
//  · The sidebar's pitch: 38 pt of row around a 35 pt pill, not 34 around 31.
//    The list is a third of an inch taller for it (`settingsMinHeight`).
//
//  Views laid out with arithmetic rather than constraints, for the reason the
//  sidebar's rows are: ten fixed rows have nothing to solve, and the pills have
//  to be placed in the same pass as the rows they are following.
//

import AppKit

@MainActor
final class SettingsSectionList: NSView {

    /// Index of the section the user picked.
    var onSelect: ((Int) -> Void)?

    private var rows: [SettingsSectionRowView] = []
    /// §3.4's two fills, shared: the sidebar's own views, doing the sidebar's
    /// own job. See `RowPillView.move(to:spec:)`.
    private let selectionPill = RowPillView(role: .selected)
    private let hoverPill = RowPillView(role: .hover)
    private(set) var selected = 0
    private var hovered: Int?

    init(titles: [String], symbols: [String]) {
        super.init(frame: .zero)
        rows = zip(titles, symbols).enumerated().map { index, pair in
            let row = SettingsSectionRowView(title: pair.0, symbolName: pair.1)
            row.onClick = { [weak self] in self?.pick(index) }
            row.onHover = { [weak self] hovering in self?.setHovered(hovering ? index : nil, from: index) }
            return row
        }
        // Pills first: they are the row's background, and a background that is
        // added last covers the label it is supposed to be behind.
        for pill in [selectionPill, hoverPill] {
            pill.alphaValue = 0
            addSubview(pill)
        }
        for row in rows { addSubview(row) }

        setAccessibilityElement(true)
        setAccessibilityRole(.list)
        setAccessibilityLabel(String(localized: "Settings sections"))
        select(0)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    // MARK: - Layout

    /// Top-down, like every list: row 0 is at the top of the column.
    override var isFlipped: Bool { true }

    /// The rows' own height. The column gives the list whatever width it has
    /// and asks nothing else of it.
    override var intrinsicContentSize: NSSize {
        NSSize(
            width: NSView.noIntrinsicMetric,
            height: max(CGFloat(rows.count) * SettingsMetrics.sectionRowHeight - SettingsMetrics.sectionRowGap, 0)
        )
    }

    override func layout() {
        super.layout()
        // Bounds-derived frames never animate — see `Motion.immediately`.
        Tokens.Motion.immediately {
            for (index, row) in rows.enumerated() { row.frame = rect(ofRow: index) }
            movePills(animated: false)
        }
    }

    /// A row's own rect: the pitch is `sectionRowHeight` and the paint is
    /// `sectionPillHeight`, so the gap between two pills comes out of the row
    /// rather than being added between them.
    private func rect(ofRow index: Int) -> NSRect {
        NSRect(
            x: 0,
            y: CGFloat(index) * SettingsMetrics.sectionRowHeight,
            width: bounds.width,
            height: SettingsMetrics.sectionPillHeight
        ).pixelAligned
    }

    /// The two fills follow the rows instead of each row owning one.
    /// `animated: false` where the move is not the pill's own — a spring
    /// chasing a live window resize arrives after the row it belongs to.
    private func movePills(animated: Bool = true) {
        place(selectionPill, at: selected, spec: animated ? Tokens.Motion.selectedRowMove : nil)
        // Never both on one row: the hover lift under the selected pill is a
        // second wash on a row that already has one.
        place(hoverPill, at: hovered == selected ? nil : hovered, spec: animated ? Tokens.Motion.rowHover : nil)
    }

    private func place(_ pill: RowPillView, at index: Int?, spec: MotionSpec?) {
        // The width guard is for the list's first moments: `select(0)` runs
        // from `init`, before the column has given this view a width, and a
        // pill inset 8 pt inside nothing is a negative rectangle.
        guard let index, rows.indices.contains(index), bounds.width > Tokens.Metric.rowInset * 2 else {
            pill.fade(to: 0)
            return
        }
        // Inset horizontally only: the vertical gap is already in the pitch.
        pill.move(to: rect(ofRow: index).insetBy(dx: Tokens.Metric.rowInset, dy: 0), spec: spec)
    }

    // MARK: - Selection

    /// §2: exactly one, always. Out-of-range falls back to the first section
    /// rather than to none.
    func select(_ index: Int) {
        let target = rows.indices.contains(index) ? index : 0
        selected = target
        for (position, row) in rows.enumerated() { row.isSelected = position == target }
        movePills()
    }

    /// §2: a section with no matches is dimmed, not removed.
    func setDimmed(_ flags: [Bool]) {
        for (row, dimmed) in zip(rows, flags) { row.isDimmed = dimmed }
    }

    private func pick(_ index: Int) {
        select(index)
        onSelect?(index)
    }

    /// A row that is exited reports it, and so does the row that was entered.
    /// The `from` guard is what keeps the stale one of the two from winning:
    /// AppKit delivers the exit after the enter often enough to matter.
    private func setHovered(_ index: Int?, from row: Int) {
        if index == nil, hovered != row { return }
        guard hovered != index else { return }
        hovered = index
        movePills()
    }

    // MARK: - §8's keyboard

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        interpretKeyEvents([event])
    }

    override func moveUp(_ sender: Any?) {
        pick(max(selected - 1, 0))
    }

    override func moveDown(_ sender: Any?) {
        pick(min(selected + 1, rows.count - 1))
    }
}

/// One row of §2's list: `[symbol 16] [title 13 pt]`, on the sidebar's own two
/// insets. It draws nothing — the fills belong to the list, and an
/// unselected, unhovered row carries no chrome at all (§30.7).
@MainActor
final class SettingsSectionRowView: NSView {

    var onClick: (() -> Void)?
    var onHover: ((Bool) -> Void)?

    var isSelected = false {
        didSet {
            guard isSelected != oldValue else { return }
            setAccessibilityValue(isSelected)
            applyTint()
        }
    }

    /// §2's "dimmed, not removed" — the row is still there, still clickable,
    /// and still says what it is.
    var isDimmed = false {
        didSet {
            guard isDimmed != oldValue else { return }
            applyTint()
        }
    }

    private let label: NSTextField
    private let icon = NSImageView()

    init(title: String, symbolName: String) {
        label = NSTextField(labelWithString: title)
        super.init(frame: .zero)

        label.font = Tokens.TypeScale.settingsRow
        label.lineBreakMode = .byTruncatingTail
        label.cell?.usesSingleLineMode = true
        icon.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.symbolConfiguration = NSImage.SymbolConfiguration(
            pointSize: SettingsMetrics.symbolSize,
            weight: .regular
        )
        for view in [icon, label] { addSubview(view) }

        setAccessibilityElement(true)
        setAccessibilityRole(.radioButton)
        setAccessibilityLabel(title)
        setAccessibilityValue(false)
        applyTint()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    // MARK: - Layout

    /// The sidebar's two insets, unchanged: a 16 pt glyph centred inside the
    /// pill's own leading square (`rowFaviconInset`), and the title a
    /// `rowTitleGap` clear of it (`rowTitleInset`). A section row and a tab row
    /// line up on the same two columns.
    override func layout() {
        super.layout()
        Tokens.Motion.immediately {
            let glyph = Tokens.Metric.faviconSize
            icon.frame = NSRect(
                x: Tokens.Metric.rowFaviconInset,
                y: (bounds.height - glyph) / 2,
                width: glyph,
                height: glyph
            ).pixelAligned
            let x = Tokens.Metric.rowTitleInset
            // The title keeps the pill's own inset at the trailing end, the way
            // a tab's does.
            let height = label.fittingSize.height
            label.frame = NSRect(
                x: x,
                y: (bounds.height - height) / 2,
                width: max(bounds.width - x - Tokens.Metric.rowInset * 2, 0),
                height: height
            ).pixelAligned
        }
    }

    // MARK: - Ink

    /// §3.4's hierarchy, which is the sidebar's: the selected row is the only
    /// one set in full-strength ink. Hover moves the pill, not the type — a
    /// title that brightened under the pointer would compete with the row that
    /// is actually selected.
    private func applyTint() {
        let ink: NSColor = if isDimmed {
            Tokens.Text.disabled
        } else if isSelected {
            Tokens.Text.primary
        } else {
            Tokens.Text.secondary
        }
        label.textColor = ink
        icon.contentTintColor = ink
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyTint()
    }

    // MARK: - Input

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }

    override func mouseExited(with event: NSEvent) { onHover?(false) }

    override func mouseDown(with event: NSEvent) { onClick?() }

    override func accessibilityPerformPress() -> Bool {
        onClick?()
        return true
    }
}
