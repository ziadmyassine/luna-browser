//
//  SettingsSectionList.swift
//  Luna
//
//  §2's section list: nine rows, exactly one selected, always.
//
//  **A stack of views rather than an `NSTableView`.** Nine rows never scroll and
//  never change, so there is no cell reuse to do and no scroll position to keep
//  honest — and §2's "a section with no matches is dimmed, not removed" is one
//  property on a row here instead of a data-source shuffle that would make the
//  list jump under the pointer, which is exactly what §2 forbids.
//

import AppKit

@MainActor
final class SettingsSectionList: NSView {

    /// Index of the section the user picked.
    var onSelect: ((Int) -> Void)?

    private var rows: [SettingsSectionRowView] = []
    private(set) var selected = 0

    init(titles: [String], symbols: [String]) {
        super.init(frame: .zero)
        rows = zip(titles, symbols).enumerated().map { index, pair in
            let row = SettingsSectionRowView(title: pair.0, symbolName: pair.1)
            row.onClick = { [weak self] in self?.pick(index) }
            return row
        }
        let stack = NSStackView(views: rows)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = SettingsMetrics.sectionRowGap
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        // **Inset from the column, not flush to it.** The selected row is a
        // pill lying on the glass; a pill that runs edge to edge is a band, and
        // the reference leaves the same `rowInset` either side of it that the
        // browser sidebar leaves around a tab.
        let margin = Tokens.Metric.settingsSectionInset
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: margin),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -margin),
            stack.topAnchor.constraint(equalTo: topAnchor),
            // Less-than, not equal: the rows sit at the top and the column's
            // spare height stays spare.
            stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor)
        ] + rows.map { $0.widthAnchor.constraint(equalTo: stack.widthAnchor) })

        setAccessibilityElement(true)
        setAccessibilityRole(.list)
        setAccessibilityLabel(String(localized: "Settings sections"))
        select(0)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    // MARK: - Selection

    /// §2: exactly one, always. Out-of-range falls back to the first section
    /// rather than to none.
    func select(_ index: Int) {
        let target = rows.indices.contains(index) ? index : 0
        selected = target
        for (position, row) in rows.enumerated() { row.isSelected = position == target }
    }

    /// §2: a section with no matches is dimmed, **not** removed.
    func setDimmed(_ flags: [Bool]) {
        for (row, dimmed) in zip(rows, flags) { row.isDimmed = dimmed }
    }

    private func pick(_ index: Int) {
        select(index)
        onSelect?(index)
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

/// One row of §2's list: `rowHeight` of pitch, `rowCornerRadius` of pill.
@MainActor
final class SettingsSectionRowView: NSView {

    var onClick: (() -> Void)?

    var isSelected = false {
        didSet {
            guard isSelected != oldValue else { return }
            setAccessibilityValue(isSelected)
            needsDisplay = true
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

    private var isHovered = false {
        didSet {
            guard isHovered != oldValue else { return }
            needsDisplay = true
        }
    }

    private let label: NSTextField
    private let icon = NSImageView()
    /// The rounded square the symbol sits in. **The reference's one structural
    /// idea in this column**: a tile per section turns a stack of labels with
    /// glyphs beside them into a list of places, and it is what makes the eye
    /// land on the row rather than on the word.
    private let tile = NSView()

    init(title: String, symbolName: String) {
        label = NSTextField(labelWithString: title)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerCurve = .continuous

        label.font = Tokens.TypeScale.settingsRow
        label.lineBreakMode = .byTruncatingTail
        tile.wantsLayer = true
        tile.layer?.cornerCurve = .continuous
        icon.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: SettingsMetrics.symbolSize, weight: .regular))
        icon.translatesAutoresizingMaskIntoConstraints = false
        tile.addSubview(icon)
        tile.setContentHuggingPriority(.required, for: .horizontal)

        let stack = NSStackView(views: [tile, label])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = Tokens.Metric.chromeGap
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        let square = Tokens.Metric.settingsSectionIcon
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: SettingsMetrics.sectionRowInset),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -SettingsMetrics.sectionRowInset),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            tile.widthAnchor.constraint(equalToConstant: square.width),
            tile.heightAnchor.constraint(equalToConstant: square.height),
            icon.centerXAnchor.constraint(equalTo: tile.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: tile.centerYAnchor),
            heightAnchor.constraint(equalToConstant: Tokens.Metric.settingsSectionRow)
        ])

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

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.cornerRadius = SettingsMetrics.rowCornerRadius
        // §3.4's table, reused: a selected row keeps its pill under the
        // pointer, and an unselected row gets no fill at all until it is
        // hovered (§30.7).
        let fill: NSColor? = isSelected ? Tokens.Surface.selected : (isHovered ? Tokens.Surface.hover : nil)
        layer?.backgroundColor = fill?.cgColor
        layer?.borderWidth = isSelected && Tokens.A11y.increaseContrast ? Tokens.Metric.hairline : 0
        layer?.borderColor = Tokens.Line.border.cgColor
        // **A chip, and it has to read on both fills.** `Surface.well` is a
        // recess and disappeared into the glass; the tile is the same wash the
        // selected row carries, which lands one step above the column whether
        // the row under it is selected or not.
        tile.layer?.cornerRadius = Tokens.Metric.settingsSectionIcon.cornerRadius
        tile.layer?.backgroundColor = Tokens.Surface.selected.cgColor
        tile.layer?.borderWidth = Tokens.Metric.hairline
        tile.layer?.borderColor = Tokens.Line.border.cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
        applyTint()
    }

    private func applyTint() {
        label.textColor = isDimmed ? Tokens.Text.disabled : Tokens.Text.primary
        icon.contentTintColor = isDimmed ? Tokens.Text.disabled : Tokens.Text.primary
    }

    // MARK: - Input

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }

    override func mouseExited(with event: NSEvent) { isHovered = false }

    override func mouseDown(with event: NSEvent) { onClick?() }

    override func accessibilityPerformPress() -> Bool {
        onClick?()
        return true
    }
}
