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

        let waiting = try XCTUnwrap(approvals.pending.first)
        approvals.answer(waiting.id, .deny)
        let answer = await asking.value
        XCTAssertEqual(answer, .deny)
        XCTAssertNil(surface.sheet)
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertNil(sheet.superview, "the sheet stayed after the answer")
    }

    /// In the content card, as the browser window has it: pinned by Auto Layout,
    /// resized after the question is up, and asked about a long address.
    func testSheetStaysCentredAndFitsItsText() async throws {
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 1670, height: 800), styleMask: [.titled, .resizable],
            backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 1670, height: 800))
        window.contentView = root
        let card = ContentCardView(frame: root.bounds)
        card.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(card)
        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 165),
            card.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            card.topAnchor.constraint(equalTo: root.topAnchor),
            card.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])
        let surface = ControlSurfaceView()
        card.setAgentLayer(surface)
        card.setContentTopInset(52, animated: false)
        window.orderFront(nil)
        defer { window.close() }
        root.layoutSubtreeIfNeeded()

        let approvals = ControlApprovals()
        let asker = ControlApprovalCard(approvals: approvals)
        approvals.onChange = { asker.update(on: surface) }
        let asking = Task {
            await approvals.ask(ControlApprovals.Request(
                client: "Claude Code", folder: nil, site: "github.com",
                summary: "tab_open https://github.com/ziadmyassine/luna-browser/pull/412/files?diff=split&w=1",
                reason: "you asked to be asked", grantable: true
            ))
        }
        for _ in 0 ..< 100 where approvals.pending.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        try await Task.sleep(for: .milliseconds(400))
        root.layoutSubtreeIfNeeded()

        let sheet = try XCTUnwrap(surface.sheet as? ControlApprovalCardView)
        XCTAssertEqual(sheet.frame.midX, surface.bounds.midX, accuracy: 1, "the sheet is not centred")
        XCTAssertEqual(sheet.frame.width, ControlApprovalCardView.width, accuracy: 1, "the sheet is not the chip's width")
        let glass = try XCTUnwrap(sheet.subviews.first { $0 is GlassBackingView }, "the sheet has no glass")
        XCTAssertEqual(glass.frame, sheet.bounds, "the glass reaches past the sheet")

        window.setContentSize(NSSize(width: 1100, height: 800))
        root.layoutSubtreeIfNeeded()
        XCTAssertEqual(sheet.frame.midX, surface.bounds.midX, accuracy: 1, "the sheet stayed where the old width put it")

        approvals.answer(try XCTUnwrap(approvals.pending.first).id, .deny)
        _ = await asking.value
    }

    /// A short question keeps the chip's width, and a long site name in the
    /// last button widens the sheet rather than cutting the button off.
    func testSheetKeepsTheChipsWidthAndMakesRoomForItsAnswers() {
        let view = ControlApprovalCardView(
            request: ControlApprovals.Request(
                client: "Codex", folder: nil, site: nil, summary: "Read the page", reason: "it is new", grantable: false
            ),
            waiting: 1
        ) { _ in }
        XCTAssertEqual(view.fittingCardSize().width, ControlApprovalCardView.width, accuracy: 1, "a short question made a narrow sheet")

        let long = ControlApprovalCardView(
            request: ControlApprovals.Request(
                client: "Codex", folder: nil, site: "accounts.a-very-long-subdomain.example.com", summary: "Click Sign In",
                reason: "it signs in", grantable: true
            ),
            waiting: 1
        ) { _ in }
        let size = long.fittingCardSize()
        XCTAssertGreaterThan(size.width, ControlApprovalCardView.width, "the answers were squeezed into the chip")
        XCTAssertEqual(size.width, long.contentWidth + ControlApprovalCardView.sideInsets, accuracy: 1)
    }

    /// The working capsule's glass is the capsule's size, not the doubled
    /// size a zero-sized start left it at.
    func testCapsuleGlassFitsTheCapsule() throws {
        let surface = ControlSurfaceView(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
        surface.showWorking(.init(client: "Claude Code", appID: "claude-code", isPaused: false, isActing: true))
        surface.layoutSubtreeIfNeeded()
        let capsule = try XCTUnwrap(surface.capsule)
        XCTAssertEqual(capsule.frame.midX, surface.bounds.midX, accuracy: 1, "the capsule is not centred")
        let glass = try XCTUnwrap(capsule.subviews.first { $0 is GlassBackingView }, "the capsule has no glass")
        XCTAssertEqual(glass.frame, capsule.bounds, "the glass reaches past the capsule")
    }
}
