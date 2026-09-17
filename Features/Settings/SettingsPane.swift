//
//  SettingsPane.swift
//  Luna
//
//  **The registry the Settings window is built from.** Adding a section is one
//  `SettingsPane` in `SettingsPane.all` and one function that returns its view
//  — no window code, no list code, no selection bookkeeping.
//
//  It is a list rather than an enum on purpose: an enum would put every pane's
//  construction in one exhaustive switch, and the point of this file is that
//  two people can add panes without meeting in the same function.
//
//      SettingsPane(
//          id: "privacy",
//          title: String(localized: "Privacy"),
//          symbolName: "hand.raised",
//          build: { PrivacySettingsView() }
//      )
//
//  A pane's view owns its own reading and writing of `Settings`; the window
//  only decides which one is on screen.
//

import AppKit

/// One row in the Settings sidebar, and the view it puts on the right.
@MainActor
struct SettingsPane: Identifiable {
    let id: String
    let title: String
    /// SF Symbol for the sidebar row. Icon **and** title — this list is short
    /// and unfamiliar, so nothing here is icon-only (§21.1).
    let symbolName: String
    let build: @MainActor () -> NSView
}

extension SettingsPane {

    /// Every section, in the order the sidebar shows them.
    static var all: [SettingsPane] {
        [
            SettingsPane(
                id: "appearance",
                title: String(localized: "Appearance"),
                symbolName: "paintbrush",
                build: { AppearanceSettingsView() }
            )
        ]
    }
}

// MARK: - Appearance

/// Luna's one setting today: which chrome the window wears (§3 vs §4).
@MainActor
final class AppearanceSettingsView: NSView {

    private let layoutControl = SettingsChoice(labels: ChromeLayoutPreference.allCases.map(\.title))
    private let layoutDetail = SettingsText.caption("")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        build()
        read()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    private func build() {
        layoutControl.onSelect = { [weak self] index in self?.layoutChanged(index) }

        // The one thing `⌘S` no longer does, said out loud: a user who used to
        // swap layouts with the keystroke needs to be told where it went.
        let note = SettingsText.caption(String(
            localized: "⌘S hides and shows the sidebar. It no longer changes the layout."
        ))

        let group = SettingsText.group(
            title: String(localized: "Tab layout"),
            views: [layoutControl, layoutDetail, note]
        )
        group.translatesAutoresizingMaskIntoConstraints = false
        addSubview(group)
        NSLayoutConstraint.activate([
            group.topAnchor.constraint(equalTo: topAnchor),
            group.leadingAnchor.constraint(equalTo: leadingAnchor),
            group.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            group.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor)
        ])
    }

    private func read() {
        let current = Settings.chromeLayout
        layoutControl.selectedIndex = ChromeLayoutPreference.allCases.firstIndex(of: current) ?? 0
        layoutDetail.stringValue = current.detail
    }

    private func layoutChanged(_ index: Int) {
        let cases = ChromeLayoutPreference.allCases
        guard cases.indices.contains(index) else { return }
        Settings.chromeLayout = cases[index]
        layoutDetail.stringValue = cases[index].detail
    }
}

// MARK: - Shared furniture

/// The two text shapes a pane needs, so panes agree with each other without
/// each one picking its own font.
@MainActor
enum SettingsText {

    static func heading(_ text: String) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = Tokens.TypeScale.settingsHeading
        field.textColor = Tokens.Text.primary
        return field
    }

    static func caption(_ text: String) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = Tokens.TypeScale.settingsCaption
        field.textColor = Tokens.Text.secondary
        field.lineBreakMode = .byWordWrapping
        field.maximumNumberOfLines = 3
        return field
    }

    /// A titled group: heading, then its controls, left-aligned.
    static func group(title: String, views: [NSView]) -> NSStackView {
        let stack = NSStackView(views: [heading(title)] + views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = Tokens.Metric.chromeGap
        stack.setCustomSpacing(Tokens.Metric.chromeGapWide, after: stack.views[0])
        return stack
    }
}


// MARK: - The picker

/// A pick-one control, in Luna's idiom rather than AppKit's.
///
/// **`NSSegmentedControl` paints its selection as a solid accent-blue block**,
/// which is the one thing this app's chrome never does: selection here is the
/// material. So the picker is two capsules — a plate each, glass on the one
/// that is chosen — and it looks like the row pills and the pinned tiles it
/// sits a window away from.
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
        stack.spacing = Tokens.Metric.chromeGap
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

/// One capsule in a `SettingsChoice`.
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
    private var glass: NSView?
    private var isHovering = false

    init(title: String) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.cornerRadius = Tokens.Metric.urlPill.cornerRadius
        label.stringValue = title
        label.font = Tokens.TypeScale.sidebarRow
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Tokens.Metric.settingsSegmentWidth),
            heightAnchor.constraint(equalToConstant: Tokens.Metric.urlPill.height),
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
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
        if isSelected, glass == nil {
            glass = Glass.apply(.control, to: self, cornerRadius: Tokens.Metric.urlPill.cornerRadius)
        }
        glass?.alphaValue = isSelected ? 1 : 0
        label.textColor = isSelected || isHovering ? Tokens.Text.primary : Tokens.Text.secondary
        setAccessibilityValue(isSelected)
        needsDisplay = true
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        guard let layer else { return }
        layer.borderWidth = Tokens.Metric.hairline
        layer.borderColor = Tokens.Line.border.cgColor
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
