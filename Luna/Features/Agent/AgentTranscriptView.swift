//
//  AgentTranscriptView.swift
//  Luna
//
//  The conversation in the agent panel: the user's messages in a bubble on
//  the trailing side, the agent's words as plain paragraphs, each step it
//  takes in Luna as a quiet line with its glyph, and above each turn how long
//  it has been working. Views are kept by item and updated in place, so text
//  arriving word by word does not rebuild the column.
//

import AppKit

@MainActor
final class AgentTranscriptView: NSView {

    let scrollView = NSScrollView()
    private let column = AgentFlippedView()
    private let stack = NSStackView()
    private var views: [String: NSView] = [:]
    /// Views already held to the column's width, so a refresh adds no second
    /// constraint to one.
    private var widthBound: Set<ObjectIdentifier> = []
    private let working = AgentWorkingLine()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.scrollerStyle = .overlay
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentView.drawsBackground = false
        scrollView.documentView = column
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = Tokens.Metric.agentItemGap
        stack.translatesAutoresizingMaskIntoConstraints = false
        column.addSubview(stack)
        column.translatesAutoresizingMaskIntoConstraints = false
        let inset = Tokens.Metric.agentPanelInset
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            column.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            column.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            column.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            stack.topAnchor.constraint(equalTo: column.topAnchor, constant: Tokens.Metric.agentItemGap),
            stack.leadingAnchor.constraint(equalTo: column.leadingAnchor, constant: inset),
            stack.trailingAnchor.constraint(equalTo: column.trailingAnchor, constant: -inset),
            stack.bottomAnchor.constraint(equalTo: column.bottomAnchor, constant: -Tokens.Metric.agentItemGap)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    /// Shows `task`'s conversation, or nothing.
    func show(_ task: AgentTask?) {
        let wasAtEnd = isScrolledToEnd
        let items = task?.items ?? []
        let ids = Set(items.map(\.id))
        for (id, view) in views where !ids.contains(id) {
            view.removeFromSuperview()
            views[id] = nil
            widthBound.remove(ObjectIdentifier(view))
        }
        // The turn's clock stands under the user's latest message, above
        // what the agent has said and done since.
        var arranged: [NSView] = []
        let lastUser = items.lastIndex(where: isUser) ?? -1
        for (index, item) in items.enumerated() {
            arranged.append(view(for: item))
            if index == lastUser, let task, task.status.isRunning || task.lastTurn != nil {
                working.show(task)
                arranged.append(working)
            }
        }
        if stack.arrangedSubviews != arranged {
            for view in stack.arrangedSubviews where !arranged.contains(view) { stack.removeArrangedSubview(view) }
            for (index, view) in arranged.enumerated() { stack.insertArrangedSubview(view, at: index) }
        }
        for view in arranged where !widthBound.contains(ObjectIdentifier(view)) {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            widthBound.insert(ObjectIdentifier(view))
        }
        layoutSubtreeIfNeeded()
        if wasAtEnd { scrollToEnd() }
    }

    private func isUser(_ item: AgentTask.Item) -> Bool {
        if case .user = item { true } else { false }
    }

    private func view(for item: AgentTask.Item) -> NSView {
        let existing = views[item.id]
        switch item {
        case let .user(_, text):
            let bubble = existing as? AgentBubble ?? AgentBubble()
            bubble.text = text
            return remember(bubble, item.id)
        case let .text(_, text, _):
            let paragraph = existing as? AgentParagraph ?? AgentParagraph()
            paragraph.markdown = text
            return remember(paragraph, item.id)
        case let .step(_, title, symbol, state):
            let line = existing as? AgentStepLine ?? AgentStepLine()
            line.show(title: title, symbol: symbol, state: state)
            return remember(line, item.id)
        case let .note(_, text):
            let line = existing as? AgentStepLine ?? AgentStepLine()
            line.show(title: text, symbol: "exclamationmark.circle", state: .failed)
            return remember(line, item.id)
        }
    }

    private func remember(_ view: NSView, _ id: String) -> NSView {
        views[id] = view
        return view
    }

    /// Ticks "Working for" while a turn runs.
    func tick(_ task: AgentTask?) {
        guard let task, working.superview != nil else { return }
        working.show(task)
    }

    private var isScrolledToEnd: Bool {
        let visible = scrollView.contentView.bounds
        return visible.maxY >= column.frame.height - 24
    }

    func scrollToEnd() {
        let end = max(column.frame.height - scrollView.contentView.bounds.height, 0)
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: end))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }
}

/// A flipped column, so the conversation reads from the top.
final class AgentFlippedView: NSView {
    override var isFlipped: Bool { true }
}

// MARK: - Items

/// The user's message: a bubble on the trailing side.
@MainActor
final class AgentBubble: NSView {

    private let label = NSTextField(wrappingLabelWithString: "")
    private let fill = NSView()

    var text = "" {
        didSet { if text != oldValue { label.stringValue = text } }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        fill.wantsLayer = true
        fill.layer?.cornerRadius = Tokens.Metric.agentBubbleRadius
        fill.layer?.cornerCurve = .continuous
        fill.translatesAutoresizingMaskIntoConstraints = false
        addSubview(fill)
        label.font = Tokens.TypeScale.agentBody
        label.textColor = Tokens.Text.primary
        label.isSelectable = true
        label.translatesAutoresizingMaskIntoConstraints = false
        fill.addSubview(label)
        let pad = Tokens.Metric.chromeGap + 4
        NSLayoutConstraint.activate([
            fill.topAnchor.constraint(equalTo: topAnchor),
            fill.bottomAnchor.constraint(equalTo: bottomAnchor),
            fill.trailingAnchor.constraint(equalTo: trailingAnchor),
            fill.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor),
            fill.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, multiplier: Tokens.Metric.agentBubbleShare),
            label.topAnchor.constraint(equalTo: fill.topAnchor, constant: Tokens.Metric.chromeGap),
            label.bottomAnchor.constraint(equalTo: fill.bottomAnchor, constant: -Tokens.Metric.chromeGap),
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
        label.preferredMaxLayoutWidth = max(bounds.width * Tokens.Metric.agentBubbleShare - 2 * (Tokens.Metric.chromeGap + 4), 40)
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        fill.layer?.backgroundColor = Tokens.Surface.selected.cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

/// The agent's words, with the inline Markdown it writes in — bold, italics,
/// code and links — drawn rather than shown as asterisks.
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
        label.attributedStringValue = Self.attributed(markdown)
    }

    static func attributed(_ markdown: String) -> NSAttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        let parsed = (try? AttributedString(markdown: markdown, options: options)) ?? AttributedString(markdown)
        let result = NSMutableAttributedString()
        let body = Tokens.TypeScale.agentBody
        for run in parsed.runs {
            let text = String(parsed[run.range].characters)
            var font = body
            let intent = run.inlinePresentationIntent ?? []
            if intent.contains(.code) {
                font = .monospacedSystemFont(ofSize: body.pointSize - 1, weight: .regular)
            } else {
                var traits: NSFontDescriptor.SymbolicTraits = []
                if intent.contains(.stronglyEmphasized) { traits.insert(.bold) }
                if intent.contains(.emphasized) { traits.insert(.italic) }
                if !traits.isEmpty {
                    font = NSFont(descriptor: body.fontDescriptor.withSymbolicTraits(traits), size: body.pointSize) ?? body
                }
            }
            var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: Tokens.Text.primary]
            if let link = run.link { attributes[.link] = link }
            result.append(NSAttributedString(string: text, attributes: attributes))
        }
        return result
    }
}

/// One step the agent took, or a note: its glyph and a line saying what it was.
@MainActor
final class AgentStepLine: NSView {

    private let glyph = NSImageView()
    private let label = NSTextField(wrappingLabelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        glyph.translatesAutoresizingMaskIntoConstraints = false
        glyph.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: Tokens.Metric.agentStepGlyph, weight: .regular)
        label.font = Tokens.TypeScale.agentStep
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glyph)
        addSubview(label)
        let glyphBox = Tokens.Metric.agentStepGlyph + 4
        NSLayoutConstraint.activate([
            glyph.leadingAnchor.constraint(equalTo: leadingAnchor),
            glyph.widthAnchor.constraint(equalToConstant: glyphBox),
            glyph.firstBaselineAnchor.constraint(equalTo: label.firstBaselineAnchor),
            label.leadingAnchor.constraint(equalTo: glyph.trailingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: trailingAnchor),
            label.topAnchor.constraint(equalTo: topAnchor),
            label.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    override func layout() {
        super.layout()
        label.preferredMaxLayoutWidth = max(bounds.width - Tokens.Metric.agentStepGlyph - 10, 40)
    }

    func show(title: String, symbol: String, state: AgentTask.StepState) {
        label.stringValue = title
        glyph.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        let ink = state == .running ? Tokens.Text.secondary : Tokens.Text.tertiary
        label.textColor = ink
        glyph.contentTintColor = ink
        // A step under way breathes; one that is over holds still.
        glyph.layer?.removeAllAnimations()
        guard state == .running, !Tokens.Motion.reduceMotion else { return }
        glyph.wantsLayer = true
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1
        pulse.toValue = 0.35
        pulse.duration = 0.7
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        glyph.layer?.add(pulse, forKey: "pulse")
    }
}

/// "Working for 13 s", with a hairline under it, above the agent's answer.
@MainActor
final class AgentWorkingLine: NSView {

    private let label = NSTextField(labelWithString: "")
    private let rule = NSView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        label.font = Tokens.TypeScale.agentStatus
        label.textColor = Tokens.Text.tertiary
        label.translatesAutoresizingMaskIntoConstraints = false
        rule.wantsLayer = true
        rule.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        addSubview(rule)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            rule.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 6),
            rule.leadingAnchor.constraint(equalTo: leadingAnchor),
            rule.trailingAnchor.constraint(equalTo: trailingAnchor),
            rule.heightAnchor.constraint(equalToConstant: Tokens.Metric.hairline),
            rule.bottomAnchor.constraint(equalTo: bottomAnchor)
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
