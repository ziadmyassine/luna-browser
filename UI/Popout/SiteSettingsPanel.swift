//
//  SiteSettingsPanel.swift
//  Luna
//
//  §3.2's site settings, as a pop-out from the glyph that opens them — the
//  sliders on the URL pill, and on §4's selected tab.
//
//  It used to be an `NSMenu`. A menu cannot hold a switch, so every per-site
//  answer was a checkmark you could not see until you opened it, and it was
//  the one surface a chrome glyph opened that was not a pop-out: History and
//  Downloads stand on their buttons in glass, and this dropped a system menu.
//
//  Three bands, top to bottom: what the connection is, the switches that are
//  this site's answers, and the things you can do to the site. The switches
//  keep the pop-out up, because the next question is usually the one beside
//  it; an action closes it, the way a menu item does.
//
//  The rows are §3.4's, pitch and pill: a glyph at `rowFaviconInset`, the
//  title a `rowIconGap` after it, and one pill that follows the pointer.
//

import AppKit

enum SiteSettingsMetrics {
    static var width: CGFloat { Tokens.Metric.siteSettingsPanel }
    static var headerHeight: CGFloat { PopoutMetrics.headerHeight }
    /// Above and below each band of rows.
    static var bandPadding: CGFloat { PopoutMetrics.padding }
    static var rowHeight: CGFloat { Tokens.Metric.rowHeight }
    static var glyphX: CGFloat { Tokens.Metric.rowFaviconInset }
    static var titleX: CGFloat { glyphX + Tokens.Metric.faviconSize + Tokens.Metric.rowIconGap }
}

/// Everything the pop-out shows, built fresh for the page on screen.
struct SiteSettingsContent {

    struct Toggle {
        var title: String
        var symbol: String
        var isOn: Bool
        var set: (Bool) -> Void
    }

    struct Action {
        var title: String
        var symbol: String
        var run: () -> Void
    }

    enum Connection { case secure, insecure }

    /// The header's words. The connection when there is one to speak of, the
    /// host otherwise.
    var heading: String
    var connection: Connection?
    var toggles: [Toggle] = []
    /// Each inner list is a band, with a hairline between bands.
    var actions: [[Action]] = []

    /// How tall the panel is with all of this in it.
    var height: CGFloat {
        let bands = (toggles.isEmpty ? [] : [toggles.count]) + actions.map(\.count).filter { $0 > 0 }
        let rows = bands.reduce(0) { total, count in
            total + CGFloat(count) * SiteSettingsMetrics.rowHeight + 2 * SiteSettingsMetrics.bandPadding
        }
        return SiteSettingsMetrics.headerHeight + rows + CGFloat(bands.count) * Tokens.Metric.hairline
    }
}

@MainActor
final class SiteSettingsPanel: PopoutPanelView {

    /// An action row was chosen. The controller closes the pop-out first, so
    /// a share sheet or a Settings window is not opened under it.
    var onAction: ((SiteSettingsContent.Action) -> Void)?

    private(set) var rows: [SiteSettingsRow] = []
    private let pill = RowPillView(role: .selected)
    private var hovered: Int?

    init(frame frameRect: NSRect, edge: PopoutEdge, content: SiteSettingsContent) {
        super.init(
            frame: frameRect,
            size: CGSize(width: SiteSettingsMetrics.width, height: content.height),
            edge: edge
        )
        centresOnAnchor = true
        pill.alphaValue = 0
        body.addSubview(pill)
        build(content)
        body.setAccessibilityRole(.group)
        body.setAccessibilityLabel(String(localized: "Site Settings"))
        body.setAccessibilityElement(true)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    // MARK: - Build

    /// Laid out top-down by hand: the body's height is the sum of what is in
    /// it, and every row is the same pitch.
    private var placements: [(NSView, CGFloat, CGFloat)] = []

    private func build(_ content: SiteSettingsContent) {
        var y: CGFloat = 0
        let header = SiteSettingsHeader(heading: content.heading, connection: content.connection)
        place(header, at: &y, height: SiteSettingsMetrics.headerHeight)

        var bands: [[SiteSettingsRow]] = []
        if !content.toggles.isEmpty {
            bands.append(content.toggles.map { SiteSettingsRow(toggle: $0) })
        }
        for band in content.actions where !band.isEmpty {
            bands.append(band.map { action in
                let row = SiteSettingsRow(action: action)
                row.onChoose = { [weak self] in self?.onAction?(action) }
                return row
            })
        }
        for band in bands {
            let line = NSView()
            line.wantsLayer = true
            line.layer?.backgroundColor = Tokens.Line.hairline.cgColor
            place(line, at: &y, height: Tokens.Metric.hairline)
            y += SiteSettingsMetrics.bandPadding
            for row in band {
                let index = rows.count
                row.onHover = { [weak self] inside in self?.hover(inside ? index : nil) }
                rows.append(row)
                place(row, at: &y, height: SiteSettingsMetrics.rowHeight)
            }
            y += SiteSettingsMetrics.bandPadding
        }
    }

    private func place(_ view: NSView, at y: inout CGFloat, height: CGFloat) {
        body.addSubview(view)
        placements.append((view, y, height))
        y += height
    }

    override func layout() {
        super.layout()
        Tokens.Motion.immediately {
            for (view, top, height) in placements {
                view.frame = NSRect(x: 0, y: body.bounds.height - top - height, width: body.bounds.width, height: height)
            }
            if let hovered { pill.frame = pillFrame(for: rows[hovered]) }
        }
    }

    // MARK: - The pill

    private func pillFrame(for row: SiteSettingsRow) -> NSRect {
        row.frame.insetBy(dx: Tokens.Metric.rowInset, dy: Tokens.Metric.rowPillInset)
    }

    private func hover(_ index: Int?) {
        guard index != hovered || index == nil else { return }
        // Leaving one row for the next reports the exit after the entry, and
        // an exit from a row the pill has already left is not a reason to hide it.
        if index == nil {
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

    // MARK: - Keyboard

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard !rows.isEmpty else { return super.keyDown(with: event) }
        switch event.keyCode {
        case 125: select(min((hovered ?? -1) + 1, rows.count - 1), animated: true)
        case 126: select(max((hovered ?? rows.count) - 1, 0), animated: true)
        // Return and Space: what a pressed row does.
        case 36, 76, 49: hovered.map { rows[$0].choose() }
        default: super.keyDown(with: event)
        }
    }
}

// MARK: - Header

/// The connection, in the reference's green when it is secure. Not a
/// control: there is nothing to do about it from here.
@MainActor
final class SiteSettingsHeader: NSView {

    private let glyph = NSImageView()
    let title = NSTextField(labelWithString: "")

    init(heading: String, connection: SiteSettingsContent.Connection?) {
        super.init(frame: .zero)
        let symbol = switch connection {
        case .secure: SiteMenu.Glyph.secure
        case .insecure: SiteMenu.Glyph.insecure
        case nil: SiteMenu.Glyph.site
        }
        glyph.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        glyph.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: Tokens.Metric.faviconSize, weight: .regular)
        glyph.contentTintColor = switch connection {
        case .secure: Tokens.Accent.secure
        case .insecure: Tokens.Accent.danger
        case nil: Tokens.Text.secondary
        }
        title.stringValue = heading
        title.font = Tokens.TypeScale.settingsHeading
        title.textColor = connection == .secure ? Tokens.Accent.secureText : Tokens.Text.primary
        title.lineBreakMode = .byTruncatingTail
        for view in [glyph, title] { addSubview(view) }
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel(heading)
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

// MARK: - Row

/// A switch row or an action row. A row, not a button (CLAUDE.md): the pill
/// is the panel's and follows the pointer, and nothing here swells.
@MainActor
final class SiteSettingsRow: NSView {

    var onHover: ((Bool) -> Void)?
    /// An action row was clicked. Unused on a switch row, whose click is the
    /// switch's.
    var onChoose: (() -> Void)?
    private(set) var isUnderPointer = false

    let toggle: SystemSwitch?
    private let glyph = NSImageView()
    private let title = NSTextField(labelWithString: "")

    init(toggle content: SiteSettingsContent.Toggle) {
        let toggle = SystemSwitch(isOn: content.isOn)
        toggle.onChange = content.set
        toggle.translatesAutoresizingMaskIntoConstraints = true
        toggle.setAccessibilityLabel(content.title)
        self.toggle = toggle
        super.init(frame: .zero)
        dress(title: content.title, symbol: content.symbol)
        addSubview(toggle)
    }

    init(action: SiteSettingsContent.Action) {
        toggle = nil
        super.init(frame: .zero)
        dress(title: action.title, symbol: action.symbol)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(action.title)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    private func dress(title text: String, symbol: String) {
        glyph.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        glyph.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: Tokens.Metric.faviconSize, weight: .regular)
        glyph.contentTintColor = Tokens.Text.primary
        glyph.setAccessibilityElement(false)
        title.stringValue = text
        title.font = Tokens.TypeScale.sidebarRow
        title.textColor = Tokens.Text.primary
        title.lineBreakMode = .byTruncatingTail
        title.setAccessibilityElement(false)
        for view in [glyph, title] { addSubview(view) }
    }

    override func layout() {
        super.layout()
        Tokens.Motion.immediately {
            let size = Tokens.Metric.faviconSize
            glyph.frame = NSRect(x: SiteSettingsMetrics.glyphX, y: (bounds.height - size) / 2, width: size, height: size)
            var end = bounds.width - 2 * Tokens.Metric.rowInset
            if let toggle {
                // Inset inside the pill by what centres it top to bottom, so
                // the switch sits in the pill the way the glyph does.
                let switchSize = toggle.intrinsicContentSize
                let inset = (Tokens.Metric.rowPillHeight - switchSize.height) / 2
                let x = bounds.width - Tokens.Metric.rowInset - inset - switchSize.width
                toggle.frame = NSRect(
                    x: x,
                    y: (bounds.height - switchSize.height) / 2,
                    width: switchSize.width,
                    height: switchSize.height
                ).integral
                end = x - Tokens.Metric.rowInset
            }
            let height = title.intrinsicContentSize.height
            title.frame = NSRect(
                x: SiteSettingsMetrics.titleX,
                y: (bounds.height - height) / 2,
                width: max(end - SiteSettingsMetrics.titleX, 0),
                height: height
            ).integral
        }
    }

    /// What a click, Return or Space does: flips the switch, or runs the action.
    func choose() {
        if let toggle {
            toggle.isOn.toggle()
            toggle.onChange?(toggle.isOn)
        } else {
            onChoose?()
        }
    }

    // MARK: - Pointer

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let superview, frame.contains(point) else { return nil }
        if let toggle, toggle.frame.contains(convert(point, from: superview)) {
            return toggle
        }
        return self
    }

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
