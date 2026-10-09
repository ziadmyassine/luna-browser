//
//  AgentTranscriptView.swift
//  Luna
//
//  The conversation in the agent panel: the user's messages in a bubble on
//  the trailing side, the agent's words set from their Markdown, the steps it
//  takes in Luna gathered into one card per run of them, a line saying what
//  Astro is doing while it works, and above each turn how long it has been working. Views
//  are kept by item and updated in place, so text arriving word by word does
//  not rebuild the column; an item that is new fades and rises in.
//

import AppKit

@MainActor
final class AgentTranscriptView: NSView {

    let scrollView = NSScrollView()
    /// Where a link in the agent's words opens.
    var onOpenLink: ((URL) -> Void)?
    private let column = AgentFlippedView()
    private let stack = NSStackView()
    private var views: [String: NSView] = [:]
    /// Views already held to the column's width, so a refresh adds no second
    /// constraint to one.
    private var widthBound: Set<ObjectIdentifier> = []
    private let working = AgentWorkingLine()
    private let thinking = AgentThinkingLine()
    private let topBlur = AgentEdgeBlur(edge: .top)
    private let bottomBlur = AgentEdgeBlur(edge: .bottom)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.scrollerStyle = .overlay
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentView.drawsBackground = false
        scrollView.documentView = column
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.wantsLayer = true
        addSubview(scrollView)
        addSubview(topBlur)
        addSubview(bottomBlur)

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
            // Room at both ends for the fade, so nothing is faded at rest.
            stack.topAnchor.constraint(equalTo: column.topAnchor, constant: AgentEdgeBlur.depth),
            stack.leadingAnchor.constraint(equalTo: column.leadingAnchor, constant: inset),
            stack.trailingAnchor.constraint(equalTo: column.trailingAnchor, constant: -inset),
            stack.bottomAnchor.constraint(equalTo: column.bottomAnchor, constant: -AgentEdgeBlur.depth),
            topBlur.topAnchor.constraint(equalTo: topAnchor),
            topBlur.leadingAnchor.constraint(equalTo: leadingAnchor),
            topBlur.trailingAnchor.constraint(equalTo: trailingAnchor),
            topBlur.heightAnchor.constraint(equalToConstant: AgentEdgeBlur.depth),
            bottomBlur.bottomAnchor.constraint(equalTo: bottomAnchor),
            bottomBlur.leadingAnchor.constraint(equalTo: leadingAnchor),
            bottomBlur.trailingAnchor.constraint(equalTo: trailingAnchor),
            bottomBlur.heightAnchor.constraint(equalToConstant: AgentEdgeBlur.depth)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    override func layout() {
        super.layout()
        Tokens.Motion.immediately { scrollView.layer?.mask = AgentEdgeBlur.fadeMask(for: scrollView.bounds) }
    }

    /// Shows `task`'s conversation, or nothing.
    func show(_ task: AgentTask?) {
        let wasAtEnd = isScrolledToEnd
        let blocks = Self.blocks(task?.items ?? [])
        let ids = Set(blocks.map(\.id))
        for (id, view) in views where !ids.contains(id) {
            view.removeFromSuperview()
            views[id] = nil
            widthBound.remove(ObjectIdentifier(view))
        }
        // The turn's clock stands under the user's latest message, above
        // what the agent has said and done since.
        var arranged: [NSView] = []
        let lastUser = blocks.lastIndex { if case .user = $0 { true } else { false } } ?? -1
        for (index, block) in blocks.enumerated() {
            arranged.append(view(for: block))
            if index == lastUser, let task, task.status.isRunning || task.lastTurn != nil {
                working.show(task)
                arranged.append(working)
            }
        }
        if let task, let activity = AgentThinkingLine.activity(for: task) {
            thinking.activity = activity
            arranged.append(thinking)
        }
        arrange(arranged)
        layoutSubtreeIfNeeded()
        if wasAtEnd { scrollToEnd() }
    }

    /// Puts `arranged` in the stack in order, the new ones arriving.
    private func arrange(_ arranged: [NSView]) {
        if stack.arrangedSubviews != arranged {
            for view in stack.arrangedSubviews where !arranged.contains(view) {
                // Out of the stack's list is not out of the stack: it would
                // stay drawn where it last stood.
                stack.removeArrangedSubview(view)
                view.removeFromSuperview()
            }
            for (index, view) in arranged.enumerated() where stack.arrangedSubviews.firstIndex(of: view) != index {
                let isNew = view.superview == nil
                stack.insertArrangedSubview(view, at: index)
                if isNew { Self.arrive(view) }
            }
        }
        // A new turn stands apart from the last one.
        for (index, view) in arranged.enumerated() where index > 0 {
            let gap = view is AgentBubble ? Tokens.Metric.agentTurnGap : Tokens.Metric.agentItemGap
            if stack.customSpacing(after: arranged[index - 1]) != gap { stack.setCustomSpacing(gap, after: arranged[index - 1]) }
        }
        for view in arranged where !widthBound.contains(ObjectIdentifier(view)) {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            widthBound.insert(ObjectIdentifier(view))
        }
    }

    /// What the column shows, item by item, except that a run of steps
    /// with nothing between them is one card.
    enum Block {
        case user(id: String, text: String)
        case text(id: String, text: String)
        case steps(id: String, [AgentStepsCard.Step])
        case note(id: String, text: String)

        var id: String {
            switch self {
            case let .user(id, _), let .text(id, _), let .steps(id, _), let .note(id, _): id
            }
        }
    }

    static func blocks(_ items: [AgentTask.Item]) -> [Block] {
        var blocks: [Block] = []
        for item in items {
            switch item {
            case let .user(id, text): blocks.append(.user(id: id.uuidString, text: text))
            case let .text(id, text, _): blocks.append(.text(id: id.uuidString, text: text))
            case let .note(id, text): blocks.append(.note(id: id.uuidString, text: text))
            case let .step(id, title, symbol, state):
                let step = AgentStepsCard.Step(id: id, title: title, symbol: symbol, state: state)
                if case let .steps(first, steps)? = blocks.last {
                    blocks[blocks.count - 1] = .steps(id: first, steps + [step])
                } else {
                    blocks.append(.steps(id: "steps-" + id, [step]))
                }
            }
        }
        return blocks
    }

    private func view(for block: Block) -> NSView {
        let existing = views[block.id]
        switch block {
        case let .user(id, text):
            let bubble = existing as? AgentBubble ?? AgentBubble()
            bubble.text = text
            return remember(bubble, id)
        case let .text(id, text):
            let paragraph = existing as? AgentParagraph ?? AgentParagraph()
            paragraph.onOpenLink = { [weak self] url in self?.onOpenLink?(url) }
            paragraph.markdown = text
            return remember(paragraph, id)
        case let .steps(id, steps):
            let card = existing as? AgentStepsCard ?? AgentStepsCard()
            card.show(steps)
            return remember(card, id)
        case let .note(id, text):
            let note = existing as? AgentNote ?? AgentNote()
            note.text = text
            return remember(note, id)
        }
    }

    /// A new item fades in and rises the few points it has to travel, so the
    /// conversation grows rather than jumps.
    private static func arrive(_ view: NSView) {
        guard !Tokens.Motion.reduceMotion else { return }
        view.wantsLayer = true
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        let rise = CABasicAnimation(keyPath: "transform.translation.y")
        rise.fromValue = -6
        rise.toValue = 0
        let group = CAAnimationGroup()
        group.animations = [fade, rise]
        group.duration = Tokens.Motion.controlHover.duration * 1.5
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        view.layer?.add(group, forKey: "arrive")
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
