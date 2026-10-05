//
//  BrowserWindow+Agent.swift
//  Luna
//
//  The agent panel in one window: `⌘E` and the buttons that show and hide it,
//  and the Command Bar's "Ask your agent", which arrives with the task
//  already written.
//

import AppKit

extension BrowserWindow {

    var isAgentShown: Bool { controller.isAgentPanelShown }

    /// Shows the panel, or hides it. Showing puts the keyboard in its field.
    func toggleAgent() {
        setAgentShown(!isAgentShown)
    }

    func setAgentShown(_ shown: Bool) {
        let panel = agentPanel ?? makeAgentPanel()
        controller.setAgentPanel(panel, shown: shown)
        guard shown else { return }
        panel.focusComposer()
        AgentCenter.shared.checkAccount()
    }

    /// The Command Bar's "Ask your agent": the panel opens and the task goes
    /// straight to the agent.
    func ask(_ task: String) {
        setAgentShown(true)
        AgentCenter.shared.send(task)
    }

    private func makeAgentPanel() -> AgentPanelView {
        let panel = AgentPanelView()
        panel.onClose = { [weak self] in self?.setAgentShown(false) }
        panel.onRevealFolder = { [weak self] session in self?.revealAgentFolder(session) }
        agentPanel = panel
        return panel
    }

    /// Opens the task's folder in the sidebar and goes to its first tab.
    private func revealAgentFolder(_ session: String) {
        guard let folder = ControlService.current?.folders[session], let group = self.session.group(folder) else { return }
        self.session.setGroupCollapsed(false, forGroup: group.id)
        if let first = self.session.members(ofGroup: group.id).first { self.session.activateTab(first.id, inWindow: id) }
    }
}

extension AppDelegate {

    @objc func toggleAgentPanel(_ sender: Any?) {
        front?.toggleAgent()
    }

    /// The menu says which way the next press goes. Not in a §5.6 window: the
    /// agent works in the main session's tabs, which that window cannot show.
    func validateAgentToggle(_ item: NSMenuItem) -> Bool? {
        guard item.action == #selector(toggleAgentPanel(_:)) else { return nil }
        item.title = front?.isAgentShown == true ? String(localized: "Hide Agent") : String(localized: "Show Agent")
        return front.map { !$0.isPrivate } ?? false
    }
}
