@testable import BrowserKit
import XCTest

/// Comment mode's selection marker, which stays on what was picked while its
/// note is open. Apart from `PageToolsTests+Picker.swift` only for SwiftLint's length limits.
extension PageToolsTests {

    /// Two 100 × 80 cards at 140,40 and 380,40, on a page tall enough to scroll.
    private static let pair = """
    <body style="margin:0">
    <div id="one" style="position:absolute;left:140px;top:40px;width:100px;height:80px">One</div>
    <div id="two" style="position:absolute;left:380px;top:40px;width:100px;height:80px">Two</div>
    <div style="height:3000px"></div>
    </body>
    """

    private static let first = "{ x: 140, y: 40, width: 100, height: 80 }"

    func testTheMarkIsDrawnAtTheBox() async throws {
        _ = try await describePair()
        try await picker("mark(\(Self.first))")
        let marked = try await picker("marked()") as? [Double]
        XCTAssertEqual(marked, [140, 40, 100, 80])
    }

    /// The hover outline is its own element: pointing elsewhere moves it and leaves the mark.
    func testAHoverElsewhereMovesOnlyTheOutline() async throws {
        _ = try await describePair()
        try await picker("mark(\(Self.first))")
        _ = try await page("dispatchEvent(new MouseEvent('mousemove', { clientX: 420, clientY: 70 })); 1")
        let outlined = try await picker("outline()") as? [Double]
        XCTAssertEqual(outlined, [380, 40, 100, 80])
        let marked = try await picker("marked()") as? [Double]
        XCTAssertEqual(marked, [140, 40, 100, 80], "the hover moved the mark")
    }

    func testTheMarkStaysOnThePageAsItScrolls() async throws {
        _ = try await describePair()
        try await picker("mark(\(Self.first))")
        _ = try await page("scrollBy(0, 30); 1")
        var marked: [Double]?
        for _ in 0 ..< 25 {
            marked = try await picker("marked()") as? [Double]
            if marked == [140, 10, 100, 80] { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(marked, [140, 10, 100, 80])
    }

    func testUnmarkRemovesTheMark() async throws {
        _ = try await describePair()
        try await picker("mark(\(Self.first))")
        try await picker("unmark()")
        let marked = try await picker("marked()") as? [Double]
        XCTAssertEqual(marked, [])
    }

    /// The next pick is pictured as soon as it posts, so the old mark is gone by then.
    func testTheNextPickTakesTheMarkAwayBeforeItPosts() async throws {
        let picks = try await describePair()
        try await picker("mark(\(Self.first))")
        _ = try await page("""
        ['pointerdown', 'pointerup'].forEach(function (kind) {
          document.dispatchEvent(new PointerEvent(kind, { bubbles: true, cancelable: true, clientX: 420, clientY: 70, button: 0 }));
        });
        1
        """)
        for _ in 0 ..< 50 where picks.all.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(picks.all.map(\.selector), ["#two"])
        let marked = try await picker("marked()") as? [Double]
        XCTAssertEqual(marked, [])
    }

    func testHideNeverMarks() async throws {
        try await load(Self.pair)
        controller.startPickingElements { _ in } onEnd: {}
        try await Task.sleep(for: .milliseconds(100))
        try await picker("mark(\(Self.first))")
        let marked = try await picker("marked()") as? [Double]
        XCTAssertEqual(marked, [])
    }

    // MARK: - Support

    private func describePair() async throws -> Picks {
        try await load(Self.pair)
        let picks = Picks()
        controller.startDescribingElements { picks.all.append($0) } onRegion: { picks.regions.append(($0, $1)) } onEnd: {}
        try await Task.sleep(for: .milliseconds(100))
        return picks
    }

    @discardableResult
    private func picker(_ call: String) async throws -> Any? {
        try await controller.webView?.evaluateJavaScript("window.__lunaPicker.\(call)", contentWorld: .defaultClient)
    }
}
