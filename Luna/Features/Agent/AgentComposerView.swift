//
//  AgentComposerView.swift
//  Luna
//
//  Where the user writes to the agent: a capsule with a field and one round
//  button at its end — send while there is something to send, Stop while the
//  agent works and the field is empty. Return sends.
//

import AppKit

@MainActor
final class AgentComposerView: NSView, NSTextFieldDelegate {

    var onSend: ((String) -> Void)?
    var onStop: (() -> Void)?

    var isRunning = false { didSet { if isRunning != oldValue { refresh() } } }
    var isEnabled = true { didSet { if isEnabled != oldValue { refresh() } } }

    private let field = NSTextField()
    private let button = GlassButton(
        shape: Tokens.Metric.controlCircle, symbolName: "arrow.up",
        pointSize: Tokens.Metric.agentStepGlyph + 1, label: String(localized: "Send")
    )

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        Glass.apply(.control, to: self, cornerRadius: Tokens.Metric.agentComposerHeight / 2)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = Tokens.TypeScale.agentBody
        field.delegate = self
        field.cell?.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.translatesAutoresizingMaskIntoConstraints = false
        button.translatesAutoresizingMaskIntoConstraints = false
        button.onActivate = { [weak self] in self?.press() }
        addSubview(field)
        addSubview(button)
        let circle = Tokens.Metric.controlCircle
        let end = (Tokens.Metric.agentComposerHeight - circle.height) / 2
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Tokens.Metric.pillTextInset + 4),
            field.centerYAnchor.constraint(equalTo: centerYAnchor),
            field.trailingAnchor.constraint(equalTo: button.leadingAnchor, constant: -Tokens.Metric.chromeGap),
            button.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -end),
            button.centerYAnchor.constraint(equalTo: centerYAnchor),
            button.widthAnchor.constraint(equalToConstant: circle.width),
            button.heightAnchor.constraint(equalToConstant: circle.height)
        ])
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    func focus() {
        window?.makeFirstResponder(field)
    }

    /// What the field holds — for the Command Bar's "Ask your agent", which
    /// arrives with its text already written.
    var text: String {
        get { field.stringValue }
        set {
            field.stringValue = newValue
            refresh()
        }
    }

    private var hasText: Bool { !field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private func refresh() {
        field.isEnabled = isEnabled
        field.placeholderString = isRunning
            ? String(localized: "Tell it more while it works…") : String(localized: "Ask your agent to do something…")
        let stops = isRunning && !hasText
        button.setSymbol(stops ? "stop.fill" : "arrow.up")
        button.setAccessibilityLabel(stops ? String(localized: "Stop") : String(localized: "Send"))
        button.isEnabled = isEnabled && (stops || hasText)
    }

    private func press() {
        guard hasText else {
            if isRunning { onStop?() }
            return
        }
        let text = field.stringValue
        field.stringValue = ""
        onSend?(text)
        refresh()
    }

    func controlTextDidChange(_ notification: Notification) {
        refresh()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard selector == #selector(NSResponder.insertNewline(_:)) else { return false }
        press()
        return true
    }
}
