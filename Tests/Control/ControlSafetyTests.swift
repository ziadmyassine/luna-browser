//
//  ControlSafetyTests.swift
//  LunaTests
//
//  Luna Control's safety rails against a real session: a stopped client's
//  calls fail, a call waiting for approval leaves the user's window alone,
//  and every call lands in the activity log.
//

import AppKit
import BrowserKit
import LunaControl
import XCTest
@testable import Luna

@MainActor
final class ControlSafetyTests: XCTestCase {

    private var directory: URL!
    private var defaults: UserDefaults!
    private let client = ControlClient(rawName: "example-agent")
    private let page = URL(string: "data:text/html,%3Cbutton%3EGo%3C/button%3E")!

    override func setUpWithError() throws {
        directory = URL.temporaryDirectory.appending(path: "luna-tests-\(UUID().uuidString)")
        defaults = UserDefaults(suiteName: "luna-control-tests-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private var audit: URL { directory.appending(path: "activity.jsonl") }

    private func makeService(_ mode: ControlMode) async throws -> (ControlService, BrowserSession) {
        let store = try BrowserStore(path: directory.appending(path: "luna.sqlite"))
        try await store.seedIfEmpty()
        let session = try await BrowserSession.restored(store: store)
        defaults.set(mode.rawValue, forKey: ControlService.modeKey)
        return (ControlService(session: session, defaults: defaults, auditURL: audit), session)
    }

    private func text(_ result: ControlResult) -> String {
        result.content.compactMap { if case let .text(text) = $0 { text } else { nil } }.joined()
    }

    /// Waits for a request to reach the approvals queue.
    private func pending(_ service: ControlService) async throws -> ControlApprovals.Request {
        for _ in 0 ..< 200 {
            if let request = service.approvals.pending.first { return request }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw XCTSkip("no approval was requested")
    }

    func testStoppedClientCallsFail() async throws {
        let (service, _) = try await makeService(.allowAll)
        let other = ControlClient(rawName: "other-agent")
        _ = await service.perform(ControlCall(.openTab(page)), client)

        service.stop(client: client.displayName)
        for command in [ControlCommand.pageText, .listTabs, .wait(seconds: 0), .click(.ref("e1"), clickCount: 1)] {
            let result = await service.perform(ControlCall(command), client)
            XCTAssertTrue(result.isError, "\(command) ran for a stopped client")
        }
        let untouched = await service.perform(ControlCall(.listTabs), other)
        XCTAssertFalse(untouched.isError, "stopping one client stopped another")

        service.resume(client: client.displayName)
        let resumed = await service.perform(ControlCall(.pageText), client)
        XCTAssertFalse(resumed.isError, text(resumed))

        service.stopAll()
        let everyone = await service.perform(ControlCall(.listTabs), other)
        XCTAssertTrue(everyone.isError)
        service.resumeAll()

        // A call already waiting on the user ends when the client is stopped.
        defaults.set(ControlMode.ask.rawValue, forKey: ControlService.modeKey)
        let waiting = Task { await service.perform(ControlCall(.click(.ref("e1"), clickCount: 1)), client) }
        _ = try await pending(service)
        service.stop(client: client.displayName)
        let stopped = await waiting.value
        XCTAssertTrue(stopped.isError)
        XCTAssertTrue(service.approvals.pending.isEmpty)
    }

    func testPendingApprovalDoesNotChangeKeyWindowOrActiveTab() async throws {
        let (service, session) = try await makeService(.ask)
        let users = session.newTab(url: URL(string: "about:blank")!)
        let blank = await service.perform(ControlCall(.openTab(nil)), client)
        XCTAssertFalse(blank.isError, "a blank tab should not need approval: \(text(blank))")
        let keyWindow = NSApp.keyWindow
        let wasActive = NSApp.isActive

        let declined = Task { await service.perform(ControlCall(.navigate(.url(self.page))), self.client) }
        let request = try await pending(service)
        XCTAssertEqual(NSApp.keyWindow, keyWindow, "an approval prompt took the key window")
        XCTAssertEqual(NSApp.isActive, wasActive, "an approval prompt activated Luna")
        XCTAssertEqual(session.activeTabID, users, "an approval prompt changed the user's tab")
        let folder = try XCTUnwrap(session.groups.first { $0.name == client.displayName })
        XCTAssertEqual(request.folder, folder.id)
        XCTAssertNotNil(session.controlBadges[folder.id], "the folder does not say it is waiting")

        service.approvals.answer(request.id, .deny)
        let result = await declined.value
        XCTAssertTrue(result.isError)
        XCTAssertTrue(text(result).contains("declined"), text(result))

        let approved = Task { await service.perform(ControlCall(.navigate(.url(self.page))), self.client) }
        service.approvals.answer(try await pending(service).id, .once)
        let done = await approved.value
        XCTAssertFalse(done.isError, text(done))
        XCTAssertEqual(session.activeTabID, users)
    }

    func testAuditRecordsEveryCall() async throws {
        let (service, _) = try await makeService(.allowAll)
        _ = await service.perform(ControlCall(.listTabs), client)
        _ = await service.perform(ControlCall(.openTab(page)), client)
        _ = await service.perform(ControlCall(.type("hunter2", ref: nil)), client)
        _ = await service.perform(ControlCall(tab: 9999, .pageText), client)
        service.stop(client: client.displayName)
        _ = await service.perform(ControlCall(.wait(seconds: 0)), client)

        let records = ControlAudit.read(from: audit)
        XCTAssertEqual(records.map(\.tool), ["wait", "page_text", "type", "tab_open", "tabs_list"])
        XCTAssertEqual(records.first?.decision, "stopped")
        XCTAssertEqual(records[1].outcome, "error")
        XCTAssertTrue(records.allSatisfy { $0.client == client.displayName })
        let raw = try String(contentsOf: audit, encoding: .utf8)
        XCTAssertFalse(raw.contains("hunter2"), "the log kept what was typed")
    }

    func testAlertInAgentTabDoesNotSheetUserWindow() async throws {
        let (service, session) = try await makeService(.allowAll)
        let users = session.newTab(url: URL(string: "about:blank")!)
        _ = await service.perform(ControlCall(.openTab(page)), client)

        // The script is stuck inside `confirm` until the dialog is answered;
        // the call comes back as soon as the dialog opens rather than then.
        let opened = await service.perform(ControlCall(.javascript("window.answer = confirm('Delete everything?')")), client)
        XCTAssertTrue(text(opened).contains("Delete everything?"), text(opened))
        XCTAssertNil(NSApp.modalWindow, "the page's dialog ran modally")
        XCTAssertTrue(NSApp.windows.allSatisfy { $0.attachedSheet == nil }, "the page's dialog sheeted a window")
        XCTAssertEqual(session.activeTabID, users)

        let blocked = await service.perform(ControlCall(.pageText), client)
        XCTAssertTrue(blocked.isError)
        XCTAssertTrue(text(blocked).contains("dialog"), text(blocked))

        let answered = await service.perform(ControlCall(.dialog(accept: true, text: nil)), client)
        XCTAssertFalse(answered.isError, text(answered))
        let value = await service.perform(ControlCall(.javascript("String(window.answer)")), client)
        XCTAssertTrue(text(value).contains("true"), text(value))
        let none = await service.perform(ControlCall(.dialog(accept: false, text: nil)), client)
        XCTAssertTrue(none.isError, "answered a dialog that is not there")
    }

    func testAgentDownloadWaitsForApproval() async throws {
        // Even when every acting call is allowed: a download is a file on this Mac.
        let (service, session) = try await makeService(.allowAll)
        let users = session.newTab(url: URL(string: "about:blank")!)
        _ = await service.perform(ControlCall(.openTab(page)), client)
        let agentTab = try XCTUnwrap(service.currentTab[client.connection])
        let agentView = try XCTUnwrap(session.controller(for: agentTab)?.webView)

        let declined = Task { await service.approveDownload(named: "report.csv", risky: false, from: agentView) }
        let request = try await pending(service)
        XCTAssertTrue(request.summary.contains("report.csv"), request.summary)
        XCTAssertFalse(request.grantable)
        XCTAssertNil(NSApp.modalWindow)
        service.approvals.answer(request.id, .deny)
        let no = await declined.value
        XCTAssertEqual(no, false)

        let approved = Task { await service.approveDownload(named: "setup.pkg", risky: true, from: agentView) }
        let risky = try await pending(service)
        XCTAssertTrue(risky.reason.contains("run"), "a file that runs should say so: \(risky.reason)")
        service.approvals.answer(risky.id, .once)
        let yes = await approved.value
        XCTAssertEqual(yes, true)

        // The user's own tab is none of Luna Control's business.
        let usersView = try XCTUnwrap(session.wakeForControl(users)?.webView)
        let theirs = await service.approveDownload(named: "x.csv", risky: false, from: usersView)
        XCTAssertNil(theirs)
        XCTAssertTrue(service.approvals.pending.isEmpty)
        XCTAssertEqual(ControlAudit.read(from: audit).first?.tool, "download")
    }

    func testRequestUserWaitsForDone() async throws {
        let (service, session) = try await makeService(.ask)
        let asked = Task { await service.perform(ControlCall(.requestUser("Sign in to the bank")), self.client) }
        let request = try await pending(service)
        XCTAssertTrue(request.isHandoff)
        XCTAssertEqual(request.summary, "Sign in to the bank")
        XCTAssertNotNil(session.controlBadges[try XCTUnwrap(request.folder)])
        service.approvals.answer(request.id, .once)
        let done = await asked.value
        XCTAssertFalse(done.isError, text(done))
    }
}
