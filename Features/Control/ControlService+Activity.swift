//
//  ControlService+Activity.swift
//  Luna
//
//  The activity pill in the page's corner and the list it opens: every call
//  an agent makes goes in when it starts and is marked when it ends.
//

import AppKit
import LunaControl

extension ControlService {

    func beginActivity(_ command: ControlCommand, by client: String) -> UUID {
        let entry = ControlActivity.entry(for: command, client: client, appID: appID(ofClient: client))
        activity.insert(entry, at: 0)
        if activity.count > ControlActivity.kept { activity.removeLast(activity.count - ControlActivity.kept) }
        activityDidChange()
        return entry.id
    }

    func endActivity(_ id: UUID, as record: ControlAudit.Record) {
        if let index = activity.firstIndex(where: { $0.id == id }) {
            activity[index].state = ControlActivity.state(decision: record.decision, outcome: record.outcome)
            activity[index].site = record.site
        }
        activityLingers = true
        activityLinger?.cancel()
        activityLinger = Task { [weak self] in
            try? await Task.sleep(for: Self.tabLinger)
            guard !Task.isCancelled, let self else { return }
            activityLingers = false
            refreshSurface()
        }
        activityDidChange()
    }

    /// The newest call, while an agent is at work, has just been, or its
    /// list is open: the list stands on the pill, so the pill stays under it.
    var shownActivity: ControlActivity.Entry? {
        activityIsWorking || activityList.isPresented ? activity.first : nil
    }

    /// A call is running or has just ended: the rim's spark runs.
    var activityIsWorking: Bool {
        activityLingers || activity.contains { $0.state == .running }
    }

    private func activityDidChange() {
        refreshSurface()
        activityList.reload()
    }

    func toggleActivityList(from pill: NSView) {
        guard let window = pill.window else { return }
        activityList.toggle(in: window, from: pill)
    }
}
