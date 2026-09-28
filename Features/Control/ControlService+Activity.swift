//
//  ControlService+Activity.swift
//  Luna
//
//  The activity pills in the page's corner, one per agent session at work,
//  and the list each opens: every call goes in when it starts and is marked
//  when it ends.
//

import AppKit
import LunaControl

extension ControlService {

    func beginActivity(_ command: ControlCommand, by client: ControlClient) -> UUID {
        let entry = ControlActivity.entry(
            for: command, agent: client.session, client: client.displayName, appID: appID(of: client.session)
        )
        activity.insert(entry, at: 0)
        if activity.count > ControlActivity.kept { activity.removeLast(activity.count - ControlActivity.kept) }
        activityDidChange()
        return entry.id
    }

    func endActivity(_ id: UUID, as record: ControlAudit.Record) {
        guard let index = activity.firstIndex(where: { $0.id == id }) else { return activityDidChange() }
        activity[index].state = ControlActivity.state(decision: record.decision, outcome: record.outcome)
        activity[index].site = record.site
        let agent = activity[index].agent
        activityLingers.insert(agent)
        activityLinger[agent]?.cancel()
        activityLinger[agent] = Task { [weak self] in
            try? await Task.sleep(for: Self.tabLinger)
            guard !Task.isCancelled, let self else { return }
            activityLingers.remove(agent)
            activityLinger[agent] = nil
            refreshSurface()
        }
        activityDidChange()
    }

    /// A pill per session that is at work, has just been, or has its list
    /// open — the list stands on its pill, so the pill stays under it. The
    /// session that started first stands lowest, so a pill keeps its place
    /// while the others come and go.
    var shownActivity: [ControlActivity.Shown] {
        var newest: [String: ControlActivity.Entry] = [:]
        var first: [String: Int] = [:]
        for (index, entry) in activity.enumerated() {
            if newest[entry.agent] == nil { newest[entry.agent] = entry }
            first[entry.agent] = index
        }
        return newest.values
            .filter { activityIsWorking($0.agent) || activityList.agent == $0.agent && activityList.isPresented }
            .sorted { first[$0.agent, default: 0] > first[$1.agent, default: 0] }
            .map { ControlActivity.Shown(entry: $0, name: activityName(of: $0.agent), working: activityIsWorking($0.agent)) }
    }

    /// A call of the session's is running or has just ended: the rim's
    /// spark runs.
    func activityIsWorking(_ agent: String) -> Bool {
        activityLingers.contains(agent) || activity.contains { $0.agent == agent && $0.state == .running }
    }

    /// What the pill and the list call a session: its folder's name, which
    /// is what the user finds its tabs under.
    func activityName(of agent: String) -> String {
        folders[agent].flatMap { session?.group($0)?.name }
            ?? agents[agent]?.sessionName
            ?? displayName(of: agent)
    }

    private func activityDidChange() {
        refreshSurface()
        activityList.reload()
    }

    func toggleActivityList(of agent: String, from pill: NSView) {
        guard let window = pill.window else { return }
        if activityList.isPresented {
            activityList.dismiss()
            return
        }
        activityList.agent = agent
        activityList.present(in: window, from: pill)
    }
}
