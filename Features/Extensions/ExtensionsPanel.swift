//
//  ExtensionsPanel.swift
//  Luna
//
//  §16.4's pop-out: every extension installed, one row each with a switch for
//  the window's Space, and the way to Settings under them.
//
//  Built like §3.2's site settings pop-out, which it stands beside on every
//  surface: the same width, header, switches and one pill sliding between
//  rows. A row runs its extension; the switch turns it on or off here; the
//  pin beside the switch puts it on the bar.
//

import AppKit

enum ExtensionsPanelMetrics {
    static var width: CGFloat { Tokens.Metric.siteSettingsPanel }
    static var headerHeight: CGFloat { PopoutMetrics.headerHeight }
    static var bandPadding: CGFloat { PopoutMetrics.padding }
    static var rowHeight: CGFloat { Tokens.Metric.rowHeight }
    static var visibleRows: Int { Tokens.Metric.extensionsPanelRows }

    /// The list's own height: every row up to `visibleRows` with a band's
    /// padding above and below, as §3.2's site settings pad theirs, and the
    /// empty state's two lines when there are none.
    static func listHeight(rows: Int) -> CGFloat {
        guard rows > 0 else { return emptyHeight }
        return CGFloat(min(rows, visibleRows)) * rowHeight + 2 * bandPadding
    }

    static var emptyHeight: CGFloat { 2 * rowHeight }

    /// Header, a hairline, the list, a hairline, then the footer's one row —
    /// site settings' header and bands, rule for rule.
    static func height(rows: Int) -> CGFloat {
        headerHeight + 2 * Tokens.Metric.hairline + listHeight(rows: rows) + rowHeight + 2 * bandPadding
    }
}

@MainActor
final class ExtensionsPanel: PopoutPanelView {

    /// A row was chosen: run that extension.
    var onRun: ((String) -> Void)?
    var onPin: ((String, Bool) -> Void)?
    var onSwitch: ((String, Bool) -> Void)?
    var onManage: (() -> Void)?

    private(set) var rows: [ExtensionsPanelRow] = []
    private let header = ExtensionsPanelHeader()
    private let scroll = NSScrollView()
    private let list = FlippedView()
    private let empty = ExtensionsPanelEmpty()
    /// Under the header, and over the footer: the rule every band in
    /// §3.2's site settings stands on. Without the first, the list ran
    /// straight on from the title.
    private let headerLine = NSView()
    private let line = NSView()
    private(set) var footer: SiteSettingsRow
    private let pill = RowPillView(role: .selected)
    /// The row the pill is on, in `rows` — or `rows.count` for the footer.
    private var hovered: Int?

    init(frame frameRect: NSRect, edge: PopoutEdge, items: [ExtensionShelfItem]) {
        footer = SiteSettingsRow(action: .init(
            title: items.isEmpty ? String(localized: "Add Extensions…") : String(localized: "Manage Extensions…"),
            symbol: items.isEmpty ? "plus" : "gearshape",
            run: {}
        ))
        super.init(
            frame: frameRect,
            size: CGSize(width: ExtensionsPanelMetrics.width, height: ExtensionsPanelMetrics.height(rows: items.count)),
            edge: edge
        )
        centresOnAnchor = true
        build()
        setItems(items)
        body.setAccessibilityRole(.group)
        body.setAccessibilityLabel(String(localized: "Extensions"))
        body.setAccessibilityElement(true)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    private func build() {
        scroll.drawsBackground = false
        scroll.contentView.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.horizontalScrollElasticity = .none
        scroll.scrollerStyle = .overlay
        scroll.automaticallyAdjustsContentInsets = false
        scroll.documentView = list
        for rule in [headerLine, line] {
            rule.wantsLayer = true
            rule.layer?.backgroundColor = Tokens.Line.hairline.cgColor
        }
        pill.alphaValue = 0
        footer.onChoose = { [weak self] in self?.onManage?() }
        footer.onHover = { [weak self] inside in self?.hover(inside ? self?.rows.count : nil) }
        // The pill slides between list rows and the footer, so it stands in
        // the body, under the scroll view whose rows it lights.
        for view in [pill, header, headerLine, scroll, empty, line, footer] { body.addSubview(view) }
    }

    /// Rebuilds the rows in place: the panel keeps its height while it is
    /// open, and a pin or a badge changing is a row changing, not a new panel.
    func setItems(_ items: [ExtensionShelfItem]) {
        // The same extensions in the same order: each row takes its own
        // change, so a switch that is still sliding is not replaced mid-way.
        if items.map(\.id) == rows.map(\.item.id) {
            for (row, item) in zip(rows, items) { row.update(item) }
            header.count = items.filter(\.isOn).count
            return
        }
        let hoveredID = hovered.flatMap { $0 < rows.count ? rows[$0].item.id : nil }
        for row in rows { row.removeFromSuperview() }
        rows = items.enumerated().map { index, item in
            let row = ExtensionsPanelRow(item: item)
            row.onChoose = { [weak self] in self?.onRun?(item.id) }
            row.onPin = { [weak self] pinned in self?.onPin?(item.id, pinned) }
            row.onSwitch = { [weak self] isOn in self?.onSwitch?(item.id, isOn) }
            row.onHover = { [weak self] inside in self?.hover(inside ? index : nil) }
            list.addSubview(row)
            return row
        }
        header.count = items.filter(\.isOn).count
        empty.isHidden = !items.isEmpty
        scroll.isHidden = items.isEmpty
        hovered = hoveredID.flatMap { id in rows.firstIndex { $0.item.id == id } }
        if hovered == nil { pill.fade(to: 0, animated: false) }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        Tokens.Motion.immediately { placeContents() }
    }

    private func placeContents() {
        let width = body.bounds.width
        let rowHeight = ExtensionsPanelMetrics.rowHeight
        var top = body.bounds.height
        header.frame = NSRect(x: 0, y: top - ExtensionsPanelMetrics.headerHeight, width: width, height: ExtensionsPanelMetrics.headerHeight)
        top -= ExtensionsPanelMetrics.headerHeight
        headerLine.frame = NSRect(x: 0, y: top - Tokens.Metric.hairline, width: width, height: Tokens.Metric.hairline)
        top -= Tokens.Metric.hairline

        let listHeight = ExtensionsPanelMetrics.listHeight(rows: rows.count)
        let listFrame = NSRect(x: 0, y: top - listHeight, width: width, height: listHeight)
        scroll.frame = listFrame
        empty.frame = listFrame
        let padding = ExtensionsPanelMetrics.bandPadding
        list.frame = NSRect(x: 0, y: 0, width: width, height: CGFloat(rows.count) * rowHeight + 2 * padding)
        for (index, row) in rows.enumerated() {
            row.frame = NSRect(x: 0, y: padding + CGFloat(index) * rowHeight, width: width, height: rowHeight)
        }
        top -= listHeight

        line.frame = NSRect(x: 0, y: top - Tokens.Metric.hairline, width: width, height: Tokens.Metric.hairline)
        top -= Tokens.Metric.hairline + padding
        footer.frame = NSRect(x: 0, y: top - rowHeight, width: width, height: rowHeight)
        if let hovered { pill.frame = pillFrame(for: hovered) }
    }

    // MARK: - The pill

    private func view(at index: Int) -> NSView? {
        index == rows.count ? footer : (rows.indices.contains(index) ? rows[index] : nil)
    }

    private func pillFrame(for index: Int) -> NSRect {
        guard let row = view(at: index) else { return .zero }
        return body.convert(row.bounds, from: row)
            .insetBy(dx: Tokens.Metric.rowInset, dy: Tokens.Metric.rowPillInset)
    }

    private func hover(_ index: Int?) {
        guard let index else {
            guard let hovered, let row = view(at: hovered), !Self.isUnderPointer(row) else { return }
            self.hovered = nil
            pill.fade(to: 0)
            return
        }
        select(index, animated: true)
    }

    private static func isUnderPointer(_ view: NSView) -> Bool {
        (view as? ExtensionsPanelRow)?.isUnderPointer ?? (view as? SiteSettingsRow)?.isUnderPointer ?? false
    }

    private func select(_ index: Int?, animated: Bool) {
        hovered = index
        guard let index else { return pill.fade(to: 0, animated: animated) }
        if index < rows.count { rows[index].scrollToVisible(rows[index].bounds) }
        pill.move(to: pillFrame(for: index), spec: animated ? Tokens.Motion.selectedRowMove : nil)
    }

    // MARK: - Keys

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        let last = rows.count
        switch event.keyCode {
        case 125: select(min((hovered ?? -1) + 1, last), animated: true)
        case 126: select(max((hovered ?? last + 1) - 1, 0), animated: true)
        case 36, 76, 49:
            guard let hovered else { return }
            if hovered == last { footer.choose() } else { rows[hovered].choose() }
        default: super.keyDown(with: event)
        }
    }
}

// MARK: - Header

/// "Extensions", and how many are running here, at the site settings
/// header's size and inset.
@MainActor
final class ExtensionsPanelHeader: NSView {

    var count = 0 { didSet { detail.stringValue = String(localized: "\(count) on in this Space") } }

    private let glyph = NSImageView()
    private let title = NSTextField(labelWithString: String(localized: "Extensions"))
    private let detail = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        glyph.image = NSImage(systemSymbolName: ExtensionsSymbol.name, accessibilityDescription: nil)
        glyph.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: Tokens.Metric.faviconSize, weight: .regular)
        glyph.contentTintColor = Tokens.Text.secondary
        title.font = Tokens.TypeScale.settingsHeading
        title.textColor = Tokens.Text.primary
        detail.font = Tokens.TypeScale.sidebarRow
        detail.textColor = Tokens.Text.tertiary
        detail.alignment = .right
        for view in [glyph, title, detail] { addSubview(view) }
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel(String(localized: "Extensions"))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    override func layout() {
        super.layout()
        let size = Tokens.Metric.faviconSize
        glyph.frame = NSRect(x: SiteSettingsMetrics.glyphX, y: (bounds.height - size) / 2, width: size, height: size)
        let height = title.intrinsicContentSize.height
        let end = bounds.width - SiteSettingsMetrics.glyphX
        let detailWidth = ceil(detail.intrinsicContentSize.width)
        detail.frame = NSRect(x: end - detailWidth, y: (bounds.height - height) / 2, width: detailWidth, height: height).integral
        title.frame = NSRect(
            x: SiteSettingsMetrics.titleX,
            y: (bounds.height - height) / 2,
            width: max(end - detailWidth - Tokens.Metric.rowInset - SiteSettingsMetrics.titleX, 0),
            height: height
        ).integral
    }
}

// MARK: - Empty

/// Nothing running in this Space: what extensions are, and where they come
/// from, in the words the footer's row then acts on.
@MainActor
final class ExtensionsPanelEmpty: NSView {

    private let text = NSTextField(wrappingLabelWithString: String(localized: """
    No extensions yet. Add one from the Chrome Web Store or a folder, \
    and it shows up here.
    """))

    init() {
        super.init(frame: .zero)
        text.font = Tokens.TypeScale.sidebarRow
        text.textColor = Tokens.Text.secondary
        text.alignment = .center
        addSubview(text)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    override func layout() {
        super.layout()
        let inset = PopoutMetrics.inset
        let width = max(bounds.width - 2 * inset, 0)
        let height = text.sizeThatFits(NSSize(width: width, height: .greatestFiniteMagnitude)).height
        text.frame = NSRect(x: inset, y: (bounds.height - height) / 2, width: width, height: height).integral
    }
}
