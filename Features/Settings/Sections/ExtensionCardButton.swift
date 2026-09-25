//
//  ExtensionCardButton.swift
//  Luna
//
//  The small controls on an extension's card in Settings: the Spaces it runs
//  in, its pin, and its "more" menu. A glyph, a word, or both, on no plate of
//  its own — the card is the surface, and three bordered buttons on a card a
//  third of the pane wide read as a form.
//
//  It answers like every button in Luna (`CLAUDE.md`): §3.4's hover wash, the
//  press's at twice it, and the swell. `isOn` keeps the press's wash, as a
//  chosen `SettingsChoiceButton` does, so a pinned pin reads as held.
//

import AppKit

@MainActor
final class ExtensionCardButton: NSView {

    var onActivate: (() -> Void)?
    /// Opens under the button instead of `onActivate` when set.
    var menuBuilder: (() -> NSMenu)?

    var isOn = false { didSet { if isOn != oldValue { refresh() } } }

    private let glyph = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private var isHovering = false { didSet { if isHovering != oldValue { refresh() } } }
    private var isPressed = false {
        didSet {
            guard isPressed != oldValue else { return }
            refresh()
            Tokens.Motion.swell(self, to: isPressed ? Tokens.Motion.pressSwell : 1)
        }
    }

    init(symbol: String?, title: String? = nil, label accessibility: String) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        translatesAutoresizingMaskIntoConstraints = false
        glyph.image = symbol.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }
        glyph.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: Tokens.Metric.pillGlyphSize, weight: .regular)
        glyph.isHidden = symbol == nil
        label.stringValue = title ?? ""
        label.font = Tokens.TypeScale.settingsCaption
        label.isHidden = title == nil
        label.lineBreakMode = .byTruncatingTail
        let stack = NSStackView(views: [glyph, label])
        stack.orientation = .horizontal
        stack.spacing = Tokens.Metric.rowGap * 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        let height = SettingsMetrics.controlHeight
        let pad = title == nil ? 0 : SettingsMetrics.controlInset - Tokens.Metric.rowGap
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: height),
            widthAnchor.constraint(greaterThanOrEqualToConstant: height),
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: pad),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -pad),
            glyph.widthAnchor.constraint(equalToConstant: Tokens.Metric.faviconSize)
        ])
        // A word sizes the button; a glyph alone makes it a circle.
        if title != nil {
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: pad).isActive = true
        } else {
            widthAnchor.constraint(equalToConstant: height).isActive = true
        }
        toolTip = accessibility
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(accessibility)
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    func setTitle(_ title: String) {
        label.stringValue = title
    }

    func setSymbol(_ symbol: String) {
        glyph.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
    }

    private func refresh() {
        let ink = isOn || isHovering || isPressed ? Tokens.Text.primary : Tokens.Text.secondary
        glyph.contentTintColor = ink
        label.textColor = ink
        setAccessibilityValue(isOn)
        let fill: NSColor? = isOn || isPressed ? Tokens.Surface.selected : (isHovering ? Tokens.Surface.hover : nil)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            Tokens.Motion.wash(self.layer, to: fill)
        }
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height / 2
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refresh()
    }

    // MARK: - Pointer

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where area.owner === self { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) { isHovering = true }
    override func mouseExited(with event: NSEvent) { isHovering = false }

    override func mouseDown(with event: NSEvent) { isPressed = true }

    override func mouseDragged(with event: NSEvent) {
        isPressed = bounds.contains(convert(event.locationInWindow, from: nil))
    }

    override func mouseUp(with event: NSEvent) {
        let inside = isPressed
        isPressed = false
        guard inside else { return }
        activate()
    }

    override func accessibilityPerformPress() -> Bool {
        activate()
        return true
    }

    private func activate() {
        guard let menuBuilder else { return onActivate?() ?? () }
        // Its top edge a gap under the button's bottom one.
        let below = isFlipped ? bounds.maxY + Tokens.Metric.rowGap : -Tokens.Metric.rowGap
        menuBuilder().popUp(positioning: nil, at: NSPoint(x: 0, y: below), in: self)
    }

    override var mouseDownCanMoveWindow: Bool { false }
}
