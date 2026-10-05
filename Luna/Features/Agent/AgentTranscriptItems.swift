//
//  AgentTranscriptItems.swift
//  Luna
//
//  The pieces `AgentTranscriptView` stacks: the user's bubble, the agent's
//  paragraph, a card of steps, a note when something went wrong, the
//  shimmering line while it thinks, and the turn's clock. Each draws with the
//  same washes as the rest of Luna's chrome — `Surface.selected` for what the
//  user said, `Surface.hover` for what the agent did — rather than colours
//  of its own.
//

import AppKit

/// The user's message: a bubble on the trailing side.
@MainActor
final class AgentBubble: NSView {

    private let label = NSTextField(wrappingLabelWithString: "")
    private let fill = NSView()
    /// Astro's lavender to ice across the bubble, over the selected wash.
    private let tint = CAGradientLayer()

    var text = "" {
        didSet { if text != oldValue { label.stringValue = text } }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        fill.wantsLayer = true
        fill.layer?.cornerRadius = Tokens.Metric.agentBubbleRadius
        fill.layer?.cornerCurve = .continuous
        fill.layer?.masksToBounds = true
        tint.startPoint = CGPoint(x: 0, y: 1)
        tint.endPoint = CGPoint(x: 1, y: 0)
        tint.zPosition = -1
        fill.layer?.addSublayer(tint)
        fill.translatesAutoresizingMaskIntoConstraints = false
        addSubview(fill)
        label.font = Tokens.TypeScale.agentBody
        label.textColor = Tokens.Text.primary
        label.isSelectable = true
        label.translatesAutoresizingMaskIntoConstraints = false
        fill.addSubview(label)
        let pad = Tokens.Metric.chromeGap + 5
        NSLayoutConstraint.activate([
            fill.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            fill.bottomAnchor.constraint(equalTo: bottomAnchor),
            fill.trailingAnchor.constraint(equalTo: trailingAnchor),
            fill.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor),
            fill.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, multiplier: Tokens.Metric.agentBubbleShare),
            label.topAnchor.constraint(equalTo: fill.topAnchor, constant: Tokens.Metric.chromeGap + 1),
            label.bottomAnchor.constraint(equalTo: fill.bottomAnchor, constant: -(Tokens.Metric.chromeGap + 1)),
            label.leadingAnchor.constraint(equalTo: fill.leadingAnchor, constant: pad),
            label.trailingAnchor.constraint(equalTo: fill.trailingAnchor, constant: -pad)
        ])
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    override func layout() {
        super.layout()
        label.preferredMaxLayoutWidth = max(bounds.width * Tokens.Metric.agentBubbleShare - 2 * (Tokens.Metric.chromeGap + 5), 40)
        Tokens.Motion.immediately { tint.frame = fill.bounds }
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let alpha = Tokens.Astro.bubbleAlpha(dark: dark)
        fill.layer?.backgroundColor = Tokens.Surface.hover.cgColor
        tint.colors = [Tokens.Astro.from.withAlphaComponent(alpha).cgColor, Tokens.Astro.to.withAlphaComponent(alpha * 0.8).cgColor]
        fill.layer?.borderColor = Tokens.Astro.from.withAlphaComponent(alpha * 0.9).cgColor
        fill.layer?.borderWidth = Tokens.Metric.hairline
    }
}

/// The agent's words, set from the Markdown it writes (`AgentMarkdown`).
@MainActor
final class AgentParagraph: NSView {

    private let label = NSTextField(wrappingLabelWithString: "")

    var markdown = "" {
        didSet { if markdown != oldValue { render() } }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        label.isSelectable = true
        label.allowsEditingTextAttributes = true
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor),
            label.bottomAnchor.constraint(equalTo: bottomAnchor),
            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            label.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    override func layout() {
        super.layout()
        label.preferredMaxLayoutWidth = max(bounds.width, 40)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        render()
    }

    private func render() {
        label.attributedStringValue = AgentMarkdown.render(markdown)
    }
}

/// A run of steps the agent took in Luna, as one card: each step's glyph,
/// what it was, and at the end a spinner while it runs, a tick when it is
/// done or a mark when it failed.
@MainActor
final class AgentStepsCard: NSView {

    struct Step: Equatable {
        var id: String
        var title: String
        var symbol: String
        var state: AgentTask.StepState
    }

    private let rows = NSStackView()
    private var shown: [Step] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = Tokens.Metric.agentBubbleRadius - 2
        layer?.cornerCurve = .continuous
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 2
        rows.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rows)
        NSLayoutConstraint.activate([
            rows.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            rows.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            rows.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            rows.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = Tokens.Surface.hover.cgColor
        // A hint of Astro's lavender in the rim: the card is the agent's doing.
        layer?.borderColor = Tokens.Astro.from.withAlphaComponent(0.28).cgColor
        layer?.borderWidth = Tokens.Metric.hairline
    }

    func show(_ steps: [Step]) {
        guard steps != shown else { return }
        while rows.arrangedSubviews.count > steps.count { rows.arrangedSubviews.last?.removeFromSuperview() }
        while rows.arrangedSubviews.count < steps.count {
            let row = AgentStepRow()
            rows.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: rows.widthAnchor).isActive = true
        }
        for (row, step) in zip(rows.arrangedSubviews.compactMap { $0 as? AgentStepRow }, steps) { row.show(step) }
        shown = steps
    }
}

@MainActor
final class AgentStepRow: NSView {

    private let glyph = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let spinner = NSProgressIndicator()
    private let mark = NSImageView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        glyph.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: Tokens.Metric.agentStepGlyph, weight: .medium)
        mark.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: Tokens.Metric.agentStepGlyph - 2, weight: .semibold)
        label.font = Tokens.TypeScale.agentStep
        label.lineBreakMode = .byTruncatingTail
        spinner.style = .spinning
        spinner.controlSize = .mini
        spinner.isDisplayedWhenStopped = false
        for view in [glyph, label, spinner, mark] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        let box = Tokens.Metric.agentStepGlyph + 8
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 24),
            glyph.leadingAnchor.constraint(equalTo: leadingAnchor),
            glyph.centerYAnchor.constraint(equalTo: centerYAnchor),
            glyph.widthAnchor.constraint(equalToConstant: box),
            label.leadingAnchor.constraint(equalTo: glyph.trailingAnchor, constant: 4),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: spinner.leadingAnchor, constant: -6),
            spinner.trailingAnchor.constraint(equalTo: trailingAnchor),
            spinner.centerYAnchor.constraint(equalTo: centerYAnchor),
            mark.centerXAnchor.constraint(equalTo: spinner.centerXAnchor),
            mark.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    func show(_ step: AgentStepsCard.Step) {
        label.stringValue = step.title
        label.toolTip = step.title
        glyph.image = NSImage(systemSymbolName: step.symbol, accessibilityDescription: nil)
        let running = step.state == .running
        label.textColor = running ? Tokens.Text.primary : Tokens.Text.secondary
        glyph.contentTintColor = running ? Tokens.Text.primary : Tokens.Text.secondary
        if running { spinner.startAnimation(nil) } else { spinner.stopAnimation(nil) }
        mark.isHidden = running
        switch step.state {
        case .running: mark.image = nil
        case .done:
            mark.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: String(localized: "Done"))
            mark.contentTintColor = Tokens.Text.tertiary
        case .failed:
            mark.image = NSImage(systemSymbolName: "exclamationmark", accessibilityDescription: String(localized: "Failed"))
            mark.contentTintColor = Tokens.Accent.danger
        }
    }
}

/// Something gone wrong that is not the agent's to say, on a faint red wash.
@MainActor
final class AgentNote: NSView {

    private let glyph = NSImageView()
    private let label = NSTextField(wrappingLabelWithString: "")

    var text = "" {
        didSet { if text != oldValue { label.stringValue = text } }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = Tokens.Metric.agentBubbleRadius - 2
        layer?.cornerCurve = .continuous
        glyph.image = NSImage(systemSymbolName: "exclamationmark.circle.fill", accessibilityDescription: nil)
        glyph.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: Tokens.Metric.agentStepGlyph + 1, weight: .medium)
        glyph.contentTintColor = Tokens.Accent.danger
        label.font = Tokens.TypeScale.agentStep
        label.textColor = Tokens.Text.primary
        for view in [glyph, label] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            glyph.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            glyph.topAnchor.constraint(equalTo: topAnchor, constant: 9),
            label.leadingAnchor.constraint(equalTo: glyph.trailingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8)
        ])
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    override func layout() {
        super.layout()
        label.preferredMaxLayoutWidth = max(bounds.width - 44, 40)
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = Tokens.Accent.danger.withAlphaComponent(0.10).cgColor
    }
}

/// "Thinking", with a light passing across the words while the agent works
/// out what to do and has not yet said or done anything to show for it.
@MainActor
final class AgentThinkingLine: NSView {

    private let face = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let shine = CAGradientLayer()

    var text = "" {
        didSet { if text != oldValue { label.stringValue = text } }
    }

    /// What the line says for `task`, or nil when there is nothing to say:
    /// the agent is writing, a step's own spinner is turning, or the turn is over.
    static func words(for task: AgentTask) -> String? {
        guard task.status.isRunning else { return nil }
        let busy = task.items.contains { item in
            switch item {
            case .step(_, _, _, .running), .text(_, _, true): true
            default: false
            }
        }
        guard !busy else { return nil }
        return task.status == .starting ? String(localized: "Getting ready…") : String(localized: "Thinking…")
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        face.image = AgentGlyph.image(pointSize: Tokens.Metric.agentStepGlyph + 3)
        label.font = Tokens.TypeScale.agentStep
        label.textColor = Tokens.Text.secondary
        label.wantsLayer = true
        for view in [face, label] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 24),
            face.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            face.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(equalTo: face.trailingAnchor, constant: 8),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        // The light: the words' own ink, dimmed but for a band that sweeps across.
        shine.colors = [NSColor(white: 1, alpha: 0.4).cgColor, NSColor.white.cgColor, NSColor(white: 1, alpha: 0.4).cgColor]
        shine.startPoint = CGPoint(x: 0, y: 0.5)
        shine.endPoint = CGPoint(x: 1, y: 0.5)
        shine.locations = [0, 0.15, 0.3]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    override func layout() {
        super.layout()
        Tokens.Motion.immediately {
            shine.frame = label.bounds
            label.layer?.mask = Tokens.Motion.reduceMotion ? nil : shine
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        shine.removeAllAnimations()
        guard window != nil, !Tokens.Motion.reduceMotion else { return }
        let sweep = CABasicAnimation(keyPath: "locations")
        sweep.fromValue = [-0.3, -0.15, 0]
        sweep.toValue = [1, 1.15, 1.3]
        sweep.duration = 1.6
        sweep.repeatCount = .infinity
        shine.add(sweep, forKey: "sweep")
    }
}

/// "Worked for 13 s" above the agent's answer, with a hairline running on
/// from the words to the column's edge.
@MainActor
final class AgentWorkingLine: NSView {

    private let label = NSTextField(labelWithString: "")
    private let rule = NSView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        label.font = Tokens.TypeScale.agentStatus
        label.textColor = Tokens.Text.tertiary
        rule.wantsLayer = true
        for view in [label, rule] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            rule.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 8),
            rule.trailingAnchor.constraint(equalTo: trailingAnchor),
            rule.centerYAnchor.constraint(equalTo: label.centerYAnchor),
            rule.heightAnchor.constraint(equalToConstant: Tokens.Metric.hairline)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        rule.layer?.backgroundColor = Tokens.Line.hairline.cgColor
    }

    func show(_ task: AgentTask) {
        let seconds = Int(task.status.isRunning ? Date().timeIntervalSince(task.turnStartedAt) : task.lastTurn ?? 0)
        let span = Self.span(seconds)
        label.stringValue = task.status.isRunning
            ? String(localized: "Working for \(span)") : String(localized: "Worked for \(span)")
    }

    static func span(_ seconds: Int) -> String {
        seconds < 60 ? "\(seconds) s" : "\(seconds / 60) min \(seconds % 60) s"
    }
}
