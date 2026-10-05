//
//  AgentPanelView.swift
//  Luna
//
//  The agent panel: a column beside the page where the user gives Luna's
//  agent a task and watches it work. History and a menu at the top either
//  side of the rover, the task's name and what it is doing under them, the
//  conversation, and the field to write in — which takes more while the agent
//  works, and turns its button into Stop.
//
//  It stands on the window's glass, as the sidebar does; it has no material
//  of its own. One per window, all showing `AgentCenter`'s task.
//

import AppKit
import LunaControl

@MainActor
final class AgentPanelView: NSView {

    /// The panel's own close, from its menu.
    var onClose: (() -> Void)?
    /// Shows the task's folder in the sidebar.
    var onRevealFolder: ((String) -> Void)?

    private let center = AgentCenter.shared
    private let history = GlassButton(
        shape: Tokens.Metric.sidebarCircle, symbolName: "clock.arrow.circlepath",
        pointSize: Tokens.Metric.glyphSize, label: String(localized: "Earlier tasks")
    )
    private let more = GlassButton(
        shape: Tokens.Metric.sidebarCircle, symbolName: "ellipsis",
        pointSize: Tokens.Metric.glyphSize, label: String(localized: "More")
    )
    private let rover = AgentRoverView()
    private let titleCapsule = NSView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private let transcript = AgentTranscriptView()
    private let composer = AgentComposerView()
    private let empty = AgentEmptyView()
    private let aura = AgentAura()
    private var watch: (any NSObjectProtocol)?
    private var clock: Timer?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(String(localized: "Agent"))
        build()
        wire()
        refresh()
        watch = NotificationCenter.default.addObserver(forName: AgentCenter.didChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    /// Puts the keyboard in the field, as opening the panel should.
    func focusComposer() {
        composer.focus()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        clock?.invalidate()
        clock = nil
        guard window != nil else { return }
        // "Working for 13 s" counts while a turn runs.
        clock = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.center.current?.status.isRunning == true else { return }
                self.transcript.tick(self.center.current)
            }
        }
    }

    // MARK: - Building

    private func build() {
        let inset = Tokens.Metric.agentPanelInset
        titleCapsule.wantsLayer = true
        Glass.apply(.control, to: titleCapsule, cornerRadius: Tokens.Metric.agentTitleCapsule.cornerRadius)
        titleLabel.font = Tokens.TypeScale.agentTitle
        titleLabel.textColor = Tokens.Text.primary
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.alignment = .center
        statusLabel.font = Tokens.TypeScale.agentStatus
        statusLabel.textColor = Tokens.Text.secondary
        statusLabel.alignment = .center
        let titles = NSStackView(views: [titleLabel, statusLabel])
        titles.orientation = .vertical
        titles.spacing = 0
        titles.translatesAutoresizingMaskIntoConstraints = false
        titleCapsule.addSubview(titles)

        addSubview(aura)
        NSLayoutConstraint.activate([
            aura.topAnchor.constraint(equalTo: topAnchor),
            aura.bottomAnchor.constraint(equalTo: bottomAnchor),
            aura.leadingAnchor.constraint(equalTo: leadingAnchor),
            aura.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
        for view in [history, more, rover, titleCapsule, transcript, composer, empty] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        layOutHeader(titles: titles)
        layOutBody()
    }

    /// History, the rover and the menu across the top, and the task's name under them.
    private func layOutHeader(titles: NSView) {
        let inset = Tokens.Metric.agentPanelInset
        let capsule = Tokens.Metric.agentTitleCapsule
        NSLayoutConstraint.activate([
            history.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            history.centerYAnchor.constraint(equalTo: rover.centerYAnchor),
            history.widthAnchor.constraint(equalToConstant: Tokens.Metric.sidebarCircle.width),
            history.heightAnchor.constraint(equalToConstant: Tokens.Metric.sidebarCircle.height),
            more.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            more.centerYAnchor.constraint(equalTo: rover.centerYAnchor),
            more.widthAnchor.constraint(equalToConstant: Tokens.Metric.sidebarCircle.width),
            more.heightAnchor.constraint(equalToConstant: Tokens.Metric.sidebarCircle.height),
            // On the line the browser's own top row is centred on — the
            // sidebar's buttons, the page bar's — not an inset below it.
            rover.centerYAnchor.constraint(equalTo: topAnchor, constant: Tokens.Metric.pageBar / 2),
            rover.centerXAnchor.constraint(equalTo: centerXAnchor),
            rover.widthAnchor.constraint(equalToConstant: Tokens.Metric.agentRover),
            rover.heightAnchor.constraint(equalToConstant: Tokens.Metric.agentRover),

            titleCapsule.topAnchor.constraint(equalTo: rover.bottomAnchor, constant: Tokens.Metric.chromeGap),
            titleCapsule.centerXAnchor.constraint(equalTo: centerXAnchor),
            titleCapsule.heightAnchor.constraint(equalToConstant: capsule.height),
            titleCapsule.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -2 * inset),
            titleCapsule.widthAnchor.constraint(greaterThanOrEqualToConstant: capsule.width),
            titles.centerYAnchor.constraint(equalTo: titleCapsule.centerYAnchor),
            titles.leadingAnchor.constraint(equalTo: titleCapsule.leadingAnchor, constant: Tokens.Metric.pillTextInset + 4),
            titles.trailingAnchor.constraint(equalTo: titleCapsule.trailingAnchor, constant: -(Tokens.Metric.pillTextInset + 4))
        ])
    }

    /// The conversation, or the empty panel in its place, over the field.
    private func layOutBody() {
        let inset = Tokens.Metric.agentPanelInset
        NSLayoutConstraint.activate([
            transcript.topAnchor.constraint(equalTo: titleCapsule.bottomAnchor, constant: Tokens.Metric.chromeGap),
            transcript.leadingAnchor.constraint(equalTo: leadingAnchor),
            transcript.trailingAnchor.constraint(equalTo: trailingAnchor),
            transcript.bottomAnchor.constraint(equalTo: composer.topAnchor, constant: -Tokens.Metric.chromeGap),

            empty.topAnchor.constraint(equalTo: topAnchor),
            empty.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            empty.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            empty.bottomAnchor.constraint(equalTo: composer.topAnchor),

            composer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            composer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            composer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -inset),
            composer.heightAnchor.constraint(equalToConstant: Tokens.Metric.agentComposerHeight)
        ])
    }

    private func wire() {
        history.onActivate = { [weak self] in self?.showHistory() }
        more.onActivate = { [weak self] in self?.showMenu() }
        composer.onSend = { [weak self] text in self?.center.send(text) }
        composer.onStop = { [weak self] in self?.center.stop() }
        empty.onAction = { [weak self] action in self?.perform(action) }
    }

    // MARK: - State

    private func refresh() {
        let task = center.current
        let blocker = center.blocker
        // A blocker takes the panel over even mid-task: until it is dealt
        // with, nothing written to the agent would reach it.
        let hasTask = task != nil && blocker == nil
        empty.isHidden = hasTask
        transcript.isHidden = !hasTask
        titleCapsule.isHidden = !hasTask
        rover.isHidden = !hasTask
        empty.show(blocker: blocker, engine: center.engine)
        composer.isEnabled = blocker == nil
        composer.isRunning = task?.status.isRunning ?? false
        aura.isLively = composer.isRunning
        guard let task, hasTask else {
            transcript.show(nil)
            return
        }
        titleLabel.stringValue = task.title
        statusLabel.stringValue = Self.status(of: task)
        rover.mood = Self.mood(for: task)
        transcript.show(task)
    }

    static func status(of task: AgentTask) -> String {
        switch task.status {
        case .starting: String(localized: "Getting ready")
        case .thinking: String(localized: "Thinking")
        case .working: String(localized: "Working")
        case .done: String(localized: "Done")
        case .stopped: String(localized: "Stopped")
        case .failed: String(localized: "Needs a hand")
        }
    }

    /// Astro's mood for a task: waving while a step is waiting on the user
    /// (`ask_user`, `request_user`), else what its state says.
    static func mood(for task: AgentTask) -> AgentRoverView.Mood {
        let asking = task.items.contains { item in
            if case let .step(_, _, symbol, .running) = item { ["hand.raised", "person.fill.questionmark"].contains(symbol) } else { false }
        }
        return asking ? .waving : mood(for: task.status)
    }

    static func mood(for status: AgentTask.Status) -> AgentRoverView.Mood {
        switch status {
        case .starting, .thinking: .thinking
        case .working: .working
        case .done: .happy
        case .stopped: .stopped
        case .failed: .sad
        }
    }

    private func perform(_ action: AgentEmptyView.Action) {
        switch action {
        case .turnOnControl: center.turnOnControl()
        case .signIn: center.signIn()
        case .cancelSignIn: center.cancelSignIn()
        case .reopenSignInPage: center.reopenSignInPage()
        case let .use(engine): center.use(engine)
        }
    }

    // MARK: - History and the menu

    private func showHistory() {
        AgentMenus.show(AgentMenus.history(center) { [weak self] in
            self?.center.newTask()
            self?.focusComposer()
        }, from: history)
    }

    private func showMenu() {
        let content = AgentMenus.more(center) { [weak self] in
            self?.center.newTask()
            self?.focusComposer()
        } revealFolder: { [weak self] task in
            self?.onRevealFolder?(task.id.uuidString.lowercased())
        } hide: { [weak self] in
            self?.onClose?()
        }
        AgentMenus.show(content, from: more)
    }
}
