//
//  PopoutAnchorTests.swift
//  LunaTests
//
//  Where History's and Downloads' pop-outs stand: their gap off the glass of
//  the capsule the button is in, in both layouts. §4's buttons sit inside
//  their capsule's padding, and a gap measured from the button stood the list
//  9 pt off the glass where §3.5's stands 5.
//

@testable import BrowserKit
import XCTest
@testable import Luna

@MainActor
final class PopoutAnchorTests: XCTestCase {

    private var directory: URL!

    override func setUp() async throws {
        directory = URL.temporaryDirectory.appending(path: "luna-popout-\(UUID().uuidString)")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    /// Up and down, the top bar's capsule; across, the button itself.
    func testATopBarPopOutStandsOffTheCapsulesGlass() async throws {
        let store = try BrowserStore(path: directory.appending(path: "luna.sqlite"))
        let session = try await BrowserSession.restored(store: store)
        let window = UUID()
        session.openWindow(window)
        let bar = TopBarView(session: session, windowID: window)
        bar.frame = NSRect(x: 0, y: 0, width: 1400, height: TopBarMetrics.barHeight)
        bar.layoutSubtreeIfNeeded()

        for anchor in [bar.historyAnchor, bar.downloadsAnchor] {
            let button = try XCTUnwrap(anchor)
            let capsule = try XCTUnwrap(button.superview)
            let glass = bar.convert(capsule.bounds, from: capsule)
            let own = bar.convert(button.bounds, from: button)
            XCTAssertLessThan(own.height, glass.height, "the capsule no longer pads its buttons")
            let rect = PopoutController.standingRect(of: button, in: bar)
            XCTAssertEqual(rect.minY, glass.minY)
            XCTAssertEqual(rect.maxY, glass.maxY)
            XCTAssertEqual(rect.minX, own.minX)
            XCTAssertEqual(rect.width, own.width)
        }
    }

    /// The sidebar's buttons fill their cylinder, so each is its own edge —
    /// the gap the top bar's now matches.
    func testTheSidebarsButtonsAreTheirOwnEdge() {
        let foot = SidebarUtilityBar()
        foot.frame = NSRect(x: 0, y: 0, width: 280, height: Tokens.Metric.topBarHeight)
        foot.layoutSubtreeIfNeeded()
        for button in [foot.historyAnchor, foot.downloadsAnchor] {
            let rect = PopoutController.standingRect(of: button, in: foot)
            XCTAssertEqual(rect, foot.convert(button.bounds, from: button))
            XCTAssertEqual(button.frame.height, try XCTUnwrap(button.superview).bounds.height, accuracy: 0.5)
        }
    }
}
