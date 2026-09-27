//
//  ControlApprovalCardTests.swift
//  LunaTests
//
//  A Luna Control request waiting for the user shows its card on its own,
//  over the window, without the window or the card becoming key, and the
//  card goes when the request is answered.
//

import AppKit
import XCTest
@testable import Luna

@MainActor
final class ControlApprovalCardTests: XCTestCase {

    private func request() -> ControlApprovals.Request {
        ControlApprovals.Request(
            client: "Claude Code", folder: nil, site: "wikipedia.org",
            summary: "tab_open https://en.wikipedia.org/wiki/Moon", reason: "you asked to be asked", grantable: true
        )
    }

    func testCardAppearsOnItsOwnAndGoesWhenAnswered() async throws {
        let window = NSWindow(
            contentRect: NSRect(x: 200, y: 200, width: 900, height: 600), styleMask: [.titled], backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.orderFront(nil)
        defer { window.close() }
        let approvals = ControlApprovals()
        let card = ControlApprovalCard(approvals: approvals)
        approvals.onChange = { card.update(over: window.contentView) }

        let asking = Task { await approvals.ask(request()) }
        for _ in 0 ..< 100 where window.childWindows?.isEmpty ?? true { try await Task.sleep(for: .milliseconds(10)) }

        let panel = try XCTUnwrap(window.childWindows?.first, "no card was shown")
        XCTAssertTrue(panel.isVisible)
        XCTAssertFalse(panel.isKeyWindow)
        XCTAssertTrue(window.frame.contains(panel.frame), "the card is not over the window: \(panel.frame)")
        XCTAssertGreaterThan(panel.frame.height, 60)

        let request = try XCTUnwrap(approvals.pending.first)
        approvals.answer(request.id, .deny)
        let answer = await asking.value
        XCTAssertEqual(answer, .deny)
        XCTAssertTrue(window.childWindows?.isEmpty ?? true, "the card stayed after the answer")
    }
}
