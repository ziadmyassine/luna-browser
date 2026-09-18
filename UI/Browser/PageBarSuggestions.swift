//
//  PageBarSuggestions.swift
//  Luna
//
//  §3.4's search suggestions, under §3.2b's address pill.
//
//  The Command Bar has offered these since the setting was built; typing in the
//  pill did not, which made the pill the one place in Luna where you could
//  start a search and get no help with it. This is that list: the engine's
//  completions for what is being typed, on the §5 popover material, hanging off
//  the bottom of the pill.
//
//  **It asks `SearchSuggestions` and nothing else.** That is the object that
//  owns the one network call in the query path, states what leaves the Mac and
//  keeps `UI/CommandBar` clear of a wire (see its header). A second fetcher here
//  would be a second answer to a question that has one.
//
//  **It is a list, not a results view.** `CommandBarResultsView` ranks tabs,
//  history and commands together and is built around `CommandBarResult`;
//  borrowing it would tie the page bar to §9's model for the sake of five rows
//  of plain text, and would put a `UI/CommandBar` type on a surface the privacy
//  test does not cover.
//

import AppKit

@MainActor
final class PageBarSuggestions: NSView {

    /// A phrase was chosen — by click, or by Return with a row selected.
    var onCommit: ((String) -> Void)?

    private(set) var phrases: [String] = []
    /// Which row Return would take. `nil` means "what the user typed", which is
    /// the state the list opens in: arriving at a suggestion has to be a thing
    /// the user did, or the first keystroke after a pause changes what Return
    /// does under their hands.
    private(set) var selected: Int?

    private var rows: [PageBarSuggestionRow] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.cornerRadius = Tokens.Metric.rowCornerRadius
        layer?.masksToBounds = true
        Glass.apply(.popover, to: self, cornerRadius: Tokens.Metric.rowCornerRadius)
        isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    /// The height this list wants for the phrases it is holding.
    var fittingHeight: CGFloat {
        guard !phrases.isEmpty else { return 0 }
        return CGFloat(phrases.count) * Tokens.Metric.rowHeight + 2 * Tokens.Metric.rowGap
    }

    // MARK: - Content

    func show(_ phrases: [String]) {
        self.phrases = phrases
        selected = nil
        rebuild()
        isHidden = phrases.isEmpty
        needsLayout = true
    }

    func dismiss() {
        show([])
    }

    /// ↑ / ↓. Returns false when there is nothing to move through, so the field
    /// keeps the key and the caret moves as it normally would.
    func move(_ offset: Int) -> Bool {
        guard !phrases.isEmpty else { return false }
        switch selected {
        case nil:
            // Down from the typed text lands on the first row; up from it wraps
            // to the last, which is how every list in this app behaves.
            selected = offset > 0 ? 0 : phrases.count - 1
        case let current?:
            let next = current + offset
            // Off either end is back to what the user typed, not a wrap: the
            // typed text is a real entry in this list and has to be reachable.
            selected = phrases.indices.contains(next) ? next : nil
        }
        refreshSelection()
        return true
    }

    /// What Return should commit, or nil to let the field commit its own text.
    var selectedPhrase: String? {
        selected.map { phrases[$0] }
    }

    private func rebuild() {
        for row in rows { row.removeFromSuperview() }
        rows = phrases.map { phrase in
            let row = PageBarSuggestionRow(phrase: phrase)
            row.onActivate = { [weak self] in self?.onCommit?(phrase) }
            addSubview(row)
            return row
        }
        refreshSelection()
    }

    private func refreshSelection() {
        for (index, row) in rows.enumerated() { row.isSelected = index == selected }
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        Tokens.Motion.immediately {
            let gap = Tokens.Metric.rowGap
            var y = bounds.maxY - gap
            for row in rows {
                y -= Tokens.Metric.rowHeight
                row.frame = NSRect(
                    x: gap,
                    y: y,
                    width: max(bounds.width - 2 * gap, 0),
                    height: Tokens.Metric.rowHeight
                ).integral
            }
        }
    }
}

/// One phrase. A row rather than a button: it carries §3.4's selection wash and
/// the same hover the sidebar's rows do, and an `NSButton` would bring a cell,
/// a bezel and a focus ring that all have to be turned off first.
@MainActor
final class PageBarSuggestionRow: NSView {

    var onActivate: (() -> Void)?

    var isSelected = false {
        didSet {
            guard isSelected != oldValue else { return }
            needsDisplay = true
        }
    }

    private let glyph = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private var isHovering = false

    init(phrase: String) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        glyph.image = NSImage(
            systemSymbolName: "magnifyingglass",
            accessibilityDescription: nil
        )?.withSymbolConfiguration(.init(pointSize: Tokens.Metric.faviconSize, weight: .regular))
        glyph.contentTintColor = Tokens.Text.secondary
        label.stringValue = phrase
        label.font = Tokens.TypeScale.urlPill
        label.textColor = Tokens.Text.primary
        label.lineBreakMode = .byTruncatingTail
        for view in [glyph, label] { addSubview(view) }
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(phrase)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.cornerRadius = Tokens.Metric.rowCornerRadius
        layer?.backgroundColor = isSelected
            ? Tokens.Surface.selected.cgColor
            : (isHovering ? Tokens.Surface.hover.cgColor : nil)
    }

    override func layout() {
        super.layout()
        Tokens.Motion.immediately {
            let size = Tokens.Metric.faviconSize
            glyph.frame = NSRect(
                x: Tokens.Metric.rowFaviconInset,
                y: (bounds.height - size) / 2,
                width: size,
                height: size
            ).integral
            let left = Tokens.Metric.rowTitleInset
            let height = label.intrinsicContentSize.height
            label.frame = NSRect(
                x: left,
                y: (bounds.height - height) / 2,
                width: max(bounds.width - left - Tokens.Metric.rowInset, 0),
                height: height
            ).integral
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where area.owner === self { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        needsDisplay = true
    }

    /// **On mouse-down, not on mouse-up.** The field is first responder while
    /// this list is showing, and a click anywhere else ends its editing — so by
    /// the time a mouse-up arrived the list had already been dismissed out from
    /// under the pointer.
    override func mouseDown(with event: NSEvent) {
        onActivate?()
    }

    override func accessibilityPerformPress() -> Bool {
        onActivate?()
        return true
    }

    override var mouseDownCanMoveWindow: Bool { false }
}
