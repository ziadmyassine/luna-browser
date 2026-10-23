@testable import BrowserKit
import XCTest

/// Comment mode's press and drag, which captures an area rather than an
/// element. Apart from `PageToolsTests+Picker.swift` only for SwiftLint's length limits.
extension PageToolsTests {

    /// Five 100 × 80 cards at x = 20 + 120n, y = 40, and between the second and
    /// third an element of each kind that has no box on screen.
    private static let cards = """
    <body style="margin:0">
    <section id="plans" style="position:relative;height:200px">
    \((0 ..< 5).map(PageToolsTests.card).joined(separator: "\n"))
    </section>
    </body>
    """

    private nonisolated static func card(_ index: Int) -> String {
        let card = """
        <article class="card" data-plan="p\(index + 1)" \
        style="position:absolute;left:\(20 + 120 * index)px;top:40px;width:100px;height:80px">\
        <h3 style="margin:0">Plan \(index + 1)</h3><button value="hunter2">Start</button></article>
        """
        guard index == 1 else { return card }
        let at = "position:absolute;left:245px;top:50px"
        return card + """
        <div style="display:none;\(at);width:10px;height:10px">Gone</div>\
        <div style="\(at);width:0;height:0"></div>\
        <div style="visibility:hidden;\(at);width:10px;height:10px">Unseen</div>
        """
    }

    // MARK: - Clicks pick on release

    func testADragUnderTheThresholdIsAClick() async throws {
        try await load(Self.cards)
        let picks = Picks()
        controller.startDescribingElements { picks.all.append($0) } onEnd: {}
        try await Task.sleep(for: .milliseconds(100))
        try await pointer("pointerdown", x: 60, y: 30)
        try await pointer("pointermove", x: 64, y: 33)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(picks.all.count, 0, "a comment pick was made before the release")

        try await pointer("pointerup", x: 64, y: 33)
        for _ in 0 ..< 50 where picks.all.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(picks.all.map(\.selector), ["#plans"])
    }

    /// Hide files a rule at the press, and never draws a rectangle.
    func testHideDoesNotDrag() async throws {
        try await load(Self.cards)
        var picked: [HiddenElements.Element] = []
        controller.startPickingElements { picked.append($0) } onEnd: {}
        try await Task.sleep(for: .milliseconds(100))
        try await pointer("pointerdown", x: 60, y: 30)
        for _ in 0 ..< 50 where picked.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(picked.map(\.selector), ["#plans"], "Hide did not pick at the press")

        try await pointer("pointermove", x: 490, y: 130)
        let outlined = try await regionOutline()
        XCTAssertNotEqual(outlined, [60, 30, 430, 100], "Hide drew a rectangle")
        try await pointer("pointerup", x: 490, y: 130)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(picked.count, 1, "Hide picked again at the release")
    }

    // MARK: - Support

    /// A pointer event where the picker hears it. A move is sent as a browser
    /// sends one, `pointermove` then `mousemove`, with the button held after a press.
    private func pointer(_ kind: String, x: Double, y: Double) async throws {
        let kinds = kind == "pointermove" ? ["pointermove", "mousemove"] : [kind]
        _ = try await page("""
        \(kinds).forEach(function (kind) {
          var make = kind.indexOf('pointer') === 0 ? PointerEvent : MouseEvent;
          document.dispatchEvent(new make(kind, { bubbles: true, cancelable: true,
            clientX: \(x), clientY: \(y), button: 0, buttons: kind === 'pointerup' ? 0 : 1 }));
        });
        1
        """)
    }

    private func regionOutline() async throws -> [Double]? {
        try await controller.webView?.evaluateJavaScript("window.__lunaPicker.outline()", contentWorld: .defaultClient)
            as? [Double]
    }
}
