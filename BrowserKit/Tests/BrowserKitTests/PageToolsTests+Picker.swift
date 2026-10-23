@testable import BrowserKit
import XCTest

/// Comment mode's picker, which describes what was pressed. Apart from
/// `PageToolsTests.swift` only for SwiftLint's length limits.
extension PageToolsTests {

    /// Selector paths lowercase the tag, and a type selector matches an SVG
    /// element's name case-sensitively, so a path through `foreignObject`
    /// resolves to nothing.
    private static let drawing = """
    <body style="margin:0">
    <svg width="300" height="100" style="display:block"><foreignObject width="300" height="100">
    <div style="height:50px">First</div><div style="height:50px">Second</div>
    </foreignObject></svg>
    <div id="cookie-bar" style="height:100px">We use cookies</div>
    </body>
    """

    func testACommentPickIsKeptWhenItsSelectorIsNotUnique() async throws {
        try await load(Self.drawing)
        var picked: [PageElement] = []
        controller.startDescribingElements { picked.append($0) } onEnd: {}
        try await Task.sleep(for: .milliseconds(100))
        try await press(x: 50, y: 75)
        for _ in 0 ..< 50 where picked.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(picked.first?.selector, "body > svg > foreignobject > div:nth-of-type(2)")
        XCTAssertEqual(picked.first?.matches, 0)
    }

    /// Hide files a rule against the site, and a rule matching nothing is worse than no pick.
    func testHideStillDropsAPickItCannotFindAgain() async throws {
        try await load(Self.drawing)
        var picked: [HiddenElements.Element] = []
        controller.startPickingElements { picked.append($0) } onEnd: {}
        try await Task.sleep(for: .milliseconds(100))
        try await press(x: 50, y: 75)
        // Messages arrive in order, so once the second pick is in, the first was dropped.
        try await press(x: 50, y: 150)
        for _ in 0 ..< 50 where picked.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(picked.map(\.selector), ["#cookie-bar"])
    }

    private static let orders = """
    <body style="margin:0">
    <header>
      <h1>Orders</h1>
      <div>
        <input aria-label="Search orders" value="typed-secret">
        <button>Filter</button>
        <button class="btn primary" data-testid="new-order" value="hunter2" data-long="\(String(repeating: "x", count: 400))"
          style="position:absolute;left:200px;top:100px;width:132px;height:36px">
          New   order
          \(String(repeating: "and more ", count: 30))</button>
        <button>Export</button>
        <script>window.unrendered = 1</script>
      </div>
    </header>
    </body>
    """

    func testThePickerDescribesWhatWasPressedWhenAskedTo() async throws {
        try await load(Self.orders)
        var picked: [PageElement] = []
        controller.startDescribingElements { picked.append($0) } onEnd: {}
        try await Task.sleep(for: .milliseconds(100))
        try await press(x: 250, y: 110)
        for _ in 0 ..< 50 where picked.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        let element = try XCTUnwrap(picked.first)

        XCTAssertEqual(element.selector, "button[data-testid=\"new-order\"]")
        XCTAssertEqual(element.matches, 1)
        XCTAssertEqual(element.tag, "button")
        // The role attribute only: WebKit has no `computedRole`, and the tag says the implicit one.
        XCTAssertNil(element.role)
        XCTAssertTrue(element.text.hasPrefix("New order and more and more"), element.text)
        XCTAssertLessThanOrEqual(element.text.count, 120)
        XCTAssertTrue(element.html.hasPrefix("<button class=\"btn primary\" data-testid=\"new-order\""), element.html)
        XCTAssertLessThanOrEqual(element.html.count, 300)
        XCTAssertFalse(element.html.contains("value="), "a form value reached the description")
        XCTAssertFalse(element.html.contains("hunter2"))
        XCTAssertEqual(element.heading, "Orders")
        XCTAssertEqual(element.landmark, "header")
        XCTAssertEqual(element.siblings, ["Search orders", "Filter", "Export"])

        let rect = try await page("""
        var r = document.querySelector('[data-testid=new-order]').getBoundingClientRect();
        [r.x, r.y, r.width, r.height]
        """) as? [Double]
        XCTAssertEqual([element.box.x, element.box.y, element.box.width, element.box.height], rect)
    }

    // MARK: - Support

    /// A press where the pointer is, as the picker hears one.
    func press(x: Double, y: Double) async throws {
        _ = try await page("""
        document.dispatchEvent(new PointerEvent('pointerdown',
          { bubbles: true, cancelable: true, clientX: \(x), clientY: \(y), button: 0 })); 1
        """)
    }
}
