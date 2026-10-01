//
//  ProcessHealthTests.swift
//  LunaTests
//
//  §19.3's heartbeat: which pages are probed, when, and what the page says
//  once one has been rebuilt. A dead process cannot be produced on demand, so
//  the rebuild is driven through `recoverFromDeadProcess`, the path both a
//  termination callback and a failed probe take.
//

import AppKit
@testable import BrowserKit
import XCTest
@testable import Luna

@MainActor
final class ProcessHealthTests: XCTestCase {

    private var directory: URL!
    private var sessions: [BrowserSession] = []

    override func setUpWithError() throws {
        directory = URL.temporaryDirectory.appending(path: "luna-tests-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        for session in sessions { session.tearDown() }
        sessions = []
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - What is probed

    /// The selected tab of each window, once each, and only if it is live:
    /// a cold tab has no process to ask, and a tab behind the selection is
    /// not on screen.
    func testOnlyTheTabsTheWindowsShowAreProbed() async throws {
        let session = try await makeSession()
        let tabs = try addTabs(3, to: session)
        let space = try XCTUnwrap(session.spaces.first).id
        let first = UUID(), second = UUID(), third = UUID(), cold = UUID()
        for (window, tab) in [(first, tabs[0]), (second, tabs[1]), (third, tabs[0]), (cold, tabs[2])] {
            session.windowFocus[window] = .init(spaceID: space, tabBySpace: [space: tab.id])
        }
        for tab in tabs.prefix(2) { _ = session.ensureController(for: tab) }

        let probed = Set(session.onScreenControllers.map(\.id))
        XCTAssertEqual(probed, [tabs[0].id, tabs[1].id])
        XCTAssertEqual(session.onScreenControllers.count, 2, "a tab shown in two windows was probed twice")
    }

    // MARK: - After a rebuild

    /// The tab in front comes back with a word on the page; a wake then
    /// clears the budget the rebuild spent.
    func testARebuiltFrontPageSaysSoAndAWakeClearsItsBudget() async throws {
        let session = try await makeSession()
        let tab = try XCTUnwrap(addTabs(1, to: session, url: URL(string: "about:blank")!).first)
        let space = tab.spaceID
        let window = UUID()
        session.windowFocus[window] = .init(spaceID: space, tabBySpace: [space: tab.id])
        session.keyWindowID = window
        let host = BrowserWindowController(remembersFrame: false)
        session.hostWindow = host.window
        let controller = session.ensureController(for: tab)

        controller.recoverFromDeadProcess()
        XCTAssertEqual(controller.recoveries.count, 1)
        let deadline = Date().addingTimeInterval(3)
        while host.controlSurface.toast == nil, Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(host.controlSurface.toast?.text, PageToast.pageReloaded.text)

        session.resetProcessCrashBudget()
        XCTAssertTrue(controller.recoveries.isEmpty, "the wake left the crash budget spent")
        host.close()
    }

    /// A page rebuilt in a window behind says nothing over the one in front.
    func testOnlyTheFrontTabIsToldItReloaded() async throws {
        let session = try await makeSession()
        let tabs = try addTabs(2, to: session)
        let space = tabs[0].spaceID
        let front = UUID(), behind = UUID()
        session.windowFocus[front] = .init(spaceID: space, tabBySpace: [space: tabs[0].id])
        session.windowFocus[behind] = .init(spaceID: space, tabBySpace: [space: tabs[1].id])
        session.keyWindowID = front

        XCTAssertEqual(session.newsOfRecovery(of: tabs[0].id), .pageReloaded)
        XCTAssertNil(session.newsOfRecovery(of: tabs[1].id))
    }

    // MARK: - When

    func testComingForwardChecksEachSessionOnce() async throws {
        let one = try await makeSession(), two = try await makeSession()
        let app = NotificationCenter(), workspace = NotificationCenter()
        let watch = ProcessHealthWatch(sessions: { [one, one, two] }, app: app, workspace: workspace)
        var calls: [String] = []
        watch.check = { calls.append("check \($0 === one ? 1 : 2)") }
        watch.reset = { calls.append("reset \($0 === one ? 1 : 2)") }

        app.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        XCTAssertEqual(calls, ["check 1", "check 2"])
    }

    /// A wake clears the budget before it probes: the probe may find the
    /// burst of terminations a wake brings, and that must not count.
    func testAWakeResetsTheBudgetThenChecks() async throws {
        let one = try await makeSession()
        let app = NotificationCenter(), workspace = NotificationCenter()
        let watch = ProcessHealthWatch(sessions: { [one] }, app: app, workspace: workspace)
        var calls: [String] = []
        watch.check = { _ in calls.append("check") }
        watch.reset = { _ in calls.append("reset") }

        workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
        XCTAssertEqual(calls, ["reset", "check"])
        app.post(name: NSWorkspace.didWakeNotification, object: nil)
        XCTAssertEqual(calls, ["reset", "check"], "a wake was heard on the wrong centre")
    }

    // MARK: - Fixtures

    private func makeSession() async throws -> BrowserSession {
        let store = try BrowserStore(path: directory.appending(path: "\(UUID().uuidString).sqlite"))
        let session = try await BrowserSession.restored(store: store)
        sessions.append(session)
        return session
    }

    /// Loose tabs in the seeded Space, made without waking any.
    private func addTabs(
        _ count: Int, to session: BrowserSession, url: URL = URL(string: "https://example.com/")!
    ) throws -> [Tab] {
        let space = try XCTUnwrap(session.spaces.first).id
        let tabs = (0 ..< count).map { index in
            Tab(spaceID: space, kind: .today, url: url, title: "Tab \(index)", order: index)
        }
        for tab in tabs { session.persistAll(session.list.insert(tab)) }
        return tabs
    }
}
