//
//  SpacePanel.swift
//  Luna
//
//  §3.5's and §4's Space pop-out: what a press on the Space's name opens, in
//  the sidebar's foot and on the top bar alike.
//
//  It was two native menus — a name and "Manage Spaces…" in the column, a
//  thirteen-line list of colour names on the bar's right-click — and neither
//  looked like anything else Luna opens from a control. It is built like §3.2's
//  site settings now: the same width, header, hairline bands and one pill
//  sliding between rows. The Spaces to go to, the colours as the swatches
//  Settings uses, and the verbs.
//

import AppKit
import BrowserKit

/// What the pop-out shows and what its rows do.
struct SpacePanelContent {
    var spaces: [Space]
    var activeID: UUID
    var switchTo: (UUID) -> Void
    var setGradient: (UUID, GradientPair) -> Void
    var edit: () -> Void
    var new: () -> Void

    var active: Space? { spaces.first { $0.id == activeID } }
}

enum SpacePanelMetrics {
    static var width: CGFloat { Tokens.Metric.siteSettingsPanel }
    static var headerHeight: CGFloat { PopoutMetrics.headerHeight }
    static var bandPadding: CGFloat { PopoutMetrics.padding }
    static var rowHeight: CGFloat { Tokens.Metric.rowHeight }
    static var swatch: CGFloat { Tokens.Metric.settingsControl }
    static var swatchGap: CGFloat { Tokens.Metric.chromeGap }
    /// Twelve colours and No Colour, seven to a line: seven 28 pt swatches
    /// and six gaps are 244 pt, inside the panel's 280 less its insets.
    static let swatchesPerLine = 7

    static func swatchLines(_ count: Int) -> Int { (count + swatchesPerLine - 1) / swatchesPerLine }

    static func colourHeight(_ count: Int) -> CGFloat {
        let lines = CGFloat(swatchLines(count))
        return lines * swatch + (lines - 1) * swatchGap
    }

    /// Header, then three bands under hairlines: the Spaces, the colours, the
    /// verbs.
    static func height(spaces: Int, swatches: Int) -> CGFloat {
        let bands = CGFloat(spaces + 2) * rowHeight + colourHeight(swatches)
        return headerHeight + bands + 6 * bandPadding + 3 * Tokens.Metric.hairline
    }
}

@MainActor
final class SpacePanel: PopoutPanelView {

    private(set) var rows: [SpacePanelRow] = []
    private(set) var swatches: [SpaceSwatchChip] = []
    private let pill = RowPillView(role: .selected)
    private var hovered: Int?
    /// Where each view stands, from the top: a row across the panel, or a
    /// swatch `inset` in from its leading edge at its own size.
    private struct Placement {
        let view: NSView
        let top: CGFloat
        let height: CGFloat
        var inset: CGFloat = 0
    }

    private var placements: [Placement] = []
    private let content: SpacePanelContent
    /// Closes the pop-out; the controller sets it.
    var onDone: (() -> Void)?

    init(frame frameRect: NSRect, edge: PopoutEdge, content: SpacePanelContent) {
        self.content = content
        let palette = Tokens.Gradient.spacePalette.count + 1
        super.init(
            frame: frameRect,
            size: CGSize(
                width: SpacePanelMetrics.width,
                height: SpacePanelMetrics.height(spaces: content.spaces.count, swatches: palette)
            ),
            edge: edge
        )
        centresOnAnchor = true
        pill.alphaValue = 0
        body.addSubview(pill)
        build()
        body.setAccessibilityRole(.group)
        body.setAccessibilityLabel(String(localized: "Spaces"))
        body.setAccessibilityElement(true)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    // MARK: - Build

    private func build() {
        var top: CGFloat = 0
        let active = content.active
        // "Spaces", not the Space's name: the list under it names the Space
        // and ticks it, and a header saying the same word read as a stutter.
        let header = SpacePanelHeader(symbol: SpacesSection.symbolName, title: String(localized: "Spaces"))
        place(header, at: &top, height: SpacePanelMetrics.headerHeight)

        band(&top) { top in
            for space in content.spaces {
                let row = SpacePanelRow(
                    symbol: space.symbolName,
                    title: space.name,
                    isChecked: space.id == content.activeID
                ) { [weak self] in
                    self?.onDone?()
                    self?.content.switchTo(space.id)
                }
                add(row, at: &top)
            }
        }
        band(&top) { top in buildColours(at: &top) }
        band(&top) { top in
            let name = active?.name ?? String(localized: "Space")
            add(SpacePanelRow(symbol: "pencil", title: String(localized: "Edit “\(name)”…")) { [weak self] in
                self?.onDone?()
                self?.content.edit()
            }, at: &top)
            add(SpacePanelRow(symbol: "plus", title: String(localized: "New Space")) { [weak self] in
                self?.onDone?()
                self?.content.new()
            }, at: &top)
        }
    }

    /// The colours, as the swatches §3.7's appearance settings use: the
    /// palette, then No Colour, the chosen one ringed. The way back out of a
    /// colour is always there, never only once one has been chosen.
    private func buildColours(at top: inout CGFloat) {
        guard let active = content.active else { return }
        let options = Array(zip(Tokens.Gradient.spacePalette, Tokens.Gradient.spacePaletteNames))
            + [(Tokens.Gradient.neutral, String(localized: "No Colour"))]
        let perLine = SpacePanelMetrics.swatchesPerLine
        let side = SpacePanelMetrics.swatch
        let gap = SpacePanelMetrics.swatchGap
        let lineWidth = CGFloat(perLine) * side + CGFloat(perLine - 1) * gap
        let inset = (SpacePanelMetrics.width - lineWidth) / 2
        for (index, option) in options.enumerated() {
            let chip = SpaceSwatchChip(gradient: option.0, label: option.1)
            chip.translatesAutoresizingMaskIntoConstraints = true
            chip.isChosen = option.0 == active.gradient
                || (Tokens.Gradient.isNeutral(option.0) && Tokens.Gradient.isNeutral(active.gradient))
            chip.onActivate = { [weak self] in
                guard let self else { return }
                content.setGradient(active.id, option.0)
                for other in swatches { other.isChosen = other === chip }
            }
            swatches.append(chip)
            let line = CGFloat(index / perLine)
            let column = CGFloat(index % perLine)
            body.addSubview(chip)
            placements.append(Placement(view: chip, top: top + line * (side + gap), height: side, inset: inset + column * (side + gap)))
        }
        top += SpacePanelMetrics.colourHeight(options.count)
    }

    /// A hairline, a band's padding, whatever `rows` adds, and the padding
    /// again — site settings' bands, rule for rule.
    private func band(_ top: inout CGFloat, _ rows: (inout CGFloat) -> Void) {
        let line = NSView()
        line.wantsLayer = true
        line.layer?.backgroundColor = Tokens.Line.hairline.cgColor
        place(line, at: &top, height: Tokens.Metric.hairline)
        top += SpacePanelMetrics.bandPadding
        rows(&top)
        top += SpacePanelMetrics.bandPadding
    }

    private func add(_ row: SpacePanelRow, at top: inout CGFloat) {
        let index = rows.count
        row.onHover = { [weak self] inside in self?.hover(inside ? index : nil) }
        rows.append(row)
        place(row, at: &top, height: SpacePanelMetrics.rowHeight)
    }

    private func place(_ view: NSView, at top: inout CGFloat, height: CGFloat) {
        body.addSubview(view)
        placements.append(Placement(view: view, top: top, height: height))
        top += height
    }

    override func layout() {
        super.layout()
        Tokens.Motion.immediately {
            for placement in placements {
                let width = placement.inset > 0 ? placement.height : body.bounds.width
                placement.view.frame = NSRect(
                    x: placement.inset,
                    y: body.bounds.height - placement.top - placement.height,
                    width: width,
                    height: placement.height
                )
            }
            if let hovered { pill.frame = pillFrame(for: rows[hovered]) }
        }
    }

    // MARK: - The pill

    private func pillFrame(for row: SpacePanelRow) -> NSRect {
        row.frame.insetBy(dx: Tokens.Metric.rowInset, dy: Tokens.Metric.rowPillInset)
    }

    private func hover(_ index: Int?) {
        guard let index else {
            guard let hovered, !rows[hovered].isUnderPointer else { return }
            self.hovered = nil
            pill.fade(to: 0)
            return
        }
        select(index, animated: true)
    }

    private func select(_ index: Int?, animated: Bool) {
        hovered = index
        guard let index else { return pill.fade(to: 0, animated: animated) }
        pill.move(to: pillFrame(for: rows[index]), spec: animated ? Tokens.Motion.selectedRowMove : nil)
    }

    // MARK: - Keys

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard !rows.isEmpty else { return super.keyDown(with: event) }
        switch event.keyCode {
        case 125: select(min((hovered ?? -1) + 1, rows.count - 1), animated: true)
        case 126: select(max((hovered ?? rows.count) - 1, 0), animated: true)
        case 36, 76, 49: hovered.map { rows[$0].choose() }
        default: super.keyDown(with: event)
        }
    }
}

/// The header, at site settings' size.
@MainActor
private final class SpacePanelHeader: NSView {

    private let glyph = NSImageView()
    private let title = NSTextField(labelWithString: "")

    init(symbol: String, title text: String) {
        super.init(frame: .zero)
        glyph.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        glyph.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: Tokens.Metric.faviconSize, weight: .regular)
        glyph.contentTintColor = Tokens.Text.secondary
        title.stringValue = text
        title.font = Tokens.TypeScale.settingsHeading
        title.textColor = Tokens.Text.primary
        title.lineBreakMode = .byTruncatingTail
        for view in [glyph, title] { addSubview(view) }
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel(text)
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
        title.frame = NSRect(
            x: SiteSettingsMetrics.titleX,
            y: (bounds.height - height) / 2,
            width: bounds.width - SiteSettingsMetrics.titleX - Tokens.Metric.rowInset,
            height: height
        ).integral
    }
}

/// One row: a glyph, a title, and a tick on the Space the window is in.
/// A list row, not a button (`CLAUDE.md`) — the panel's pill is its answer.
@MainActor
final class SpacePanelRow: NSView {

    var onHover: ((Bool) -> Void)?
    private(set) var isUnderPointer = false
    let isChecked: Bool
    private let run: () -> Void
    private let glyph = NSImageView()
    private let title = NSTextField(labelWithString: "")
    private let check = NSImageView()

    init(symbol: String, title text: String, isChecked: Bool = false, run: @escaping () -> Void) {
        self.run = run
        self.isChecked = isChecked
        super.init(frame: .zero)
        glyph.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        glyph.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: Tokens.Metric.faviconSize, weight: .regular)
        glyph.contentTintColor = Tokens.Text.primary
        title.stringValue = text
        title.font = Tokens.TypeScale.sidebarRow
        title.textColor = Tokens.Text.primary
        title.lineBreakMode = .byTruncatingTail
        check.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)
        check.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: Tokens.Metric.pillGlyphSize, weight: .semibold)
        check.contentTintColor = Tokens.Text.secondary
        check.isHidden = !isChecked
        for view in [glyph, title, check] {
            view.setAccessibilityElement(false)
            addSubview(view)
        }
        setAccessibilityElement(true)
        setAccessibilityRole(isChecked ? .radioButton : .button)
        setAccessibilityLabel(text)
        if isChecked { setAccessibilityValue(true) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    override func layout() {
        super.layout()
        Tokens.Motion.immediately {
            let size = Tokens.Metric.faviconSize
            glyph.frame = NSRect(x: SiteSettingsMetrics.glyphX, y: (bounds.height - size) / 2, width: size, height: size)
            // The tick stands where the glyph does at the other end.
            let checkX = bounds.width - SiteSettingsMetrics.glyphX - size
            check.frame = NSRect(x: checkX, y: (bounds.height - size) / 2, width: size, height: size)
            let height = title.intrinsicContentSize.height
            title.frame = NSRect(
                x: SiteSettingsMetrics.titleX,
                y: (bounds.height - height) / 2,
                width: max(checkX - Tokens.Metric.rowIconGap - SiteSettingsMetrics.titleX, 0),
                height: height
            ).integral
        }
    }

    func choose() { run() }

    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        choose()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where area.owner === self { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        isUnderPointer = true
        onHover?(true)
    }

    override func mouseExited(with event: NSEvent) {
        isUnderPointer = false
        onHover?(false)
    }

    override func accessibilityPerformPress() -> Bool {
        choose()
        return true
    }
}

// MARK: - Presenting

@MainActor
final class SpacePopoutController: PopoutController {

    private var edge: PopoutEdge = .below
    private var content: SpacePanelContent?

    func toggle(in window: NSWindow, from anchor: NSView, edge: PopoutEdge, content: SpacePanelContent) {
        self.edge = edge
        self.content = content
        toggle(in: window, from: anchor)
    }

    override func makePanel(in root: NSView) -> PopoutPanelView {
        guard let content else { return PopoutPanelView(frame: root.bounds, size: .zero, edge: edge) }
        let panel = SpacePanel(frame: root.bounds, edge: edge, content: content)
        panel.onDone = { [weak self] in self?.dismiss() }
        return panel
    }

    override func panelDidAppear(_ panel: PopoutPanelView) {
        panel.window?.makeFirstResponder(panel)
    }
}

/// The entry point for both places a Space's name can be pressed, as
/// `SiteMenu` is for §3.2's site settings.
@MainActor
enum SpacePopout {

    static let controller = SpacePopoutController()

    /// - Parameter aligned: a view to line the pop-out's leading edge up with
    ///   — the sidebar's Space pill.
    static func present(from anchor: NSView, content: SpacePanelContent, alignedTo aligned: NSView? = nil) {
        guard let window = anchor.window else { return }
        controller.alignsLeadingEdgeTo = aligned
        let edge: PopoutEdge = anchor.convert(anchor.bounds, to: nil).midY > window.contentLayoutRect.midY
            ? .below
            : .above
        controller.toggle(in: window, from: anchor, edge: edge, content: content)
    }
}
