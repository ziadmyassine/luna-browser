//
//  AgentPanelView.swift
//  Luna
//
//  The agent panel: a column beside the page where the user gives Luna's
//  agent a task and watches it work. History on one side of Astro at the
//  top and New Task and a menu on the other, the task's name and what it is
//  doing under Astro, the conversation, and the field to write in — which
//  takes more while the agent works, and turns its button into Stop.
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
    private let fresh = GlassButton(
        shape: Tokens.Metric.sidebarCircle, symbolName: "square.and.pencil",
        pointSize: Tokens.Metric.glyphSize, label: String(localized: "New Task")
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
    /// The light behind the panel. Not one of its subviews: `AgentPanelHost`
    /// puts it under the page, reaching a corner's width past the panel, so
    /// the colour fills the notches the page's rounded corners leave.
    let aura = AgentAura()
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

        for view in [history, fresh, more, rover, titleCapsule, transcript, composer, empty] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        layOutHeader(titles: titles)
        layOutBody()
    }

    /// History, Astro, New Task and the menu on the line the browser's own
    /// top row is centred on — the sidebar's buttons, the page bar's — and
    /// the task's pill under Astro: its name, and what it is doing.
    private func layOutHeader(titles: NSView) {
        let inset = Tokens.Metric.agentPanelInset
        let circle = Tokens.Metric.sidebarCircle
        let capsule = Tokens.Metric.agentTitleCapsule
        let text = Tokens.Metric.pillTextInset + 4
        NSLayoutConstraint.activate([
            rover.centerYAnchor.constraint(equalTo: topAnchor, constant: Tokens.Metric.pageBar / 2),
            rover.centerXAnchor.constraint(equalTo: centerXAnchor),
            rover.widthAnchor.constraint(equalToConstant: Tokens.Metric.agentRover),
            rover.heightAnchor.constraint(equalToConstant: Tokens.Metric.agentRover),
            history.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            history.centerYAnchor.constraint(equalTo: rover.centerYAnchor),
            history.widthAnchor.constraint(equalToConstant: circle.width),
            history.heightAnchor.constraint(equalToConstant: circle.height),
            more.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            more.centerYAnchor.constraint(equalTo: rover.centerYAnchor),
            more.widthAnchor.constraint(equalToConstant: circle.width),
            more.heightAnchor.constraint(equalToConstant: circle.height),
            fresh.trailingAnchor.constraint(equalTo: more.leadingAnchor, constant: -Tokens.Metric.chromeGap),
            fresh.centerYAnchor.constraint(equalTo: rover.centerYAnchor),
            fresh.widthAnchor.constraint(equalToConstant: circle.width),
            fresh.heightAnchor.constraint(equalToConstant: circle.height),

            titleCapsule.topAnchor.constraint(equalTo: rover.bottomAnchor, constant: Tokens.Metric.chromeGap),
            titleCapsule.centerXAnchor.constraint(equalTo: centerXAnchor),
            titleCapsule.heightAnchor.constraint(equalToConstant: capsule.height),
            titleCapsule.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -2 * inset),
            titleCapsule.widthAnchor.constraint(greaterThanOrEqualToConstant: capsule.width),
            titles.centerYAnchor.constraint(equalTo: titleCapsule.centerYAnchor),
            titles.leadingAnchor.constraint(equalTo: titleCapsule.leadingAnchor, constant: text),
            titles.trailingAnchor.constraint(equalTo: titleCapsule.trailingAnchor, constant: -text)
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
        fresh.onActivate = { [weak self] in self?.startOver() }
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
        // An empty panel is already a new task.
        fresh.isHidden = !hasTask
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

    /// Astro's mood for a task: what it is doing while a turn runs
    /// (`AgentThinkingLine.activity`), else what the turn came to.
    static func mood(for task: AgentTask) -> AgentRoverView.Mood {
        AgentThinkingLine.activity(for: task)?.mood ?? mood(for: task.status)
    }

    /// Whether a step's glyph is one of a question put to the user.
    static func asks(_ symbol: String) -> Bool {
        ["hand.raised", "person.fill.questionmark"].contains(symbol)
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

    /// A clean panel with the keyboard in its field. A task still running
    /// carries on, and is in History.
    private func startOver() {
        center.newTask()
        focusComposer()
    }

    private func showHistory() {
        AgentMenus.show(AgentMenus.history(center) { [weak self] in self?.startOver() }, from: history)
    }

    private func showMenu() {
        let content = AgentMenus.more(center) { [weak self] in
            self?.startOver()
        } revealFolder: { [weak self] task in
            self?.onRevealFolder?(task.id.uuidString.lowercased())
        } hide: { [weak self] in
            self?.onClose?()
        }
        AgentMenus.show(content, from: more, trailing: true)
    }
}
