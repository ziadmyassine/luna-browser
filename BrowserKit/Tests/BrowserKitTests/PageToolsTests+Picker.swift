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

    // MARK: - Walking

    /// `elementFromPoint` only ever gives the innermost leaf, so a container is
    /// reached by walking up from it.
    private static let sidebar = """
    <body style="margin:0">
    <aside style="width:400px">
      <div class="sub-sidebar" style="padding:20px">
        <nav style="padding:10px">
          <a href="/a" style="display:block;height:30px">Alpha</a>
          <a href="/b" style="display:block;height:30px">Beta</a>
        </nav>
      </div>
    </aside>
    <p id="other" style="height:50px">Elsewhere</p>
    <script>window.keys = []; addEventListener('keydown', e => keys.push(e.key))</script>
    </body>
    """

    func testUpWalksToTheParentAndTheOutlineFollows() async throws {
        let picked = try await describeSidebar()
        try await hover(x: 50, y: 45)
        let leaf = try await rect(of: "a[href='/a']")
        let onLeaf = try await outline()
        XCTAssertEqual(onLeaf, leaf)
        try await walk("walk(true)")
        try await walk("walk(true)")
        let container = try await rect(of: ".sub-sidebar")
        let walked = try await outline()
        XCTAssertEqual(walked, container)

        try await walk("commit()")
        for _ in 0 ..< 50 where picked.all.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(picked.all.map(\.selector), ["div.sub-sidebar"])
    }

    func testDownWalksBackTowardTheLeaf() async throws {
        let picked = try await describeSidebar()
        try await hover(x: 50, y: 45)
        try await walk("walk(true)")
        try await walk("walk(true)")
        try await walk("walk(false)")
        let nav = try await rect(of: "nav")
        let walked = try await outline()
        XCTAssertEqual(walked, nav)
        try await walk("walk(false)")
        try await walk("walk(false)")
        let leaf = try await rect(of: "a[href='/a']")
        let back = try await outline()
        XCTAssertEqual(back, leaf, "down walked past the element first outlined")

        try await walk("commit()")
        for _ in 0 ..< 50 where picked.all.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(picked.all.map(\.tag), ["a"])
    }

    func testMovingThePointerReleasesTheWalk() async throws {
        _ = try await describeSidebar()
        try await hover(x: 50, y: 45)
        try await walk("walk(true)")
        try await hover(x: 60, y: 50)
        let nav = try await rect(of: "nav")
        let locked = try await outline()
        XCTAssertEqual(locked, nav, "a move within the same leaf released the walk")
        try await hover(x: 50, y: 160)
        let other = try await rect(of: "#other")
        let released = try await outline()
        XCTAssertEqual(released, other)
    }

    /// Nothing outlined, nothing walked: Swift hands the key on when told so.
    func testAWalkWithNothingOutlinedSaysSo() async throws {
        _ = try await describeSidebar()
        let walked = try await walk("walk(true)")
        let committed = try await walk("commit()")
        XCTAssertEqual([walked, committed], [false, false])
    }

    func testHideIgnoresTheArrows() async throws {
        try await load(Self.sidebar)
        controller.startPickingElements { _ in } onEnd: {}
        try await Task.sleep(for: .milliseconds(100))
        try await hover(x: 50, y: 45)
        try await key("ArrowUp")
        try await key("Enter")
        let walked = try await walk("walk(true)")
        let committed = try await walk("commit()")
        XCTAssertEqual([walked, committed], [false, false], "Hide walked, or committed")
        let leaf = try await rect(of: "a[href='/a']")
        let outlined = try await outline()
        XCTAssertEqual(outlined, leaf, "Hide walked, or committed on Enter")
        let keys = try await page("window.keys") as? [String]
        XCTAssertEqual(keys, ["ArrowUp", "Enter"], "Hide swallowed keys it does not use")
    }

    func testDescribingIsNotHiding() async throws {
        try await load(Self.sidebar)
        controller.startDescribingElements { _ in } onEnd: {}
        XCTAssertTrue(controller.isDescribingElements)
        XCTAssertFalse(controller.isPickingElements)
        controller.startPickingElements { _ in } onEnd: {}
        XCTAssertFalse(controller.isPickingElements, "Hide started over comment mode")
        controller.stopDescribingElements()
        XCTAssertFalse(controller.isDescribingElements)
    }

    // MARK: - Support

    /// Picks land here from the picker's callback.
    final class Picks { var all: [PageElement] = [] }

    private func describeSidebar() async throws -> Picks {
        try await load(Self.sidebar)
        let picks = Picks()
        controller.startDescribingElements { picks.all.append($0) } onEnd: {}
        try await Task.sleep(for: .milliseconds(100))
        return picks
    }

    private func hover(x: Double, y: Double) async throws {
        _ = try await page("dispatchEvent(new MouseEvent('mousemove', { clientX: \(x), clientY: \(y) })); 1")
    }

    private func key(_ name: String) async throws {
        _ = try await page("document.dispatchEvent(new KeyboardEvent('keydown', { key: '\(name)', bubbles: true })); 1")
    }

    /// Comment mode's walk, called in the picker's world as Swift calls it.
    @discardableResult
    private func walk(_ call: String) async throws -> Bool {
        try await controller.webView?.callAsyncJavaScript(
            "return window.__lunaPicker.\(call)", arguments: [:], in: nil, contentWorld: .defaultClient
        ) as? Bool ?? false
    }

    private func rect(of selector: String) async throws -> [Double]? {
        try await page("""
        var r = document.querySelector("\(selector)").getBoundingClientRect(); [r.x, r.y, r.width, r.height]
        """) as? [Double]
    }

    /// Where the picker put its outline, read in the picker's own world.
    private func outline() async throws -> [Double]? {
        try await controller.webView?.evaluateJavaScript("window.__lunaPicker.outline()", contentWorld: .defaultClient)
            as? [Double]
    }

    /// A press where the pointer is, as the picker hears one.
    func press(x: Double, y: Double) async throws {
        _ = try await page("""
        document.dispatchEvent(new PointerEvent('pointerdown',
          { bubbles: true, cancelable: true, clientX: \(x), clientY: \(y), button: 0 })); 1
        """)
    }
}
