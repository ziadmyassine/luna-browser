//
//  ChromeTransitionTests.swift
//  LunaTests
//
//  What the page is asked to do while `⌘S` moves the chrome.
//
//  A web view's width is the expensive thing about it: change it and the web
//  process re-flows the document. The sidebar changes it by 280 pt, so a
//  transition that hands the page a new width on every frame of its 0.20 s
//  buys twelve re-flows for one layout change — which is what a page counting
//  its own `resize` events saw before `ContentCardView` was made to hold one
//  width across the whole slide: 13 hiding, 10 showing.
//
//  The stand-in counts `setFrameSize` and records whether the animation was
//  running when it arrived, because "how many" is only half of it: a single
//  re-flow inside an animating transaction is still animated, and an animated
//  width is a width per frame.
//

import XCTest
@testable import Luna

@MainActor
final class ChromeTransitionTests: XCTestCase {

    private final class PageStub: NSView {
        var resizes: [(size: NSSize, animating: Bool)] = []

        override func setFrameSize(_ newSize: NSSize) {
            if newSize != frame.size {
                resizes.append((newSize, NSAnimationContext.current.allowsImplicitAnimation))
            }
            super.setFrameSize(newSize)
        }
    }

    private func shown() throws -> (window: BrowserWindowController, page: PageStub) {
        let controller = BrowserWindowController()
        let root = try XCTUnwrap(controller.window?.contentView)
        let page = PageStub()
        controller.setContent(page)
        root.layoutSubtreeIfNeeded()
        page.resizes = []
        return (controller, page)
    }

    /// The one that was failing. Hiding and showing are one re-flow each, and
    /// neither happens while anything is moving.
    func testThePageIsNeverResizedInsideTheChromeAnimation() throws {
        let (window, page) = try shown()
        window.setSidebarCollapsed(true)
        window.setSidebarCollapsed(false)
        XCTAssertEqual(
            page.resizes.filter(\.animating).count,
            0,
            "a page resized inside the transaction is a page resized once a frame"
        )
    }

    /// The rule that makes one re-flow enough: the page is held at the wider of
    /// the two widths, so the card's edge has something to reveal on the way out
    /// and something to cover on the way back.
    func testTheWiderOfTheTwoWidthsIsTheOneHeld() throws {
        let (window, page) = try shown()
        let inset = window.contentFrame.width

        window.setSidebarCollapsed(true)
        let hidden = window.contentFrame.width
        XCTAssertGreaterThan(hidden, inset, "hiding the sidebar should widen the pane")
        XCTAssertEqual(page.frame.width, hidden, accuracy: 0.5, "hiding should re-flow the page up front")

        page.resizes = []
        window.setSidebarCollapsed(false)
        XCTAssertEqual(
            page.frame.width,
            hidden,
            accuracy: 0.5,
            "showing should hold the page at the width it already has, and narrow it once the slide is over"
        )
    }

    /// And it does end up the width of the pane, both ways round. The hold is a
    /// hold, not a new resting state — `endGeometryTransition` hands the width
    /// back to Auto Layout, and a watchdog does it even if the completion
    /// handler never arrives.
    func testThePageEndsAtThePanesWidth() async throws {
        let (window, page) = try shown()
        for collapsed in [true, false] {
            window.setSidebarCollapsed(collapsed)
            try await Task.sleep(for: .milliseconds(600))
            XCTAssertEqual(page.frame.width, window.contentFrame.width, accuracy: 0.5)
        }
    }
}
