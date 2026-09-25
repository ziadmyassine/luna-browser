//
//  ControlModePicker.swift
//  Luna
//
//  "Before an app acts on a page", as three cards with a moon in each: a thin
//  crescent for Ask, a half moon for Per Site, a full moon for Allow All. The
//  more of the moon is lit, the more an app may do without asking. The chosen
//  card's moon waxes to its phase; the others rest dim at theirs.
//

import AppKit
import LunaControl

@MainActor
final class ControlModePicker: NSView {

    struct Choice {
        let mode: ControlMode
        let title: String
        let caption: String
        let phase: CGFloat
        let explanation: String
    }

    static let choices: [Choice] = [
        Choice(mode: .ask, title: String(localized: "Ask"), caption: String(localized: "Every action"), phase: 0.2,
               explanation: String(localized: "Luna asks before every click, keypress and form an app fills.")),
        Choice(mode: .allowPerSite, title: String(localized: "Per Site"), caption: String(localized: "Once per site"),
               phase: 0.5,
               explanation: String(localized: """
               Luna asks the first time an app acts on a site. Press Allow and that site joins Allowed sites below.
               """)),
        Choice(mode: .allowAll, title: String(localized: "Allow All"), caption: String(localized: "No questions"),
               phase: 1,
               explanation: String(localized: "Apps act on any page without asking. Choose this only for apps you trust completely."))
    ]

    static let footnote = String(localized: "Reading a page never asks. Local files and pages that talk to the app always ask.")

    var onChange: ((ControlMode) -> Void)?

    private(set) var mode: ControlMode = .ask
    private let cards: [ControlModeCard]
    private let explanation = NSTextField(wrappingLabelWithString: "")

    init(title: String) {
        cards = Self.choices.map(ControlModeCard.init(choice:))
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let header = NSTextField(labelWithString: title)
        header.font = Tokens.TypeScale.settingsRow
        header.textColor = Tokens.Text.secondary
        let row = NSStackView(views: cards)
        row.distribution = .fillEqually
        row.spacing = Tokens.Metric.settingsListGap
        explanation.font = Tokens.TypeScale.settingsCaption
        explanation.textColor = Tokens.Text.secondary
        let footnote = NSTextField(wrappingLabelWithString: Self.footnote)
        footnote.font = Tokens.TypeScale.settingsCaption
        footnote.textColor = Tokens.Text.tertiary

        let column = NSStackView(views: [header, row, explanation, footnote])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = Tokens.Metric.chromeGap
        column.setCustomSpacing(Tokens.Metric.chromeGap + 2, after: row)
        column.setCustomSpacing(2, after: explanation)
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: leadingAnchor),
            column.trailingAnchor.constraint(equalTo: trailingAnchor),
            column.topAnchor.constraint(equalTo: topAnchor),
            column.bottomAnchor.constraint(equalTo: bottomAnchor),
            row.widthAnchor.constraint(equalTo: column.widthAnchor),
            explanation.widthAnchor.constraint(equalTo: column.widthAnchor),
            footnote.widthAnchor.constraint(equalTo: column.widthAnchor)
        ])
        for card in cards {
            card.onActivate = { [weak self] in self?.choose(card.choice.mode) }
        }
        setAccessibilityElement(true)
        setAccessibilityRole(.radioGroup)
        setAccessibilityLabel(title)
        select(.ask, animated: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    private func choose(_ chosen: ControlMode) {
        guard chosen != mode else { return }
        select(chosen, animated: true)
        onChange?(chosen)
    }

    /// Shows `chosen` without reporting it — what the section calls with the
    /// mode it read back from `ControlService`.
    func select(_ chosen: ControlMode, animated: Bool) {
        let changed = chosen != mode
        mode = chosen
        for card in cards { card.setSelected(card.choice.mode == chosen, animated: animated && changed) }
        let words = Self.choices.first { $0.mode == chosen }?.explanation ?? ""
        guard words != explanation.stringValue else { return }
        if animated, !Tokens.Motion.reduceMotion {
            let fade = CATransition()
            fade.type = .fade
            fade.duration = Tokens.Motion.spaceSwitchCrossfade.duration
            explanation.wantsLayer = true
            explanation.layer?.add(fade, forKey: "explanation")
        }
        explanation.stringValue = words
    }
}

/// One of the three. A card of its own, so it takes the hover wash and the
/// press swell itself, and the chosen one wears the accent round its edge.
@MainActor
final class ControlModeCard: NSView {

    let choice: ControlModePicker.Choice
    var onActivate: (() -> Void)?

    private let wash = NSView()
    private let moon: ControlModeMoonView
    private var isSelected = false
    private var isHovering = false {
        didSet { if isHovering != oldValue { refreshWash() } }
    }
    private var isPressed = false {
        didSet {
            guard isPressed != oldValue else { return }
            refreshWash()
            Tokens.Motion.swell(self, to: isPressed ? Tokens.Motion.pressSwell : 1)
        }
    }

    init(choice: ControlModePicker.Choice) {
        self.choice = choice
        moon = ControlModeMoonView(phase: choice.phase)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        wash.wantsLayer = true
        wash.layer?.cornerCurve = .continuous
        wash.layer?.cornerRadius = SettingsMetrics.rowCornerRadius

        let name = NSTextField(labelWithString: choice.title)
        name.font = .systemFont(ofSize: Tokens.TypeScale.settingsRow.pointSize, weight: .semibold)
        name.alignment = .center
        let caption = NSTextField(labelWithString: choice.caption)
        caption.font = Tokens.TypeScale.settingsCaption
        caption.textColor = Tokens.Text.secondary
        caption.alignment = .center
        let column = NSStackView(views: [moon, name, caption])
        column.orientation = .vertical
        column.spacing = Tokens.Metric.chromeGap
        column.setCustomSpacing(2, after: name)
        for view in [wash, column] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        let pad = SettingsMetrics.controlInset
        NSLayoutConstraint.activate([
            wash.leadingAnchor.constraint(equalTo: leadingAnchor),
            wash.trailingAnchor.constraint(equalTo: trailingAnchor),
            wash.topAnchor.constraint(equalTo: topAnchor),
            wash.bottomAnchor.constraint(equalTo: bottomAnchor),
            column.centerXAnchor.constraint(equalTo: centerXAnchor),
            column.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: pad),
            column.topAnchor.constraint(equalTo: topAnchor, constant: pad + 2),
            column.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -pad)
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.radioButton)
        setAccessibilityLabel(choice.title)
        setAccessibilityHelp(choice.explanation)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    func setSelected(_ selected: Bool, animated: Bool) {
        isSelected = selected
        setAccessibilityValue(selected)
        moon.setLit(selected, animated: animated)
        needsDisplay = true
        refreshWash()
    }

    /// §3.4's two washes, as `SettingsChoiceButton` has them: the chosen card
    /// already wears the press's, so a press on it answers with the swell.
    private func refreshWash() {
        let colour: NSColor? = isSelected || isPressed ? Tokens.Surface.selected : (isHovering ? Tokens.Surface.hover : nil)
        Tokens.Motion.wash(wash.layer, to: colour)
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        guard let layer else { return }
        layer.cornerRadius = SettingsMetrics.rowCornerRadius
        layer.backgroundColor = Tokens.Surface.raised.cgColor
        layer.borderWidth = isSelected ? Tokens.Metric.hairline * 1.5 : Tokens.Metric.hairline
        layer.borderColor = (isSelected ? Tokens.Accent.tint : Tokens.Line.border).cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
        refreshWash()
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

    override func mouseEntered(with event: NSEvent) { isHovering = true }

    override func mouseExited(with event: NSEvent) { isHovering = false }

    /// The whole card is the button: the wash, the moon and the labels on it
    /// are its face, not targets of their own.
    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }

    override func mouseDown(with event: NSEvent) { isPressed = true }

    override func mouseDragged(with event: NSEvent) {
        isPressed = bounds.contains(convert(event.locationInWindow, from: nil))
    }

    override func mouseUp(with event: NSEvent) {
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        isPressed = false
        guard inside else { return }
        onActivate?()
    }

    override func accessibilityPerformPress() -> Bool {
        onActivate?()
        return true
    }
}

/// A round window on the night sky with the card's moon in it.
@MainActor
final class ControlModeMoonView: NSView {

    private let phase: CGFloat
    private var shown: CGFloat
    private var lit: CGFloat = 0
    private struct Tween {
        let start: CFTimeInterval
        let from: CGFloat
        let litFrom: CGFloat
        let litTo: CGFloat
    }

    private var tween: Tween?
    private var link: CADisplayLink?

    init(phase: CGFloat) {
        self.phase = phase
        shown = phase
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let side = Tokens.Metric.controlModePorthole
        widthAnchor.constraint(equalToConstant: side).isActive = true
        heightAnchor.constraint(equalToConstant: side).isActive = true
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    override var isFlipped: Bool { true }

    /// Lit: the moon waxes from dark to its phase and its glow comes up.
    /// Unlit: it rests at its phase, dimmed.
    func setLit(_ on: Bool, animated: Bool) {
        let target: CGFloat = on ? 1 : 0
        guard animated, !Tokens.Motion.reduceMotion, window != nil else {
            tween = nil
            lit = target
            shown = phase
            needsDisplay = true
            return
        }
        tween = Tween(start: CACurrentMediaTime(), from: on ? 0 : shown, litFrom: lit, litTo: target)
        if link == nil {
            let made = displayLink(target: self, selector: #selector(tick(_:)))
            made.add(to: .main, forMode: .common)
            link = made
        }
    }

    @objc private func tick(_ sender: CADisplayLink) {
        guard let tween else { return stop() }
        let progress = Tokens.Motion.modePhase.progress(at: CACurrentMediaTime() - tween.start)
        shown = tween.from + (phase - tween.from) * progress
        lit = tween.litFrom + (tween.litTo - tween.litFrom) * progress
        needsDisplay = true
        if progress >= 1 {
            self.tween = nil
            stop()
        }
    }

    private func stop() {
        link?.invalidate()
        link = nil
    }

    /// The section rebuilds its body around this view while a card is still
    /// waxing, which takes it out of the window for a moment; the tween is
    /// timed off the clock, so it picks up where it would have been.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stop()
        guard window != nil, tween != nil else { return }
        let made = displayLink(target: self, selector: #selector(tick(_:)))
        made.add(to: .main, forMode: .common)
        link = made
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let centre = CGPoint(x: bounds.midX, y: bounds.midY), radius = bounds.width / 2 - 1
        context.saveGState()
        context.addEllipse(in: CGRect(x: centre.x - radius, y: centre.y - radius, width: 2 * radius, height: 2 * radius))
        context.clip()
        if let sky = CGGradient(
            colorsSpace: nil, colors: [Tokens.Moon.skyBottom.cgColor, Tokens.Moon.skyTop.cgColor] as CFArray, locations: [0, 1]
        ) {
            context.drawRadialGradient(sky, startCenter: CGPoint(x: centre.x, y: centre.y - radius * 0.25), startRadius: 2,
                                       endCenter: centre, endRadius: radius, options: [.drawsAfterEndLocation])
        }
        context.setFillColor(Tokens.Moon.star.withAlphaComponent(0.55).cgColor)
        for (x, y, size) in Self.stars {
            let at = CGPoint(x: bounds.minX + x * bounds.width, y: bounds.minY + y * bounds.height)
            context.fillEllipse(in: CGRect(x: at.x - size, y: at.y - size, width: 2 * size, height: 2 * size))
        }
        context.setAlpha(0.45 + 0.55 * lit)
        ControlMoon.draw(in: context, center: centre, radius: Tokens.Metric.controlModeMoon,
                         light: ControlMoon.Light(phase: shown, glow: 0.9 * lit, earthshine: 0.14),
                         scale: window?.backingScaleFactor ?? 2)
        context.restoreGState()
    }

    /// Five stars at fixed places in the window, as fractions of its side.
    private static let stars: [(CGFloat, CGFloat, CGFloat)] = [
        (0.23, 0.27, 0.6), (0.77, 0.23, 0.5), (0.73, 0.77, 0.7), (0.19, 0.69, 0.45), (0.38, 0.85, 0.4)
    ]
}
