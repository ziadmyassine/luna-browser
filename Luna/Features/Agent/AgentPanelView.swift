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
        guard let task, hasTask else {
            transcript.show(nil)
            return
        }
        titleLabel.stringValue = task.title
        statusLabel.stringValue = Self.status(of: task)
        rover.mood = Self.mood(for: task.status)
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
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(SidebarMenu.glyphItem(String(localized: "New Task"), symbol: "plus") { [weak self] in
            self?.center.newTask()
            self?.focusComposer()
        })
        let earlier = center.tasks
        if !earlier.isEmpty { menu.addItem(.separator()) }
        for task in earlier {
            let symbol = task.status.isRunning ? "circle.dotted" : "checkmark.circle"
            let item = SidebarMenu.glyphItem(task.title, symbol: symbol) { [weak self] in self?.center.show(task) }
            item.state = task === center.current ? .on : .off
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: history.bounds.maxY + 4), in: history)
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(SidebarMenu.glyphItem(String(localized: "New Task"), symbol: "plus") { [weak self] in
            self?.center.newTask()
            self?.focusComposer()
        })
        if let task = center.current {
            if task.status.isRunning {
                menu.addItem(SidebarMenu.glyphItem(String(localized: "Stop"), symbol: "stop.fill") { [weak self] in
                    self?.center.stop()
                })
            }
            menu.addItem(SidebarMenu.glyphItem(String(localized: "Show Its Folder"), symbol: "folder") { [weak self] in
                self?.onRevealFolder?(task.id.uuidString.lowercased())
            })
        }
        menu.addItem(.separator())
        for engine in AgentEngine.allCases {
            let item = SidebarMenu.glyphItem(String(localized: "Use \(engine.name)"), symbol: "sparkle") { [weak self] in
                self?.center.use(engine)
            }
            item.state = engine == AgentEngine.chosen ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(SidebarMenu.glyphItem(String(localized: "Hide Agent"), symbol: "sidebar.trailing") { [weak self] in
            self?.onClose?()
        })
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: more.bounds.maxY + 4), in: more)
    }
}
