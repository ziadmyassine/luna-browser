//
//  AppDelegate+Control.swift
//  Luna
//
//  The app menu's Stop All Agents: Luna Control's kill switch for every
//  connected client at once (docs/LUNA-CONTROL.md, Security). It ends the
//  calls running now and refuses the rest until Resume Agents.
//

import AppKit

extension AppDelegate {

    @objc func toggleStopAllAgents(_ sender: Any?) {
        guard let control else { return }
        if control.stoppedAll {
            control.resumeAll()
        } else {
            control.stopAll()
        }
    }

    /// Says which way the next press goes. Live even with the setting off,
    /// so stopping never depends on finding the switch first.
    func validateStopAllAgents(_ item: NSMenuItem) -> Bool? {
        guard item.action == #selector(toggleStopAllAgents(_:)) else { return nil }
        item.title = control?.stoppedAll == true
            ? String(localized: "Resume Agents")
            : String(localized: "Stop All Agents")
        return control != nil
    }
}
