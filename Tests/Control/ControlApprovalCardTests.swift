//
//  ControlApprovalCardTests.swift
//  LunaTests
//
//  A Luna Control request waiting for the user drops its sheet from the top
//  of the page on its own, without the window becoming key, and the sheet
//  goes back up when the request is answered.
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

    func testSheetDropsOnItsOwnAndGoesWhenAnswered() async throws {
        let window = NSWindow(
            contentRect: NSRect(x: 200, y: 200, width: 900, height: 600), styleMask: [.titled], backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        let surface = ControlSurfaceView(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
        surface.topInset = 52
        window.contentView = surface
        window.orderFront(nil)
        defer { window.close() }
        let wasKey = window.isKeyWindow
        let approvals = ControlApprovals()
        let card = ControlApprovalCard(approvals: approvals)
        approvals.onChange = { card.update(on: surface) }

        let asking = Task { await approvals.ask(request()) }
        for _ in 0 ..< 100 where approvals.pending.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        try await Task.sleep(for: .milliseconds(400))

        let sheet = try XCTUnwrap(surface.sheet, "no sheet was shown")
        XCTAssertTrue(sheet.superview === surface)
        XCTAssertEqual(sheet.frame.midX, surface.bounds.midX, accuracy: 1, "the sheet is not centred")
        XCTAssertEqual(sheet.frame.minY, 52 - ControlApprovalCardView.hiddenTop, accuracy: 1, "the sheet is not under the bar")
        XCTAssertEqual(window.isKeyWindow, wasKey, "asking made the window key")

        let request = try XCTUnwrap(approvals.pending.first)
        approvals.answer(request.id, .deny)
        let answer = await asking.value
        XCTAssertEqual(answer, .deny)
        XCTAssertNil(surface.sheet)
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertNil(sheet.superview, "the sheet stayed after the answer")
    }
}
