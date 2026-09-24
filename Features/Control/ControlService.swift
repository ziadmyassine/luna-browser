//
//  ControlService.swift
//  Luna
//
//  Luna Control: other programs on this Mac driving Luna over MCP
//  (docs/LUNA-CONTROL.md). This file is the switch and the tabs — the socket
//  that exists only while the setting is on, which tab a call means, and the
//  folder each client's tabs go into. What happens inside a page is
//  `ControlService+Page.swift`.
//
//  Every call passes the gate in `ControlService+Safety.swift` first: the
//  stop and pause switches, the policy, the user's approval, and on the way
//  out the redactor, the untrusted fence and the activity log.
//
//  Off by default, and it has to be: whoever connects can read and act in
//  every signed-in site in the non-private session. The socket is user-only
//  and there is no network listener, so "whoever" is a program the user runs.
//  Private windows are never reachable — the service holds the main session.
//

import AppKit
import BrowserKit
import LunaControl

@MainActor
final class ControlService {

    /// SETTINGS-SPEC §3.10's "Allow apps to control Luna". The key predates
    /// the section and §6 does not rename keys.
    static let enabledKey = "advanced.allowControl"

    /// Posted on the main actor when a client connects, names itself or goes.
    static let clientsDidChange = Notification.Name("ControlService.clientsDidChange")

    /// The stdio server an MCP client is given: `Contents/MacOS/luna-control`,
    /// beside the app's own binary.
    static var helperURL: URL {
        (Bundle.main.executableURL?.deletingLastPathComponent() ?? Bundle.main.bundleURL)
            .appending(path: "luna-control")
    }

    /// `clientInfo.name` of each client connected now.
    var clientNames: [String] { listener?.clientNames ?? [] }

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: enabledKey)
            NotificationCenter.default.post(name: Settings.didChange, object: nil)
        }
    }

    private(set) weak var session: BrowserSession?
    private var listener: ControlListener?

    let approvals = ControlApprovals()
    /// Where the mode and the site grants are kept. Injected so a test can
    /// set a mode without touching the user's.
    let defaults: UserDefaults
    let auditURL: URL

    enum Hold { case paused, stopped }
    /// Per client display name. In memory: a relaunch is a fresh start.
    var holds: [String: Hold] = [:]
    /// The main menu's Stop All Agents, until Resume.
    var stoppedAll = false
    /// The tasks running each client's calls, so Stop can cancel them.
    var inFlight: [String: [UUID: Task<ControlResult, Never>]] = [:]

    /// A site a page on it addressed the agent from, for the rest of that
    /// connection: acting there asks whatever the mode.
    struct Escalation: Hashable {
        var connection: UUID
        var site: String
    }
    var escalated: Set<Escalation> = []
    /// Dialogs held for agents, by tab — `ControlService+Handoff.swift`.
    var dialogs: [UUID: HeldDialog] = [:]

    /// Tabs are numbered for clients, in the order a client first sees them:
    /// a model copes with `3` far better than with a UUID. For the life of
    /// the app, so a number never comes to mean a different tab.
    private var numbers: [UUID: Int] = [:]
    private var tabsByNumber: [Int: UUID] = [:]
    /// The tab each connection last opened or acted on — what a call with no
    /// `tabId` means.
    var currentTab: [UUID: UUID] = [:]
    /// Per tab, the documents it has loaded since an agent first touched it,
    /// in the shape `ControlScripts.networkRead` takes.
    var networkDocuments: [UUID: [[String: Any]]] = [:]
    /// Each client's folder, by display name, so a renamed folder stays theirs.
    var folders: [String: UUID] = [:]
    /// Calls running per folder. The folder shows as controlled while this is
    /// above zero and for `markLinger` after.
    private var running: [UUID: Int] = [:]

    init(
        session: BrowserSession,
        defaults: UserDefaults = .standard,
        auditURL: URL = ControlAudit.url(
            inControlFolderOf: ControlSocket.path(bundleIdentifier: Bundle.main.bundleIdentifier ?? "dk.novapps.luna")
        )
    ) {
        self.session = session
        self.defaults = defaults
        self.auditURL = auditURL
        approvals.onChange = { [weak self] in self?.refreshBadges() }
        session.control = self
    }

    /// The `luna-control` service of the running app, for the sidebar and the
    /// menus. Nil until launch has finished.
    static var current: ControlService? { (NSApp.delegate as? AppDelegate)?.control }

    /// Makes the socket match the setting. Called at launch and on every
    /// settings change.
    func update() {
        guard Self.isEnabled != (listener != nil) else { return }
        guard Self.isEnabled else {
            stop()
            return
        }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        do {
            listener = try ControlListener(
                path: ControlSocket.path(bundleIdentifier: Bundle.main.bundleIdentifier ?? "dk.novapps.luna"),
                version: version,
                onClientsChange: {
                    Task { @MainActor in NotificationCenter.default.post(name: Self.clientsDidChange, object: nil) }
                },
                perform: { [weak self] call, client in
                    await self?.perform(call, client) ?? .error("Luna is closing.")
                }
            )
        } catch {
            NSLog("Luna Control: could not open its socket: %@", String(describing: error))
        }
    }

    func stop() {
        listener?.stop()
        listener = nil
        NotificationCenter.default.post(name: Self.clientsDidChange, object: nil)
    }

    // MARK: - Calls

    /// Runs one call in a task of its own, which is what Stop cancels.
    func perform(_ call: ControlCall, _ client: ControlClient) async -> ControlResult {
        let key = UUID()
        let work = Task { await self.gated(call, client) }
        inFlight[client.displayName, default: [:]][key] = work
        defer { inFlight[client.displayName]?[key] = nil }
        return await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
    }

    /// Carries out a call the gate has let through. `id` is the tab it
    /// resolved, nil for the calls that name none.
    func execute(_ call: ControlCall, for client: ControlClient, in session: BrowserSession, tab id: UUID?) async throws
        -> ControlResult {
        let folder = folders[client.displayName]
        if let folder { mark(folder, running: true) }
        defer { if let folder { mark(folder, running: false) } }
        switch call.command {
        case .listTabs:
            return .text(listTabs(in: session, for: client))
        case let .openTab(url):
            return try await openTab(url, in: session, for: client)
        case let .wait(seconds):
            try await Task.sleep(for: .seconds(seconds))
            return .text("Waited \(seconds) s.")
        case .closeTab:
            return try closeTab(call, in: session, for: client)
        case let .requestUser(reason):
            return await requestUser(reason, for: client, in: session)
        default:
            guard let id, let controller = session.wakeForControl(id), let webView = controller.webView else {
                return .error("That tab could not be woken.")
            }
            currentTab[client.connection] = id
            return try await onTab(call.command, tab: id, webView: webView, controller: controller)
        }
    }

    private func openTab(_ url: URL?, in session: BrowserSession, for client: ControlClient) async throws -> ControlResult {
        let group = session.controlFolder(named: client.displayName, previously: folders[client.displayName])
        // The folder `perform` marks is one that existed when the call came in.
        let isNew = folders[client.displayName] != group.id
        folders[client.displayName] = group.id
        if isNew { mark(group.id, running: true) }
        defer { if isNew { mark(group.id, running: false) } }
        let id = session.openControlledTab(url: url, in: group)
        currentTab[client.connection] = id
        if let webView = session.controller(for: id)?.webView {
            size(webView, in: session)
            await settle(webView)
        }
        let tab = session.tab(id)
        return .text("Opened tab \(number(id)) in the “\(group.name)” folder: \(tab?.title ?? "") \(tab?.url.absoluteString ?? "")")
    }

    /// Only a tab in the client's own folder: closing is the one call that
    /// cannot be taken back from the page, and the user's tabs are theirs.
    private func closeTab(_ call: ControlCall, in session: BrowserSession, for client: ControlClient) throws -> ControlResult {
        let id = try resolve(call, in: session, for: client)
        guard let folder = folders[client.displayName], session.tab(id)?.groupID == folder else {
            return .error("Tab \(call.tab ?? 0) is not in your folder. Only tabs you opened can be closed.")
        }
        session.closeControlledTab(id)
        currentTab[client.connection] = nil
        return .text("Closed tab \(call.tab ?? 0).")
    }

    private func listTabs(in session: BrowserSession, for client: ControlClient) -> String {
        let front = session.activeTabID
        let yours = folders[client.displayName]
        var lines: [String] = []
        for space in session.spaces {
            let tabs = session.list[space.id].filter { $0.archivedAt == nil }
            guard !tabs.isEmpty else { continue }
            lines.append("Space “\(space.name)”\(space.id == session.activeSpaceID ? " (current)" : ""):")
            for tab in tabs {
                var line = "  [\(number(tab.id))] \(tab.customTitle ?? tab.title) — \(tab.url.absoluteString)"
                if tab.id == front { line += " (in front)" }
                if let group = tab.groupID, group == yours { line += " (yours)" }
                lines.append(line)
            }
        }
        return lines.isEmpty ? "No tabs are open. Open one with tab_open." : lines.joined(separator: "\n")
    }

    /// The tab a call means — see `ControlCall.tab`.
    func resolve(_ call: ControlCall, in session: BrowserSession, for client: ControlClient) throws -> UUID {
        if let number = call.tab {
            guard let id = tabsByNumber[number], session.tab(id) != nil else {
                throw ControlError("There is no tab \(number) any more. Call tabs_list for the open ones.")
            }
            return id
        }
        if let id = currentTab[client.connection], session.tab(id) != nil { return id }
        if let id = session.activeTabID { return id }
        throw ControlError("There is no tab to act on. Open one with tab_open.")
    }

    func number(_ id: UUID) -> Int {
        if let number = numbers[id] { return number }
        let number = numbers.count + 1
        numbers[id] = number
        tabsByNumber[number] = id
        return number
    }

    // MARK: - The folder's mark

    /// How long a folder stays marked after its last call. Long enough that a
    /// run of calls reads as one stretch of work rather than a flicker.
    private static let markLinger: Duration = .seconds(2)

    private func mark(_ folder: UUID, running start: Bool) {
        guard start else {
            Task { [weak self] in
                try? await Task.sleep(for: Self.markLinger)
                guard let self else { return }
                running[folder, default: 1] -= 1
                if running[folder] ?? 0 <= 0 {
                    running[folder] = nil
                    session?.setControlled(false, group: folder)
                }
            }
            return
        }
        running[folder, default: 0] += 1
        session?.setControlled(true, group: folder)
    }

    static func describe(_ error: any Error) -> String {
        if let error = error as? ControlError { return error.message }
        let error = error as NSError
        // WebKit's key for a script's own exception message. It has no
        // public constant; `WKError.h` documents only the code.
        if let message = error.userInfo["WKJavaScriptExceptionMessage"] as? String { return message }
        return error.localizedDescription
    }
}
