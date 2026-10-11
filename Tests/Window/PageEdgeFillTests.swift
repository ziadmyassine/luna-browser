//
//  PageEdgeFillTests.swift
//  LunaTests
//
//  What fills the strip of a web view that WebKit has not painted yet (#218).
//
//  `ContentCardView.beginGeometryTransition` widens the page in one step when
//  the sidebar hides. AppKit grows the web view's own layer in that turn; the
//  layers the web process draws keep their old width until its next commit, a
//  few frames later. The strip between the two is the web view's backing
//  layer, and WebKit fills that from the view's appearance — `#1e1e1e` under
//  dark chrome, whatever the page is. That was the black band down the page's
//  trailing edge. Real web views, because the lag is WebKit's.
//

import XCTest
import WebKit
@testable import Luna

@MainActor
final class PageEdgeFillTests: XCTestCase {

    private var window: NSWindow?

    override func tearDown() async throws {
        window?.close()
        window = nil
    }

    /// A light page in a card beside a 270 pt sidebar, under dark chrome.
    /// Off-screen and never ordered key.
    private func lightPageInCard() async throws -> (ContentCardView, WKWebView) {
        let window = NSWindow(
            contentRect: NSRect(x: -20_000, y: -20_000, width: 1000, height: 600),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        self.window = window
        let root = try XCTUnwrap(window.contentView)
        let card = ContentCardView()
        card.pin(in: root)
        card.setInsets(NSEdgeInsets(top: 0, left: 270, bottom: 0, right: 0))
        let web = LunaWebView(frame: .zero, configuration: WKWebViewConfiguration())
        card.setContent(web)
        window.orderFrontRegardless()
        root.layoutSubtreeIfNeeded()
        web.loadHTMLString("<html><body><p>page</p></body></html>", baseURL: nil)
        try await settle { !web.isLoading && Self.paintedWidth(of: web) == web.bounds.width }
        return (card, web)
    }

    private func settle(until condition: () -> Bool) async throws {
        for _ in 0..<200 where !condition() { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertTrue(condition(), "the page never painted")
    }

    /// How wide the web process last drew the page: its under-page layer, which
    /// spans the whole view once a commit has caught up with the view's size.
    private static func paintedWidth(of web: WKWebView) -> CGFloat? {
        func find(_ layer: CALayer) -> CALayer? {
            if layer.name == "overhang areas" { return layer }
            return layer.sublayers?.lazy.compactMap(find).first
        }
        return web.layer.flatMap(find)?.bounds.width
    }

    private static func srgb(_ colour: CGColor?) -> [CGFloat] {
        guard let colour, let space = CGColorSpace(name: CGColorSpace.sRGB),
              let converted = colour.converted(to: space, intent: .defaultIntent, options: nil) else { return [] }
        return Array((converted.components ?? []).prefix(3))
    }

    private func assertFill(_ web: WKWebView, is wanted: [CGFloat], _ message: String, line: UInt = #line) {
        let fill = Self.srgb(web.layer?.backgroundColor)
        XCTAssertEqual(fill.count, 3, "no fill at all", line: line)
        for (have, want) in zip(fill, wanted) {
            XCTAssertEqual(have, want, accuracy: 0.02, "\(message) — fill \(fill)", line: line)
        }
    }

    /// The hide itself: the page is widened, and the strip WebKit has not
    /// painted yet is the page's colour rather than the chrome's.
    func testTheStripWebKitHasNotPaintedIsThePagesColour() async throws {
        let (card, web) = try await lightPageInCard()
        let page = Self.srgb(web.underPageBackgroundColor.cgColor)
        XCTAssertEqual(page.first ?? 0, 1, accuracy: 0.02, "the page should report itself white")

        card.beginGeometryTransition(toWidth: 1000, over: 0.2)
        let painted = try XCTUnwrap(Self.paintedWidth(of: web))
        XCTAssertLessThan(painted, web.bounds.width, "precondition: the web process has not caught up yet")
        assertFill(web, is: page, "the strip beyond the painted page shows the backing layer's fill")
        card.endGeometryTransition()
    }

    /// WebKit does not always say when the page's colour arrives. On CI's
    /// runner (light system, dark window) the page read white while no change
    /// was ever observed, and the fill kept the `#1e1e1e` it took from the
    /// window. Here the fill is left stale by hand, and widening the page has
    /// to correct it.
    func testWideningThePageFillsTheStripEvenIfTheColourWasNeverReported() async throws {
        let (card, web) = try await lightPageInCard()
        let page = Self.srgb(web.underPageBackgroundColor.cgColor)
        web.layer?.backgroundColor = NSColor(srgbRed: 0.118, green: 0.118, blue: 0.118, alpha: 1).cgColor

        card.beginGeometryTransition(toWidth: 1000, over: 0.2)
        assertFill(web, is: page, "the widened strip should show the page's colour, not a stale fill")
        card.endGeometryTransition()
    }

    /// The fill changes in the turn the page's colour does, not on the next
    /// display pass, which can land after the widening. No run loop turn
    /// passes between the change and the assertion here.
    func testTheFillChangesWithThePageColourBeforeAnyDisplayPass() async throws {
        let (_, web) = try await lightPageInCard()
        web.underPageBackgroundColor = NSColor(srgbRed: 0, green: 0.5, blue: 0, alpha: 1)
        assertFill(web, is: [0, 0.5, 0], "the fill should change with the page's colour, not on the next display")
    }

    /// A page that repaints itself changes the fill with it, so the band cannot
    /// come back as yesterday's colour.
    func testTheFillFollowsThePageWhenItRepaints() async throws {
        let (_, web) = try await lightPageInCard()
        _ = try await web.evaluateJavaScript("document.body.style.background = '#3a0a0a'; 1")
        let wanted: [CGFloat] = [58, 10, 10].map { $0 / 255 }
        try await settle { Self.srgb(web.underPageBackgroundColor.cgColor).first.map { abs($0 - wanted[0]) < 0.02 } ?? false }
        try await settle { Self.srgb(web.layer?.backgroundColor).first.map { abs($0 - wanted[0]) < 0.02 } ?? false }
        assertFill(web, is: wanted, "the fill should follow the page's own colour")
    }
}
