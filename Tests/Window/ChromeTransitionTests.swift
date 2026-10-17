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

    /// The agent panel moves the pane's trailing edge, so the page is held by
    /// its leading one. Held by the trailing edge, as for the sidebar, it slid
    /// 340 pt sideways with the panel and jumped back when the slide ended.
    func testThePageKeepsItsLeadingEdgeWhileTheAgentPanelSlides() throws {
        let (window, page) = try shown()
        let start = page.frame.minX
        window.setAgentPanel(AgentPanelView(), shown: true)
        XCTAssertEqual(page.frame.minX, start, accuracy: 0.5, "showing the panel should not move the page sideways")
        window.setAgentPanel(AgentPanelView(), shown: false)
        XCTAssertEqual(page.frame.minX, start, accuracy: 0.5, "nor should hiding it")
        XCTAssertEqual(page.resizes.filter(\.animating).count, 0)
    }

    /// A window whose last tab has closed. The page's constraints hold it
    /// unretained, and kept past it they were activated on a freed view the
    /// next time the chrome moved: Luna crashed opening the agent panel.
    /// Freed memory need not crash at once, so the test asks for the cause:
    /// nothing is kept that names the page after it has left.
    func testTheChromeMovesOverAPaneWhosePageHasGone() throws {
        let card = ContentCardView()
        let page = PageStub()
        card.setContent(page)
        XCTAssertFalse(card.contentEdges.isEmpty)
        card.setContent(nil)
        XCTAssertTrue(card.contentEdges.isEmpty, "edges kept past their page outlive it once its tab closes")
        card.beginGeometryTransition(toWidth: 600, over: 0.2, holding: .leading)
        card.endGeometryTransition()
    }

    /// A page in element fullscreen: WebKit puts a placeholder in its place
    /// and moves it to a window of its own. There it is sized by frame, and
    /// the chrome leaves it alone: the sidebar toggled once held it by a width
    /// alone and activated an edge to a card it was no longer in (an
    /// exception). Back in the card, it follows the pane again.
    func testTheChromeLeavesAPageInFullscreenAlone() async throws {
        let (window, page) = try shown()
        let card = try XCTUnwrap(page.superview as? ContentCardView)
        // WebKit's order: the window built at no size, the page put in at its
        // bounds, then the window grown to the screen with the page expected
        // to follow. Something in it is laid out by constraints, as WebKit's
        // own views are. Held by constraints, the page stayed 0 × 0, and a
        // paused video showed black.
        let fullscreen = NSWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: true)
        let stage = try XCTUnwrap(fullscreen.contentView)
        let constrained = NSView()
        constrained.translatesAutoresizingMaskIntoConstraints = false
        stage.addSubview(constrained)
        NSLayoutConstraint.activate([
            constrained.topAnchor.constraint(equalTo: stage.topAnchor),
            constrained.leadingAnchor.constraint(equalTo: stage.leadingAnchor),
            constrained.widthAnchor.constraint(equalToConstant: 1),
            constrained.heightAnchor.constraint(equalToConstant: 1)
        ])
        let placeholder = NSView(frame: page.frame)
        card.addSubview(placeholder, positioned: .above, relativeTo: page)
        stage.addSubview(page)
        page.frame = stage.bounds
        page.autoresizingMask = [.width, .height]
        fullscreen.setFrame(NSRect(x: 0, y: 0, width: 900, height: 600), display: false)
        stage.layoutSubtreeIfNeeded()
        XCTAssertEqual(page.frame.size, stage.bounds.size, "the page did not grow with WebKit's fullscreen window")

        window.setSidebarCollapsed(true)
        window.setAgentPanel(AgentPanelView(), shown: true)
        stage.layoutSubtreeIfNeeded()
        XCTAssertEqual(page.frame.size, stage.bounds.size, "the chrome reached the page in WebKit's window")
        XCTAssertTrue(page.constraints.filter(\.isActive).isEmpty, "the page took a width into WebKit's window")

        card.addSubview(page, positioned: .above, relativeTo: placeholder)
        page.frame = placeholder.frame
        placeholder.removeFromSuperview()
        window.setAgentPanel(AgentPanelView(), shown: false)
        window.setSidebarCollapsed(false)
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertEqual(page.frame.width, window.contentFrame.width, accuracy: 0.5, "back in the card, the page kept its old frame")
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
