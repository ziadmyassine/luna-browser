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
//  **The selection is §9.2's, though**, because that is the one thing the two
//  lists genuinely share: one `.control` glass pill that *moves* between rows on
//  `Motion.selectedRowMove`, rather than a fill switched on and off per row. It
//  is cheaper — one backing instead of five — and the movement is what makes the
//  highlight readable when the arrows are held down.
//

import AppKit

@MainActor
final class PageBarSuggestions: NSView {

    /// A phrase was chosen — by click, or by Return with a row selected.
    var onCommit: ((String) -> Void)?

    private(set) var phrases: [String] = []
    /// Which row Return would take. `nil` is "what the user typed", which stays
    /// reachable — ↑ off the top of the list lands on it — but it is not where
    /// the list opens: the top suggestion is, so Return takes it without the
    /// user having to arrow down to it first.
    private(set) var selected: Int?

    private var rows: [PageBarSuggestionRow] = []
    /// §9.2's selector: one pill, moved, not five fills toggled.
    private let selection = Glass.backing(.control, cornerRadius: Tokens.Metric.rowCornerRadius)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.cornerRadius = Tokens.Metric.rowCornerRadius
        layer?.masksToBounds = true
        Glass.apply(.popover, to: self, cornerRadius: Tokens.Metric.rowCornerRadius)
        selection.isHidden = true
        addSubview(selection)
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
        selected = phrases.isEmpty ? nil : 0
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
        refreshSelection(animated: true)
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
            addSubview(row, positioned: .above, relativeTo: selection)
            return row
        }
        refreshSelection(animated: false)
    }

    private func refreshSelection(animated: Bool) {
        for (index, row) in rows.enumerated() { row.isSelected = index == selected }
        guard let index = selected, rows.indices.contains(index) else {
            selection.isHidden = true
            return
        }
        let target = rows[index].frame
        selection.isHidden = false
        guard animated, !target.isEmpty else {
            Tokens.Motion.immediately { selection.frame = target }
            return
        }
        Tokens.Motion.animate(Tokens.Motion.selectedRowMove) { context in
            context.allowsImplicitAnimation = true
            selection.animator().frame = target
        }
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
            // The pill follows the frames it was placed against; a resize that
            // moved the rows without moving it would leave it behind.
            refreshSelection(animated: false)
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
            applyTokens()
        }
    }

    private let glyph = NSImageView()
    private let label = NSTextField(labelWithString: "")

    init(phrase: String) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        glyph.image = NSImage(
            systemSymbolName: "magnifyingglass",
            accessibilityDescription: nil
        )?.withSymbolConfiguration(.init(pointSize: Tokens.Metric.faviconSize, weight: .regular))
        label.stringValue = phrase
        label.font = Tokens.TypeScale.urlPill
        label.lineBreakMode = .byTruncatingTail
        applyTokens()
        for view in [glyph, label] { addSubview(view) }
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(phrase)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    /// **A row paints nothing.** The highlight is the one glass pill behind
    /// these rows, and §9.2's list works the same way — it has no hover fill
    /// either. A second grey plate that lit under the pointer and then sat
    /// there was a second selection the keyboard could not move.
    ///
    /// What selection does change is the ink: §3.4's "brighter text", as a step
    /// from secondary to primary rather than a fade, because §1 forbids
    /// separating tiers by alpha alone.
    private func applyTokens() {
        label.textColor = isSelected ? Tokens.Text.primary : Tokens.Text.secondary
        glyph.contentTintColor = isSelected ? Tokens.Text.primary : Tokens.Text.secondary
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

    /// **On mouse-down, not on mouse-up.** The field is first responder while
    /// this list is showing, and a click anywhere else ends its editing — so by
    /// the time a mouse-up arrived the list had already been dismissed out from
    /// under the pointer.
    override func mouseDown(with event: NSEvent) {
        onActivate?()
    }

    /// The ink is dynamic, and the bar this row sits on changes appearance with
    /// the page under it — see `PageChromeBar`. Without this the rows keep the
    /// colours of whatever site was open when they were built.
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyTokens()
    }

    override func accessibilityPerformPress() -> Bool {
        onActivate?()
        return true
    }

    override var mouseDownCanMoveWindow: Bool { false }
}
