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

    var selectedIndex: Int {
        get { selectedIndexStorage }
        set {
            guard newValue != selectedIndexStorage else { return }
            selectedIndexStorage = newValue
            apply()
        }
    }

    private var selectedIndexStorage = 0

    private var buttons: [SettingsChoiceButton] = []
    private let stack = NSStackView()

    init(labels: [String]) {
        super.init(frame: .zero)
        setAccessibilityRole(.radioGroup)
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
        setLabels(labels, selected: 0)
    }

    /// **The answers themselves can change.** Almost every choice in Settings
    /// has a fixed set of segments; one does not — §3.2's tab position offers a
    /// middle segment in the top-bar layout and only two in the sidebar's, and
    /// the row that decides which is directly above it. Rebuilding the segments
    /// is cheaper and more honest than dimming one that cannot apply.
    func setLabels(_ labels: [String], selected: Int) {
        for button in buttons { stack.removeArrangedSubview(button); button.removeFromSuperview() }
        buttons = labels.enumerated().map { index, label in
            let button = SettingsChoiceButton(title: label)
            button.onActivate = { [weak self] in
                self?.selectedIndex = index
                self?.onSelect?(index)
            }
            stack.addArrangedSubview(button)
            return button
        }
        // Assigned directly, not through the property: its `didSet` early-exits
        // on an unchanged value, and after a relabel "unchanged" still means the
        // wrong button is lit.
        selectedIndexStorage = min(max(selected, 0), max(labels.count - 1, 0))
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
