//
//  AgentMenus.swift
//  Luna
//
//  The agent panel's two pop-outs: History, behind the clock, and the
//  panel's own, behind ⋯. Glass pop-outs standing on their buttons, as every
//  other surface a chrome glyph opens is (`SiteSettingsPanel`) — not
//  `NSMenu`s, which cannot hold the model switch and look like they came
//  from another app.
//

import AppKit

@MainActor
enum AgentMenus {

    static let controller: SiteSettingsController = {
        let controller = SiteSettingsController()
        controller.label = String(localized: "Astro")
        return controller
    }()

    /// Earlier tasks this launch, newest first, under New Task.
    static func history(_ center: AgentCenter, newTask: @escaping () -> Void) -> SiteSettingsContent {
        var content = SiteSettingsContent(heading: String(localized: "Tasks"))
        content.symbol = "clock.arrow.circlepath"
        let fresh = SiteSettingsContent.Action(title: String(localized: "New Task"), symbol: "plus.bubble", run: newTask)
        let earlier = center.tasks.prefix(12).map { task in
            SiteSettingsContent.Action(title: task.title, symbol: symbol(for: task, current: task === center.current)) {
                center.show(task)
            }
        }
        content.actions = [[fresh], Array(earlier)]
        return content
    }

    /// A task's glyph: under way, done, stopped or gone wrong; the one on
    /// show is the filled one.
    static func symbol(for task: AgentTask, current: Bool) -> String {
        switch task.status {
        case .starting, .thinking, .working: "ellipsis.bubble" + (current ? ".fill" : "")
        case .done: "checkmark.circle" + (current ? ".fill" : "")
        case .stopped: "stop.circle" + (current ? ".fill" : "")
        case .failed: "exclamationmark.circle" + (current ? ".fill" : "")
        }
    }

    /// The model, then what can be done to the task on show, then the panel.
    /// New Task is not here: it has a button of its own beside this one.
    static func more(
        _ center: AgentCenter, revealFolder: @escaping (AgentTask) -> Void, hide: @escaping () -> Void
    ) -> SiteSettingsContent {
        var content = SiteSettingsContent(heading: center.current?.title ?? String(localized: "Astro"))
        content.symbol = "sparkles"
        let engines = AgentEngine.allCases
        let choice = SettingsChoice(labels: engines.map(\.name), inset: Tokens.Metric.chromeGap)
        choice.selectedIndex = engines.firstIndex(of: AgentEngine.chosen) ?? 0
        choice.onSelect = { center.use(engines[$0]) }
        content.controls = [[.init(title: String(localized: "Runs on"), symbol: "cpu", view: choice)]]
        var task: [SiteSettingsContent.Action] = []
        if let current = center.current {
            if current.status.isRunning {
                task.append(.init(title: String(localized: "Stop"), symbol: "stop.circle") { center.stop() })
            }
            task.append(.init(title: String(localized: "Show Its Folder"), symbol: "folder") { revealFolder(current) })
        }
        let panel: [SiteSettingsContent.Action] = [
            .init(title: String(localized: "Astro Settings…"), symbol: "gearshape") {
                (NSApp.delegate as? AppDelegate)?.showSettings(section: AstroSection.id)
            },
            .init(title: String(localized: "Hide Astro"), symbol: "sidebar.trailing", run: hide)
        ]
        content.actions = [task, panel].filter { !$0.isEmpty }
        return content
    }

    /// On its button, the edge nearer the panel's side lined up with the
    /// button's, so the pop-out stays inside the panel rather than over the page.
    static func show(_ content: SiteSettingsContent, from anchor: NSView, trailing: Bool = false) {
        guard let window = anchor.window else { return }
        if trailing { controller.alignsTrailingEdgeTo = anchor } else { controller.alignsLeadingEdgeTo = anchor }
        controller.toggle(in: window, from: anchor, edge: .below, content: content)
    }
}
