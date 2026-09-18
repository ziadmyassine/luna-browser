//
//  SettingsChoice.swift
//  Luna
//
//  The pick-one control Settings uses everywhere, kept from Martin's first
//  Settings window when the rest of that file was superseded by `Shell/`.
//  The reason it exists is in the doc comment below and it is a measured one.
//

import AppKit

/// A pick-one control, in Luna's idiom rather than AppKit's.
///
/// **`NSSegmentedControl` paints its selection as a solid accent-blue block**,
/// which is the one thing this app's chrome never does: selection here is the
/// material. So the picker is a run of plates with a wash on the one that is
/// chosen, and it looks like the row pills and the pinned tiles it sits a
/// window away from.
///
/// **A segment is as wide as its word.** Every segment used to be a fixed
/// 140 pt, which is wider than "Auto", "Light" and "Dark" put together need and
/// wide enough that three of them crossed half the pane — the row read as three
/// buttons that happened to be next to each other rather than as one choice
/// with three settings. The reference sizes a segment from its label, leaves
/// two points between them, and lets the group end where the words do.
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

/// One segment in a `SettingsChoice`.
@MainActor
final class SettingsChoiceButton: NSView {

    var onActivate: (() -> Void)?

    var isSelected = false {
        didSet {
            guard isSelected != oldValue else { return }
            refresh()
        }
    }

    private let label = NSTextField(labelWithString: "")
    private var isHovering = false

    init(title: String) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        label.stringValue = title
        label.font = Tokens.TypeScale.sidebarRow
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        let inset = Tokens.Metric.settingsSegmentInset
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: Tokens.Metric.settingsSegmentHeight),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.radioButton)
        setAccessibilityLabel(title)
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    private func refresh() {
        label.textColor = isSelected || isHovering ? Tokens.Text.primary : Tokens.Text.secondary
        setAccessibilityValue(isSelected)
        needsDisplay = true
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        guard let layer else { return }
        layer.cornerRadius = Tokens.Metric.settingsSegmentCorner
        // **No outline on the ones you have not chosen.** Bordering every
        // segment drew the group as a row of empty boxes and put the same
        // weight on the two answers you did not give as on the one you did.
        // The wash is the whole signal, which is how selection reads
        // everywhere else in the app.
        layer.borderWidth = 0
        layer.backgroundColor = isSelected
            ? Tokens.Surface.selected.cgColor
            : (isHovering ? Tokens.Surface.hover.cgColor : nil)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refresh()
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
        refresh()
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        refresh()
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
