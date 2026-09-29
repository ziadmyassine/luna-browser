//
//  PageToastTests.swift
//  LunaTests
//
//  A page toast drops from under the bar, centred, takes no clicks, is
//  rewritten rather than stacked, and goes back up after its dwell.
//

import AppKit
import BrowserKit
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

    /// An instruction for a mode stays down past its dwell until it is put away.
    func testAToastForAModeStaysUntilPutAway() async throws {
        let surface = surface()
        surface.showToast(.hidingStarted, dwells: false)
        try await Task.sleep(for: .seconds(Tokens.Motion.toastDwell + 0.6))
        XCTAssertEqual(surface.toast?.text, PageToast.hidingStarted.text)
        surface.hideToast()
        XCTAssertNil(surface.toast)
    }

    /// A count going up rewrites the toast without a new dwell: a page that
    /// blocks a pop-up every few seconds must not keep its toast down for good.
    func testACountUpKeepsTheFirstDeadline() async throws {
        let surface = surface()
        let first = PageToast.popupBlocked(count: 1, address: nil, shortcut: nil, open: {}, allow: {})
        surface.showToast(first)
        let deadline = try XCTUnwrap(surface.toastDeadline)
        try await Task.sleep(for: .milliseconds(200))
        let second = PageToast.popupBlocked(count: 2, address: nil, shortcut: nil, open: {}, allow: {})
        surface.showToast(second, keepsDeadline: true)
        XCTAssertEqual(surface.toast?.text, "2 pop-ups blocked")
        let kept = try XCTUnwrap(surface.toastDeadline)
        XCTAssertEqual(kept.timeIntervalSince(deadline), 0, accuracy: 0.05, "the count-up gave the toast a new dwell")
        // Any other toast is news of its own, and starts its own dwell.
        surface.showToast(.linkCopied)
        let own = try XCTUnwrap(surface.toastDeadline).timeIntervalSinceNow
        XCTAssertEqual(own, Tokens.Motion.toastDwell, accuracy: 0.1)
    }

    /// A pill that drops under a pointer resting there is not held by it;
    /// only a pointer that moves onto it is.
    func testOnlyAPointerThatMovesOntoTheToastHoldsIt() throws {
        let surface = surface()
        surface.showToast(.popupBlocked(count: 1, address: nil, shortcut: nil, open: {}, allow: {}))
        let toast = try XCTUnwrap(surface.toast)
        let event = try XCTUnwrap(NSEvent.mouseEvent(
            with: .mouseMoved, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
            context: nil, eventNumber: 0, clickCount: 0, pressure: 0
        ))
        toast.mouseEntered(with: event)
        XCTAssertNotNil(surface.toastDeadline, "arriving under the pointer stopped the dwell")
        toast.mouseMoved(with: event)
        XCTAssertNil(surface.toastDeadline, "a pointer on the words did not hold the toast")
        toast.mouseExited(with: event)
        XCTAssertNotNil(surface.toastDeadline, "the toast stayed after the pointer left")
    }

    func testZoomSaysThePercentage() {
        XCTAssertEqual(PageToast.zoom(1.25).text, "Zoom 125 %")
        XCTAssertEqual(PageToast.archived(1).text, "1 tab archived")
        XCTAssertEqual(PageToast.archived(4).text, "4 tabs archived")
    }

    /// The Reading pop-out's two: the saved file's name rides in `detail`.
    func testReadingSaysWhatItSavedAndCopied() {
        let saved = PageToast.savedToDownloads("README.md")
        XCTAssertEqual(saved.text, "Saved to Downloads")
        XCTAssertEqual(saved.detail, "README.md")
        XCTAssertEqual(PageToast.markdownTextCopied.text, "Markdown copied")
        XCTAssertNotEqual(PageToast.markdownTextCopied, PageToast.markdownCopied)
        for toast in [saved, PageToast.markdownTextCopied] {
            XCTAssertNotNil(NSImage(systemSymbolName: toast.symbol, accessibilityDescription: nil), toast.symbol)
        }
    }

    /// ⌘S in a Markdown editor. Distinct from Save to Downloads, which names a copy.
    func testSavingAnEditSaysSaved() {
        XCTAssertEqual(PageToast.saved.text, "Saved")
        XCTAssertNil(PageToast.saved.detail)
        XCTAssertNotEqual(PageToast.saved, PageToast.savedToDownloads("README.md"))
        XCTAssertNotNil(NSImage(systemSymbolName: PageToast.saved.symbol, accessibilityDescription: nil))
    }

    /// Each answer reads differently, and every symbol is one the system has:
    /// a misspelt name draws the pill with a gap where its glyph should be.
    func testReaderPictureInPictureAndHidingEachSayWhatHappened() {
        let toasts: [PageToast] = [
            .reader(.on), .reader(.off), .reader(.nothingToRead),
            .pictureInPicture(.floating), .pictureInPicture(.backInPage), .pictureInPicture(.noVideo),
            .hidingStarted, .hidden("Cookie bar"), .shownAgain("Cookie bar")
        ]
        XCTAssertEqual(Set(toasts.map(\.text)).count, toasts.count)
        for toast in toasts {
            XCTAssertNotNil(NSImage(systemSymbolName: toast.symbol, accessibilityDescription: nil), toast.symbol)
        }
        XCTAssertEqual(PageToast.hidden("Cookie bar").text, "Hidden: Cookie bar. ⌘Z brings it back.")
    }
}
