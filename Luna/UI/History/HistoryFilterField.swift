//
//  HistoryFilterField.swift
//  Luna
//
//  §6.4's filter, and the keys the panel routes through it.
//
//  Split out of `HistoryRow.swift` when that file crossed SwiftLint's 400-line
//  limit. It was the half with its own subject: everything else in there is a
//  row — what one is made of, and how the time on it is written — and this is
//  the thing above them all that narrows the list.
//
//  The field has focus for as long as the pop-out is up, so it is where ↓/↑/↩
//  arrive; it hands each of them down to the list, which is what they mean.
//

import AppKit

/// §6.4's filter. §3.2's pill shape, because it is the same gesture: a recess
/// in the surface with a hairline on its edge.
@MainActor
final class HistoryFilterField: NSView, NSTextFieldDelegate {

    var onChange: ((String) -> Void)?
    /// `esc` with nothing typed — the panel takes it as "close".
    var onCancel: (() -> Void)?
    /// `↓` / `↑`. The field has focus, so it is where they land.
    var onMoveSelection: ((Int) -> Void)?
    /// `↩` on the highlighted row.
    var onCommit: (() -> Void)?

    private let field = NSTextField()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerCurve = .continuous

        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.delegate = self
        field.translatesAutoresizingMaskIntoConstraints = false
        addSubview(field)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: Tokens.Metric.urlPill.height),
            field.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Tokens.Metric.pillTextInset),
            field.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Tokens.Metric.pillTextInset),
            field.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

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
        field.font = Tokens.TypeScale.urlPill
        field.textColor = Tokens.Text.primary
        field.placeholderAttributedString = NSAttributedString(
            string: String(localized: "Search history"),
            attributes: [
                .font: Tokens.TypeScale.urlPill,
                .foregroundColor: Tokens.Text.tertiary
            ]
        )
        needsDisplay = true
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        guard let layer else { return }
        layer.cornerRadius = Tokens.Metric.urlPill.cornerRadius
        layer.backgroundColor = Tokens.Surface.well.cgColor
        layer.borderWidth = Tokens.Metric.hairline
        layer.borderColor = Tokens.Line.border.cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyTokens()
    }

    /// Clicking anywhere in the pill puts the caret in the field, not just the
    /// 13 pt of text inside it.
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(field)
    }

    override func becomeFirstResponder() -> Bool {
        window?.makeFirstResponder(field) ?? false
    }

    func controlTextDidChange(_ notification: Notification) {
        onChange?(field.stringValue)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.moveDown(_:)):
            onMoveSelection?(1)
        case #selector(NSResponder.moveUp(_:)):
            onMoveSelection?(-1)
        case #selector(NSResponder.insertNewline(_:)):
            onCommit?()
        case #selector(NSResponder.cancelOperation(_:)):
            // The query first, the panel second: `esc` on a filtered list means
            // "show me everything again", and only then "close".
            guard field.stringValue.isEmpty else {
                field.stringValue = ""
                onChange?("")
                return true
            }
            onCancel?()
        default:
            return false
        }
        return true
    }
}
