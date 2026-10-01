//
//  BrowserSession+ProcessHealth.swift
//  Luna
//
//  §19.3's heartbeat. A WebContent process suspended in the background can
//  fail to resume, and it sends no termination callback when it does: the
//  page just stays white. Asking it to run something is the only probe, so
//  the pages on screen are asked when the app comes forward and when the Mac
//  wakes (`ProcessHealthWatch`). The rebuild itself, and its budget of three
//  a minute, are `TabController`'s.
//

import AppKit
import BrowserKit

extension BrowserSession {

    /// The live controllers this session's windows are showing, once each.
    /// Only these are probed: a white page is only a problem where it is
    /// seen, and each probe is a round trip to a process.
    var onScreenControllers: [TabController] {
        var seen: Set<UUID> = []
        return windowFocus.keys
            .compactMap { activeTabID(inWindow: $0) }
            .filter { seen.insert($0).inserted }
            .compactMap { controllers[$0] }
    }

    /// Probes every page on screen; a dead one is rebuilt from its saved state.
    func checkProcessHealth() {
        for controller in onScreenControllers {
            Task { await controller.checkProcessHealth() }
        }
    }

    /// Every live tab starts a clean crash budget. For a wake: the burst of
    /// terminations straight after one is the system's, not the page's, and
    /// counting it would leave a healthy tab cold.
    func resetProcessCrashBudget() {
        for controller in controllers.values { controller.resetProcessCrashBudget() }
    }

    /// What the page says once §19.3 has rebuilt it: news for the tab in the
    /// front window, nothing for one that reloaded out of sight.
    func newsOfRecovery(of id: UUID) -> PageToast? {
        id == activeTabID ? .pageReloaded : nil
    }
}

/// Runs the heartbeat at the two moments a suspended page is likeliest to be
/// found dead: the app coming forward, and the Mac waking.
@MainActor
final class ProcessHealthWatch: NSObject {

    /// What each moment does to a session. Seams for tests, which count the
    /// calls rather than kill a real process.
    var check: (BrowserSession) -> Void = { $0.checkProcessHealth() }
    var reset: (BrowserSession) -> Void = { $0.resetProcessCrashBudget() }

    private let sessions: () -> [BrowserSession]

    /// - Parameters:
    ///   - sessions: every session with a window open; the ordinary one and
    ///     each private window's.
    ///   - app: where `didBecomeActiveNotification` is posted.
    ///   - workspace: where `didWakeNotification` is. `NSWorkspace` posts it
    ///     on a centre of its own, which the default one never hears.
    init(
        sessions: @escaping () -> [BrowserSession],
        app: NotificationCenter = .default,
        workspace: NotificationCenter = NSWorkspace.shared.notificationCenter
    ) {
        self.sessions = sessions
        super.init()
        app.addObserver(
            self, selector: #selector(appBecameActive), name: NSApplication.didBecomeActiveNotification, object: nil
        )
        workspace.addObserver(self, selector: #selector(macWoke), name: NSWorkspace.didWakeNotification, object: nil)
    }

    @objc private func appBecameActive() {
        eachSession(check)
    }

    @objc private func macWoke() {
        eachSession { session in
            reset(session)
            check(session)
        }
    }

    private func eachSession(_ body: (BrowserSession) -> Void) {
        var seen: Set<ObjectIdentifier> = []
        for session in sessions() where seen.insert(ObjectIdentifier(session)).inserted {
            body(session)
        }
    }
}
