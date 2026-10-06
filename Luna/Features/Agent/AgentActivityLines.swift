//
//  AgentActivityLines.swift
//  Luna
//
//  The two lines in Astro's conversation that are about the turn rather
//  than in it: what Astro is doing while it runs, and how long it took.
//

import AppKit

/// What Astro is doing while a turn runs, at the foot of the conversation:
/// a small live Astro in the mood for it, and the words with a light passing
/// across them — thinking, working in Luna, writing, or waiting on the user.
@MainActor
final class AgentThinkingLine: NSView {

    struct Activity: Equatable {
        var words: String
        var mood: AgentRoverView.Mood
    }

    private let face = AgentRoverView()
    private let label = NSTextField(labelWithString: "")
    private let shine = CAGradientLayer()

    var activity = Activity(words: "", mood: .thinking) {
        didSet {
            guard activity != oldValue else { return }
            if activity.words != oldValue.words { swapWords() }
            face.mood = activity.mood
        }
    }

    /// What Astro is doing in `task`, or nil once the turn is over. A step
    /// the user is asked to answer (`ask_user`, `request_user`) is waiting on
    /// them; any other step is work in Luna or on the web.
    static func activity(for task: AgentTask) -> Activity? {
        guard task.status.isRunning else { return nil }
        if task.status == .starting { return Activity(words: String(localized: "Getting ready…"), mood: .thinking) }
        var stepRunning = false
        for item in task.items {
            guard case let .step(_, _, symbol, .running) = item else { continue }
            if AgentPanelView.asks(symbol) { return Activity(words: String(localized: "Waiting for you…"), mood: .waving) }
            stepRunning = true
        }
        if stepRunning { return Activity(words: String(localized: "Working…"), mood: .working) }
        if case .text(_, _, true)? = task.items.last {
            return Activity(words: String(localized: "Writing…"), mood: .writing)
        }
        return Activity(words: String(localized: "Thinking…"), mood: .thinking)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        face.mood = activity.mood
        label.font = Tokens.TypeScale.agentStep
        label.textColor = Tokens.Text.secondary
        label.wantsLayer = true
        for view in [face, label] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        let side = Tokens.Metric.agentActivityFace
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: side + 4),
            face.leadingAnchor.constraint(equalTo: leadingAnchor, constant: -2),
            face.centerYAnchor.constraint(equalTo: centerYAnchor),
            face.widthAnchor.constraint(equalToConstant: side),
            face.heightAnchor.constraint(equalToConstant: side),
            label.leadingAnchor.constraint(equalTo: face.trailingAnchor, constant: 6),
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

    /// New words cross-fade in over the old, rather than replacing them in
    /// a frame.
    private func swapWords() {
        if !Tokens.Motion.reduceMotion, window != nil {
            let fade = CATransition()
            fade.type = .fade
            fade.duration = Tokens.Motion.controlHover.duration
            label.layer?.add(fade, forKey: "words")
        }
        label.stringValue = activity.words
        needsLayout = true
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
