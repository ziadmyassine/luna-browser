//
//  ControlService+Handoff.swift
//  Luna
//
//  The steps an agent hands to the user, and the page surfaces that would
//  otherwise land on the user's window (docs/LUNA-CONTROL.md, Security):
//  `request_user`, the `alert`/`confirm`/`prompt` a tab in an agent's folder
//  opens, and a download started there. Each waits in the folder like an
//  approval does; none puts a sheet, a panel or a key window on screen.
//

import AppKit
import BrowserKit
import LunaControl
import WebKit

extension ControlService {

    // MARK: - request_user

    func requestUser(_ reason: String, for client: ControlClient, in session: BrowserSession) async -> ControlResult {
        let request = ControlApprovals.Request(
            client: client.displayName, folder: folder(for: client, in: session), site: nil,
            summary: reason, reason: "", grantable: false, isHandoff: true
        )
        switch await approvals.ask(request) {
        case .once, .always:
            return .text("The user says it is done. Read the page again before carrying on.")
        case .deny:
            return .error("The user will not do that step. Ask them what they want instead.")
        case .timedOut:
            return .error("The user did not answer within five minutes.")
        case .stopped:
            return .error(refusal(for: client.displayName) ?? "The user stopped this call.")
        }
    }

    // MARK: - Page dialogs

    struct HeldDialog {
        var dialog: ControlDialog
        var token = UUID()
        var continuation: CheckedContinuation<ControlDialog.Answer, Never>
    }

    /// Long enough for an agent that is mid-call to come back to it; short
    /// enough that a page is not left frozen, since its script is stopped
    /// inside the dialog until it is answered.
    static let dialogTimeout: Duration = .seconds(30)

    /// Holds a dialog from a tab in an agent's folder for the agent's
    /// `dialog` tool. Nil when the dialog is the user's: any other tab, or an
    /// agent's tab the user has in front of them.
    func hold(_ dialog: ControlDialog, tab id: UUID) async -> ControlDialog.Answer? {
        guard let session, session.activeTabID != id, let folder = session.tab(id)?.groupID,
              let client = client(ofFolder: folder) else { return nil }
        // Script is stopped inside the first, so a second cannot open; if one
        // somehow does, it is not shown to the user either.
        guard dialogs[id] == nil else { return .dismiss }
        return await withCheckedContinuation { continuation in
            let held = HeldDialog(dialog: dialog, continuation: continuation)
            dialogs[id] = held
            Task { [weak self] in
                try? await Task.sleep(for: Self.dialogTimeout)
                // Not while the user is deciding whether the agent may answer it.
                while self?.approvals.pending.contains(where: { $0.client == client }) == true {
                    try? await Task.sleep(for: .seconds(1))
                }
                self?.answerDialog(on: id, .dismiss, token: held.token)
            }
        }
    }

    /// `token` limits it to one dialog, so a timer cannot close the next one.
    @discardableResult
    func answerDialog(on id: UUID, _ answer: ControlDialog.Answer, token: UUID? = nil) -> ControlDialog? {
        guard let held = dialogs[id], token == nil || held.token == token else { return nil }
        dialogs[id] = nil
        held.continuation.resume(returning: answer)
        return held.dialog
    }

    /// What every call on a tab with a dialog open reads instead of a result.
    static func describe(_ dialog: ControlDialog) -> String {
        """
        The page has a \(dialog.kind.rawValue)() open: “\(dialog.message)”. Nothing else can run in this tab \
        until you answer it with the dialog tool (accept or dismiss). Luna dismisses it after 30 seconds.
        """
    }

    /// A call on one tab: the `dialog` tool, or any other page tool unless a
    /// dialog is open.
    func onTab(
        _ command: ControlCommand, tab id: UUID, webView: WKWebView, controller: TabController
    ) async throws -> ControlResult {
        if case let .dialog(accept, text) = command {
            guard let dialog = answerDialog(on: id, accept ? .accept(text) : .dismiss) else {
                return .error("Tab \(number(id)) has no dialog open.")
            }
            await settle(webView)
            return .text("\(accept ? "Accepted" : "Dismissed") the \(dialog.kind.rawValue) “\(dialog.message)”.")
        }
        if let held = dialogs[id] { return .error(Self.describe(held.dialog)) }
        let recorded = command.recordsFrame
        let marks = recorded ? await marks(for: command, in: webView, tab: id) : []
        let result = try await racingDialogs(on: id) { try await self.run(command, in: webView, controller: controller) }
        if recorded { await recordFrame(of: webView, tab: id, marks: marks) }
        return result
    }

    /// Runs `body`, coming back early if the page opens a dialog meanwhile:
    /// the script behind the call is stopped inside the dialog and will not
    /// finish until it is answered.
    func racingDialogs(on id: UUID, _ body: @escaping @MainActor () async throws -> ControlResult) async throws
        -> ControlResult {
        let outcome = Outcome()
        Task { @MainActor in
            do { outcome.result = .success(try await body()) } catch { outcome.result = .failure(error) }
        }
        // ponytail: polls every 50 ms; a continuation `hold` resumes would
        // answer at once, if the delay ever shows.
        while true {
            if let result = outcome.result { return try result.get() }
            if let held = dialogs[id] { return .text(Self.describe(held.dialog)) }
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    // MARK: - Downloads

    /// Whether a download from `webView` may go ahead. Nil when it is not an
    /// agent's — `DownloadManager` then carries on as for any download.
    ///
    /// Asked whatever the mode: a download is a file on this Mac, not
    /// something on a site a grant was given for. The card says when the
    /// file can run, and its answer replaces the risky-file sheet, which
    /// would otherwise land on the user's window.
    func approveDownload(named name: String, risky: Bool, from webView: WKWebView?) async -> Bool? {
        guard let session, let webView,
              let id = session.controllers.first(where: { $0.value.webView === webView })?.key,
              session.activeTabID != id, let folder = session.tab(id)?.groupID,
              let client = client(ofFolder: folder) else { return nil }
        let site = session.tab(id).flatMap { Self.site(of: $0.url) }
        var record = ControlAudit.Record(
            client: client, tool: "download", tab: number(id), site: site,
            summary: "download “\(name)”", decision: "approved", outcome: "ok"
        )
        defer { log(record) }
        guard refusal(for: client) == nil else {
            record.decision = "stopped"
            return false
        }
        let answer = await approvals.ask(ControlApprovals.Request(
            client: client, folder: folder, site: site, summary: record.summary,
            reason: risky ? "it downloads a file that can run programs on this Mac" : ControlRisk.download.reason,
            grantable: false
        ))
        let approved = answer == .once || answer == .always
        if !approved { record.decision = answer == .stopped ? "stopped" : "declined" }
        return approved
    }
}

/// A page's `alert`, `confirm` or `prompt`, held for an agent.
struct ControlDialog: Equatable {
    enum Kind: String { case alert, confirm, prompt }

    enum Answer: Equatable {
        case accept(String?)
        case dismiss
    }

    var kind: Kind
    var message: String
    var defaultText: String?
}

/// Where `racingDialogs`'s call leaves its result.
@MainActor
private final class Outcome {
    var result: Result<ControlResult, any Error>?
}
