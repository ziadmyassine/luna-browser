//
//  AgentTranscriptItems.swift
//  Luna
//
//  The pieces `AgentTranscriptView` stacks: the user's bubble, the agent's
//  paragraph, a card of steps and a note when something went wrong; the
//  lines about the turn itself are in `AgentActivityLines.swift`. The bubble
//  and the cards are Liquid Glass, as Luna's other raised surfaces are, with
//  a breath of Astro's lavender over the bubble and in the cards' rims.
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
        // Under the lavender, which is added first and so stays above it.
        Glass.apply(.control, to: fill, cornerRadius: Tokens.Metric.agentBubbleRadius)
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
        let alpha = Tokens.Astro.bubbleAlpha(dark: dark) * 0.7
        tint.colors = [Tokens.Astro.from.withAlphaComponent(alpha).cgColor, Tokens.Astro.to.withAlphaComponent(alpha * 0.8).cgColor]
        fill.layer?.borderColor = Tokens.Astro.from.withAlphaComponent(alpha * 0.9).cgColor
        fill.layer?.borderWidth = Tokens.Metric.hairline
    }
}

/// The agent's words, set from the Markdown it writes (`AgentMarkdown`):
/// prose as text, a table as a grid, code in a box of its own.
@MainActor
final class AgentParagraph: NSView {

    private let blocks = NSStackView()

    var markdown = "" {
        didSet { if markdown != oldValue { render() } }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        blocks.orientation = .vertical
        blocks.alignment = .leading
        blocks.spacing = Tokens.Metric.agentItemGap
        blocks.translatesAutoresizingMaskIntoConstraints = false
        addSubview(blocks)
        NSLayoutConstraint.activate([
            blocks.topAnchor.constraint(equalTo: topAnchor),
            blocks.bottomAnchor.constraint(equalTo: bottomAnchor),
            blocks.leadingAnchor.constraint(equalTo: leadingAnchor),
            blocks.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    override func layout() {
        super.layout()
        for case let label as NSTextField in blocks.arrangedSubviews { label.preferredMaxLayoutWidth = max(bounds.width, 40) }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        render()
    }

    /// Text that is still arriving keeps its label, so a paragraph growing
    /// word by word is one view changing, not a column being rebuilt; a
    /// table or code box is made again only when it changes.
    private func render() {
        let segments = AgentMarkdown.segments(markdown)
        var views: [NSView] = []
        for (index, segment) in segments.enumerated() {
            let existing = blocks.arrangedSubviews[safe: index]
            switch segment {
            case let .text(text):
                let label = existing as? NSTextField ?? Self.label()
                label.attributedStringValue = text
                views.append(label)
            case let .quote(text):
                views.append(AgentQuoteView(text))
            case let .table(table):
                views.append(AgentTableView(table))
            case let .code(code):
                views.append(AgentCodeView(code))
            }
        }
        for view in blocks.arrangedSubviews where !views.contains(view) {
            blocks.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        for (index, view) in views.enumerated() where blocks.arrangedSubviews[safe: index] !== view {
            blocks.insertArrangedSubview(view, at: index)
            view.widthAnchor.constraint(equalTo: blocks.widthAnchor).isActive = true
        }
        needsLayout = true
    }

    private static func label() -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: "")
        label.isSelectable = true
        label.allowsEditingTextAttributes = true
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
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
        Glass.apply(.control, to: self, cornerRadius: Tokens.Metric.agentBubbleRadius - 2)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
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
