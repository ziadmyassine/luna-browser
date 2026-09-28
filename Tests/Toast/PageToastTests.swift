//
//  PageToastTests.swift
//  LunaTests
//
//  A page toast drops from under the bar, centred, takes no clicks, is
//  rewritten rather than stacked, and goes back up after its dwell.
//

import AppKit
import XCTest
@testable import Luna

@MainActor
final class PageToastTests: XCTestCase {

    private func surface() -> ControlSurfaceView {
        let surface = ControlSurfaceView(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
        surface.topInset = 52
        return surface
    }

    func testAToastDropsCentredUnderTheBar() async throws {
        let surface = surface()
        surface.showToast(.linkCopied)
        try await Task.sleep(for: .milliseconds(400))
        surface.layoutSubtreeIfNeeded()
        let toast = try XCTUnwrap(surface.toast)
        XCTAssertEqual(toast.text, PageToast.linkCopied.text)
        XCTAssertEqual(toast.alphaValue, 1, accuracy: 0.01)
        XCTAssertEqual(toast.frame.midX, surface.bounds.midX, accuracy: 1, "the toast is not centred")
        XCTAssertEqual(toast.frame.minY, 52 + Tokens.Metric.chromeGap, accuracy: 1, "the toast is not under the bar")
        XCTAssertEqual(toast.frame.height, Tokens.Agent.capsuleHeight, accuracy: 0.5)
    }

    func testTheToastLetsThePageKeepItsClicks() throws {
        let surface = surface()
        surface.showToast(.linkCopied)
        surface.layoutSubtreeIfNeeded()
        let toast = try XCTUnwrap(surface.toast)
        XCTAssertNil(surface.hitTest(NSPoint(x: toast.frame.midX, y: toast.frame.midY)))
    }

    func testASecondToastRewritesTheFirst() throws {
        let surface = surface()
        surface.showToast(.linkCopied)
        let first = try XCTUnwrap(surface.toast)
        surface.showToast(.zoom(1.25))
        XCTAssertTrue(surface.toast === first, "a second toast stacked on the first")
        XCTAssertEqual(first.text, PageToast.zoom(1.25).text)
        XCTAssertEqual(surface.subviews.filter { $0 is PageToastView }.count, 1)
    }

    func testTheToastGoesBackUpAfterItsDwell() async throws {
        let surface = surface()
        surface.showToast(.cachesEmptied)
        let toast = try XCTUnwrap(surface.toast)
        try await Task.sleep(for: .seconds(Tokens.Motion.toastDwell + 0.6))
        XCTAssertNil(surface.toast)
        XCTAssertNil(toast.superview, "the toast stayed after its dwell")
    }

    func testZoomSaysThePercentage() {
        XCTAssertEqual(PageToast.zoom(1.25).text, "Zoom 125 %")
        XCTAssertEqual(PageToast.archived(1).text, "1 tab archived")
        XCTAssertEqual(PageToast.archived(4).text, "4 tabs archived")
    }
}
