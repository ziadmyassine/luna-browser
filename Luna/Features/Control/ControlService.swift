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
    /// A session named its task: `userInfo` has its `session` and `title`.
    static let taskNamed = Notification.Name("ControlService.taskNamed")

    /// The stdio server an MCP client is given: `Contents/MacOS/luna-control`,
    /// beside the app's own binary.
    static var helperURL: URL {
        (Bundle.main.executableURL?.deletingLastPathComponent() ?? Bundle.main.bundleURL)
            .appending(path: "luna-control")
    }

    /// `clientInfo.name` of each client connected now.
    var clientNames: [String] { listener?.clientNames ?? [] }

    /// Every client connected now, one per session.
    var clients: [ControlClient] { listener?.clients ?? [] }

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
    /// Everything kept per agent is kept per session (`ControlClient.session`),
    /// not per app: two sessions of one app are two agents, each with its
    /// own folder, pause and activity. In memory: a relaunch is a fresh start.
    var holds: [String: Hold] = [:]
    /// The main menu's Stop All Agents, until Resume.
    var stoppedAll = false
    /// A paused session's calls, waiting for Resume, by session and call.
    var pausedCalls: [String: [UUID: CheckedContinuation<Void, Never>]] = [:]
    /// The tasks running each session's calls, so Stop can cancel them.
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
    /// Per tab, the scale of the last whole-viewport screenshot below 1:
    /// the agent's coordinates are that picture's pixels until the next.
    var shotScales: [UUID: Double] = [:]
    /// Per tab, its `gif` recording.
    var recordings: [UUID: ControlRecording] = [:]
    /// Each session's folder, so a renamed folder stays theirs.
    var folders: [String: UUID] = [:]
    /// The name Luna last gave each session's folder. A folder still called
    /// that follows the session's name; one the user renamed keeps theirs.
    var folderNames: [String: String] = [:]
    /// What each session said it is doing (`name_task`), which its folder is
    /// called in place of the session's or the app's name.
    var taskNames: [String: String] = [:]
    /// The newest word from each session: its app and its name.
    var agents: [String: ControlClient] = [:]
    /// Calls running per folder. The folder shows as controlled while this is
    /// above zero and for `markLinger` after.
    private var running: [UUID: Int] = [:]
    /// Calls running per tab, on the same terms: the tab's row is outlined.
    private var runningTabs: [UUID: Int] = [:]
    /// Sessions connected at the last change, so a new one is told apart
    /// from one that was already there.
    var connectedSessions: Set<String> = []
    /// Where a request waiting for the user is asked.
    private lazy var approvalCard = ControlApprovalCard(approvals: approvals)
    /// Which session last acted on each tab: whose capsule a page shows when
    /// the user goes to it.
    var actingOn: [UUID: String] = [:]
    /// The calls since launch, newest first — the activity pill and its list
    /// (`ControlService+Activity.swift`).
    var activity: [ControlActivity.Entry] = []
    /// Sessions whose last call ended less than `tabLinger` ago, so a pill
    /// does not blink out between an agent's calls.
    var activityLingers: Set<String> = []
    var activityLinger: [String: Task<Void, Never>] = [:]
    lazy var activityList = ControlActivityController(service: self)
    private var surfaceWatch: ObservationToken?
    private var pageWatch: ObservationToken?

    init(
        session: BrowserSession,
        defaults: UserDefaults = .standard,
        auditURL: URL = ControlAudit.url(
            inControlFolderOf: ControlSocket.path(bundleIdentifier: Bundle.main.bundleIdentifier ?? "dev.novapps.luna")
        )
    ) {
        Self.dropAgentTabIcons(in: session)
        self.session = session
        self.defaults = defaults
        self.auditURL = auditURL
        approvals.onChange = { [weak self] in
            self?.refreshBadges()
            self?.showApprovals()
        }
        session.control = self
        // A tab switch, a call starting or ending, a pause, a folder closed:
        // each is a change. A closed folder has to drop its face too, or its
        // outline is left behind.
        surfaceWatch = session.addChangeObserver { [weak self] in
            self?.dropClosedFaces()
            self?.refreshSurface()
        }
        // A navigation changes the page's colour without being a change.
        pageWatch = session.addTabStateObserver { [weak self, weak session] id, _ in
            if id == session?.activeTabID { self?.refreshSurface() }
        }
        // Folders from an earlier launch wear their app's icon before the
        // app connects again.
        refreshFaces()
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
                path: ControlSocket.path(bundleIdentifier: Bundle.main.bundleIdentifier ?? "dev.novapps.luna"),
                version: version,
                onClientsChange: { [weak self] in
                    Task { @MainActor in
                        self?.clientsChanged()
                        NotificationCenter.default.post(name: Self.clientsDidChange, object: nil)
                    }
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
        clientsChanged()
        NotificationCenter.default.post(name: Self.clientsDidChange, object: nil)
    }

    // MARK: - Calls

    /// Runs one call in a task of its own, which is what Stop cancels.
    func perform(_ call: ControlCall, _ client: ControlClient) async -> ControlResult {
        let key = UUID()
        let work = Task { await self.gated(call, client) }
        inFlight[client.session, default: [:]][key] = work
        defer { inFlight[client.session]?[key] = nil }
        return await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
    }

    /// Carries out a call the gate has let through. `id` is the tab it
    /// resolved, nil for the calls that name none.
    func execute(_ call: ControlCall, for client: ControlClient, in session: BrowserSession, tab id: UUID?) async throws
        -> ControlResult {
        let folder = folders[client.session]
        if let folder { mark(folder, running: true) }
        astroActed(on: id, for: client.session)
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
        case .requestUser, .nameTask, .askUser:
            return await speak(call.command, for: client, in: session)
        case .labelTab, .showDocument, .searchHistory, .listFolders, .readPDF, .addToCalendar:
            return try await assist(call.command, tab: id, for: client, in: session)
        case let .viewport(size):
            return await viewport(size, tab: id, for: client, in: session)
        default:
            return try await onPage(call.command, for: client, in: session, tab: id)
        }
    }

    func openTab(_ url: URL?, in session: BrowserSession, for client: ControlClient) async throws -> ControlResult {
        // The folder `execute` marks is one that existed when the call came in.
        let isNew = folders[client.session].flatMap(session.group)?.spaceID != session.activeSpaceID
        let group = folderInActiveSpace(for: client, in: session)
        if isNew { mark(group.id, running: true) }
        defer { if isNew { mark(group.id, running: false) } }
        let id = session.openControlledTab(url: url, in: group)
        currentTab[client.connection] = id
        actingOn[id] = client.session
        mark(tab: id, of: client.session, running: true)
        defer { mark(tab: id, of: client.session, running: false) }
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
        guard let folder = folders[client.session], session.tab(id)?.groupID == folder else {
            return .error("Tab \(call.tab ?? 0) is not in your folder. Only tabs you opened can be closed.")
        }
        session.closeControlledTab(id)
        recordings[id] = nil
        shotScales[id] = nil
        currentTab[client.connection] = nil
        return .text("Closed tab \(call.tab ?? 0).")
    }

    private func listTabs(in session: BrowserSession, for client: ControlClient) -> String {
        let front = session.activeTabID
        let yours = folders[client.session]
        var lines: [String] = []
        for space in session.spaces {
            let tabs = session.list[space.id].filter { $0.archivedAt == nil }
            guard !tabs.isEmpty else { continue }
            lines.append("Space “\(space.name)”\(space.id == session.activeSpaceID ? " (current)" : ""):")
            for tab in tabs {
                var line = "  [\(number(tab.id))] \(tab.customTitle ?? tab.title) — \(tab.url.absoluteString)"
                if tab.id == front { line += " (in front)" }
                line += folderNote(for: tab, yours: yours, in: session)
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

    /// The sheet over whatever page the user is looking at.
    private func showApprovals() {
        approvalCard.update(on: surface)
    }

    /// How long a folder stays marked after its last call. Long enough that a
    /// run of calls reads as one stretch of work rather than a flicker.
    private static let markLinger: Duration = .seconds(2)
    /// How long a tab stays marked, and its capsule up, after the last call
    /// on it: longer than a folder's, because it also covers the model
    /// thinking between two calls on the same page, and a capsule that went
    /// and came back with each call would flicker.
    static let tabLinger: Duration = .seconds(8)

    private func mark(_ folder: UUID, running start: Bool) {
        count(folder, in: \.running, start: start, linger: Self.markLinger) { [weak self] on in
            self?.session?.setControlled(on, group: folder)
        }
    }

    private func mark(tab id: UUID, of agent: String, running start: Bool) {
        let face = ControlFace(appID: appID(of: agent))
        count(id, in: \.runningTabs, start: start, linger: Self.tabLinger) { [weak self] on in
            self?.session?.setControlled(on, tab: id, face: face)
        }
    }

    private func count(
        _ key: UUID, in counts: ReferenceWritableKeyPath<ControlService, [UUID: Int]>, start: Bool,
        linger: Duration, apply: @escaping @MainActor (Bool) -> Void
    ) {
        guard start else {
            Task { [weak self] in
                try? await Task.sleep(for: linger)
                guard let self else { return }
                self[keyPath: counts][key, default: 1] -= 1
                if self[keyPath: counts][key] ?? 0 <= 0 {
                    self[keyPath: counts][key] = nil
                    apply(false)
                }
            }
            return
        }
        self[keyPath: counts][key, default: 0] += 1
        apply(true)
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

extension ControlService {

    private func onPage(_ command: ControlCommand, for client: ControlClient, in session: BrowserSession, tab id: UUID?)
        async throws -> ControlResult {
        guard let id, let controller = session.wakeForControl(id), let webView = controller.webView else {
            return .error("That tab could not be woken.")
        }
        currentTab[client.connection] = id
        actingOn[id] = client.session
        if command.takesOver { enfold(id, for: client, in: session) }
        mark(tab: id, of: client.session, running: true)
        defer { mark(tab: id, of: client.session, running: false) }
        await showPointer(for: command, on: webView, by: client)
        return try await onTab(command, tab: id, webView: webView, controller: controller)
    }
}
