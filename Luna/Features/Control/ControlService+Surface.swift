//
//  ControlService+Surface.swift
//  Luna
//
//  What `ControlSurfaceView` shows of the agents: the capsule on a page an
//  agent is working on, with Take Over, and the agent's pointer where it
//  acts on a page the user can see.
//

import AppKit
import LunaControl
import WebKit

extension ControlService {

    /// The front window's layer over the page.
    var surface: ControlSurfaceView? {
        (session?.hostWindow?.windowController as? BrowserWindowController)?.controlSurface
    }

    /// The capsule for the tab in front, if an agent is working on it.
    func refreshSurface() {
        guard let surface, let session else { return }
        surface.onToggleWorking = { [weak self] in self?.toggleTakeover() }
        let page = session.activeTabID.flatMap { session.controller(for: $0)?.state.pageBackground }
        surface.setPageColour(page.map(NSColor.init))
        surface.showWorking(working(on: session.activeTabID, in: session))
        surface.showActivity(shownActivity) { [weak self] agent, pill in
            self?.toggleActivityList(of: agent, from: pill)
        }
    }

    /// The session acting on `id` now, or paused on it. Only while it acts
    /// (`BrowserSession.controlledTabs`, which outlives each call by
    /// `tabLinger`): a capsule that stayed as long as the client was connected
    /// said "working" over a page it had finished with. Paused, it stays, so
    /// Resume can be pressed.
    private func working(on id: UUID?, in session: BrowserSession) -> ControlSurfaceView.Working? {
        guard let id, let agent = actingOn[id], connectedSessions.contains(agent), !stoppedAll,
              holds[agent] != .stopped else { return nil }
        let isActing = session.controlledTabs[id] != nil
        let isPaused = holds[agent] == .paused
        guard isActing || isPaused else { return nil }
        return ControlSurfaceView.Working(
            client: displayName(of: agent), appID: appID(of: agent), isPaused: isPaused, isActing: isActing
        )
    }

    /// Take Over pauses the agent working on the page in front; Resume hands
    /// the page back.
    private func toggleTakeover() {
        guard let id = session?.activeTabID, let agent = actingOn[id] else { return }
        if holds[agent] == .paused { resume(client: agent) } else { pause(client: agent) }
        refreshSurface()
    }

    /// Moves the agent's pointer to where `command` acts, when the page is
    /// one the user can see. A tab in no window, or on the stage, has nobody
    /// to show it to.
    func showPointer(for command: ControlCommand, on webView: WKWebView, by client: ControlClient) async {
        guard let surface, let window = webView.window, window === surface.window,
              let point = await points(for: command, in: webView).last else { return }
        let zoom = webView.pageZoom
        let top = webView.obscuredContentInsets.top + point.y * zoom
        let local = NSPoint(x: point.x * zoom, y: webView.isFlipped ? top : webView.bounds.height - top)
        let clicks = if case .click = command { true } else { false }
        surface.point(
            at: surface.convert(local, from: webView), client: client.shownName,
            tint: Tokens.Agent.tint(forApp: appID(of: client.session)),
            clicks: clicks
        )
    }
}
