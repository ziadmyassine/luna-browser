//
//  SettingsSearchField.swift
//  Luna
//
//  §2's search, as the reference draws it: a rounded-rectangle well with a
//  magnifier in it, sitting above the section list rather than in a title bar.
//
//  **Not `NSSearchField`.** The stock control brings a bezel, a focus ring and
//  a system-blue selection that belong to a form, not to a piece of chrome —
//  it read as an inspector field dropped into Luna's sidebar. This is the same
//  pill `HistoryFilterField` draws, with the same tokens, so the two search
//  fields in the app are the same object twice rather than two near-misses.
//

import AppKit

@MainActor
final class SettingsSearchField: NSView, NSTextFieldDelegate {

    var onChange: ((String) -> Void)?

    var stringValue: String { field.stringValue }

    private let field = NSTextField()
    private let glyph = NSImageView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerCurve = .continuous

        glyph.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)
        glyph.symbolConfiguration = NSImage.SymbolConfiguration(
            pointSize: Tokens.Metric.faviconSize,
            weight: .regular
        )
        glyph.translatesAutoresizingMaskIntoConstraints = false

        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.delegate = self
        field.translatesAutoresizingMaskIntoConstraints = false

        addSubview(glyph)
        addSubview(field)
        let inset = Tokens.Metric.pillTextInset
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: SettingsMetrics.searchHeight),
            glyph.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            glyph.centerYAnchor.constraint(equalTo: centerYAnchor),
            field.leadingAnchor.constraint(equalTo: glyph.trailingAnchor, constant: Tokens.Metric.chromeGap),
            field.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            field.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        setAccessibilityLabel(String(localized: "Search settings"))
        applyTokens()
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(accessibilityDisplayOptionsChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    @objc private func accessibilityDisplayOptionsChanged() {
        applyTokens()
    }

    private func applyTokens() {
        field.font = Tokens.TypeScale.settingsRow
        field.textColor = Tokens.Text.primary
        glyph.contentTintColor = Tokens.Text.tertiary
        field.placeholderAttributedString = NSAttributedString(
            string: String(localized: "Search settings…"),
            attributes: [
                .font: Tokens.TypeScale.settingsRow,
                .foregroundColor: Tokens.Text.tertiary
            ]
        )
        needsDisplay = true
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        guard let layer else { return }
        // **A rounded rectangle, not a pill.** The reference's field is the
        // same corner as the capsule across the divider and as the selected
        // row under it, so the column reads as one shape repeated at three
        // sizes. A half-height radius made it a lozenge floating over a list
        // of squares.
        layer.cornerRadius = SettingsMetrics.fieldCorner
        layer.backgroundColor = Tokens.Surface.well.cgColor
        // No border. The well is already a recess; outlining it as well drew
        // the eye to the field before the list, which is the wrong order — the
        // field is how you get out of a nine-section list, not the first thing
        // in it.
        layer.borderWidth = 0
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyTokens()
    }

    /// Clicking anywhere in the pill puts the caret in the field, not only the
    /// run of text inside it.
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(field)
    }

    override func becomeFirstResponder() -> Bool {
        window?.makeFirstResponder(field) ?? false
    }

    func controlTextDidChange(_ notification: Notification) {
        onChange?(field.stringValue)
    }
}
