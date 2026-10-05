//
//  AgentComposerView.swift
//  Luna
//
//  Where the user writes to the agent: a capsule with a field and one round
//  button at its end — send while there is something to send, Stop while the
//  agent works and the field is empty. Return sends. Round it runs a ring of
//  Astro's light, lavender to ice, which turns while Astro works.
//

import AppKit

@MainActor
final class AgentComposerView: NSView, NSTextFieldDelegate {

    var onSend: ((String) -> Void)?
    var onStop: (() -> Void)?

    var isRunning = false { didSet { if isRunning != oldValue { refresh() } } }
    var isEnabled = true { didSet { if isEnabled != oldValue { refresh() } } }

    private let field = NSTextField()
    private let ring = CAGradientLayer()
    private let ringShape = CAShapeLayer()
    private let button = GlassButton(
        shape: Tokens.Metric.controlCircle, symbolName: "arrow.up",
        pointSize: Tokens.Metric.agentStepGlyph + 1, label: String(localized: "Send")
    )

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        Glass.apply(.control, to: self, cornerRadius: Tokens.Metric.agentComposerHeight / 2)
        ring.type = .conic
        ring.startPoint = CGPoint(x: 0.5, y: 0.5)
        ring.endPoint = CGPoint(x: 0.5, y: 0)
        ringShape.fillColor = nil
        ringShape.strokeColor = NSColor.black.cgColor
        ringShape.lineWidth = 1.5
        ring.mask = ringShape
        ring.shadowColor = Tokens.Astro.from.cgColor
        ring.shadowRadius = 6
        ring.shadowOffset = .zero
        layer?.addSublayer(ring)
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

    override func layout() {
        super.layout()
        Tokens.Motion.immediately {
            ring.frame = bounds
            ringShape.frame = bounds
            let radius = bounds.height / 2
            ringShape.path = CGPath(roundedRect: bounds.insetBy(dx: 0.75, dy: 0.75), cornerWidth: radius - 0.75,
                                    cornerHeight: radius - 0.75, transform: nil)
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        paintRing()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        spinRing()
    }

    private func paintRing() {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let alpha = Tokens.Astro.ringAlpha(dark: dark) * (isRunning ? 1 : 0.55)
        let from = Tokens.Astro.from.withAlphaComponent(alpha).cgColor
        let to = Tokens.Astro.to.withAlphaComponent(alpha).cgColor
        ring.colors = [from, to, from]
        ring.shadowOpacity = isRunning ? 0.7 : 0
    }

    /// The light runs round the ring while Astro works.
    private func spinRing() {
        guard isRunning, window != nil, !Tokens.Motion.reduceMotion else { return ring.removeAnimation(forKey: "spin") }
        // Left running: restarting it on every keystroke made it stutter.
        guard ring.animation(forKey: "spin") == nil else { return }
        let spin = CAKeyframeAnimation(keyPath: "endPoint")
        spin.values = (0...8).map { step in
            let angle = Double(step) / 8 * 2 * .pi
            return NSValue(point: NSPoint(x: 0.5 + 0.5 * sin(angle), y: 0.5 - 0.5 * cos(angle)))
        }
        spin.duration = 3
        spin.repeatCount = .infinity
        ring.add(spin, forKey: "spin")
    }

    func focus() {
        window?.makeFirstResponder(field)
    }

    /// What the field holds — for the Command Bar's "Ask Astro", which
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
        paintRing()
        spinRing()
        field.isEnabled = isEnabled
        field.placeholderString = isRunning
            ? String(localized: "Tell it more while it works…") : String(localized: "Ask Astro to do something…")
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
