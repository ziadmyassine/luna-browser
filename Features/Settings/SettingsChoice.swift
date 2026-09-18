//
//  SettingsChoice.swift
//  Luna
//
//  The pick-one control Settings uses everywhere.
//
//  **`NSSegmentedControl` paints its selection as a solid accent-blue block**,
//  which is the one thing this app's chrome never does: selection here is a
//  wash, exactly as it is on a sidebar row. So a segment is a plate with
//  `Surface.selected` on the one that is chosen, nothing on the others, and no
//  outline anywhere — bordering all three put the same weight on the two
//  answers you did not give as on the one you did.
//
//  A segment is also as wide as its word. Every one used to be a fixed 140 pt,
//  which put "Auto · Light · Dark" across half the pane and read as three
//  buttons rather than one choice.
//

import AppKit

@MainActor
final class SettingsChoice: NSView {

    var onSelect: ((Int) -> Void)?

    var selectedIndex: Int = 0 {
        didSet {
            guard selectedIndex != oldValue else { return }
            apply()
        }
    }

    private var buttons: [SettingsChoiceButton] = []

    init(labels: [String]) {
        super.init(frame: .zero)
        setAccessibilityRole(.radioGroup)
        buttons = labels.enumerated().map { index, label in
            let button = SettingsChoiceButton(title: label)
            button.onActivate = { [weak self] in
                self?.selectedIndex = index
                self?.onSelect?(index)
            }
            return button
        }
        let stack = NSStackView(views: buttons)
        stack.orientation = .horizontal
        stack.spacing = Tokens.Metric.settingsSegmentGap
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        apply()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    private func apply() {
        for (index, button) in buttons.enumerated() { button.isSelected = index == selectedIndex }
    }
}

/// One segment.
@MainActor
final class SettingsChoiceButton: NSView {

    var onActivate: (() -> Void)?

    var isSelected = false {
        didSet {
            guard isSelected != oldValue else { return }
            refresh(animated: true)
        }
    }

    private let label = NSTextField(labelWithString: "")
    private var isHovering = false

    init(title: String) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        label.stringValue = title
        label.font = Tokens.TypeScale.settingsRow
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        let inset = SettingsMetrics.controlInset
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: SettingsMetrics.controlHeight),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.radioButton)
        setAccessibilityLabel(title)
        refresh(animated: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    private func refresh(animated: Bool) {
        setAccessibilityValue(isSelected)
        let ink = isSelected || isHovering ? Tokens.Text.primary : Tokens.Text.secondary
        guard animated, !Tokens.Motion.reduceMotion else {
            label.textColor = ink
            needsDisplay = true
            return
        }
        Tokens.Motion.animate(Tokens.Motion.controlHover) { context in
            context.allowsImplicitAnimation = true
            self.label.textColor = ink
            self.needsDisplay = true
            self.displayIfNeeded()
        }
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        guard let layer else { return }
        layer.cornerRadius = SettingsMetrics.controlCorner
        layer.borderWidth = 0
        layer.backgroundColor = isSelected
            ? Tokens.Surface.selected.cgColor
            : (isHovering ? Tokens.Surface.hover.cgColor : nil)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refresh(animated: false)
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
        refresh(animated: true)
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        refresh(animated: true)
    }

    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onActivate?()
    }

    override func accessibilityPerformPress() -> Bool {
        onActivate?()
        return true
    }
}
