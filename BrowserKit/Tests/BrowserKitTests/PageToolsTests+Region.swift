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

    // MARK: - The rectangle

    /// Square and without its label, as the crop is; the same black line and white halo as the outline.
    func testADragDrawsTheRectangle() async throws {
        _ = try await describeCards()
        try await pointer("pointerdown", x: 60, y: 30)
        try await pointer("pointermove", x: 200, y: 80)
        try await pointer("pointermove", x: 490, y: 130)
        let drawn = try await regionOutline()
        XCTAssertEqual(drawn, [60, 30, 430, 100])

        let read = try await controller.webView?.evaluateJavaScript("window.__lunaPicker.look()", contentWorld: .defaultClient)
        let look = try XCTUnwrap(read as? [String: String])
        XCTAssertEqual(look["border"], "rgb(0, 0, 0)")
        XCTAssertEqual(look["shadow"], "rgb(255, 255, 255) 0px 0px 0px 2px")
        XCTAssertEqual(look["radius"], "0px", "the rectangle has rounded corners")
        XCTAssertEqual(look["tagShown"], "none", "the rectangle carries the element's label")
    }

    /// The press gave the page the keyboard, so its Escape reaches the picker first.
    func testEscapeMidDragCancelsTheDragNotTheMode() async throws {
        let picks = try await describeCards()
        try await pointer("pointerdown", x: 60, y: 30)
        try await pointer("pointermove", x: 490, y: 130)
        _ = try await page("document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true })); 1")
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(controller.isDescribingElements, "Escape mid-drag ended comment mode")
        let cancelled = try await regionOutline()
        XCTAssertEqual(cancelled, [])

        try await pointer("pointerup", x: 490, y: 130)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(picks.all.count, 0, "the cancelled drag still picked")
    }

    /// The rectangle is fixed to the viewport, so the page moving under it would make it lie.
    func testAScrollMidDragCancelsIt() async throws {
        let picks = try await describeCards()
        _ = try await page("document.body.appendChild(document.createElement('div')).style.height = '3000px'; 1")
        try await pointer("pointerdown", x: 60, y: 30)
        try await pointer("pointermove", x: 490, y: 130)
        _ = try await page("scrollTo(0, 50); 1")
        for _ in 0 ..< 25 {
            if try await regionOutline() == [] { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        let cancelled = try await regionOutline()
        XCTAssertEqual(cancelled, [])

        try await pointer("pointerup", x: 490, y: 130)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(picks.all.count, 0, "the cancelled drag still picked")
        XCTAssertTrue(controller.isDescribingElements)
    }

    // MARK: - Collect and post

    func testADragListsExactlyTheCardsInside() async throws {
        let picks = try await describeCards()
        try await drag(from: (60, 30), to: (490, 130))
        for _ in 0 ..< 50 where picks.regions.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(picks.regions.count, 1)
        let (region, container) = try XCTUnwrap(picks.regions.first)

        XCTAssertEqual(region.contents.map(\.selector), (2 ... 4).map { "#plans > article:nth-of-type(\($0))" })
        XCTAssertEqual(region.contents.map(\.tag), ["article", "article", "article"])
        XCTAssertEqual(region.contents.map(\.text), ["Plan 2 Start", "Plan 3 Start", "Plan 4 Start"])
        XCTAssertEqual(region.contents.first?.box, PageElement.Box(x: 140, y: 40, width: 100, height: 80))
        XCTAssertFalse(region.contents.contains { $0.html.contains("value=") }, "a form value reached the region")
        XCTAssertTrue(region.contents[0].html.hasPrefix(#"<article class="card" data-plan="p2""#), region.contents[0].html)
        XCTAssertEqual(region.more, 0)
        XCTAssertEqual(region.box, PageElement.Box(x: 60, y: 30, width: 430, height: 100))
        XCTAssertEqual(container.tag, "section")
        XCTAssertEqual(container.selector, "#plans")
        XCTAssertEqual(picks.all.count, 0, "the drag was also taken for a click")
    }

    func testTheListStopsAtTwentyAndCountsTheRest() async throws {
        let tiles = (1 ... 30).map { #"<span data-n="\#($0)" style="display:inline-block;width:20px;height:20px"></span>"# }
        try await load(#"<body style="margin:0"><div style="padding:10px;width:400px">\#(tiles.joined())</div></body>"#)
        let picks = Picks()
        controller.startDescribingElements { picks.all.append($0) } onRegion: { picks.regions.append(($0, $1)) } onEnd: {}
        try await Task.sleep(for: .milliseconds(100))
        try await drag(from: (5, 5), to: (700, 200))
        for _ in 0 ..< 50 where picks.regions.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        let region = try XCTUnwrap(picks.regions.first?.0)

        XCTAssertEqual(region.contents.count, 20)
        XCTAssertEqual(region.more, 10)
        XCTAssertEqual(region.contents.last?.html, #"<span data-n="20" style="display:inline-block;width:20px;height:20px"></span>"#)
    }

    /// A rectangle under 6 CSS px on a side is a slip, not an area.
    func testAThinDragPostsNothing() async throws {
        let picks = try await describeCards()
        try await drag(from: (60, 30), to: (490, 33))
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(picks.regions.count, 0, "a thin drag posted a region")
        XCTAssertEqual(picks.all.count, 0, "a thin drag picked an element")
    }

    // MARK: - Support

    private func describeCards() async throws -> Picks {
        try await load(Self.cards)
        let picks = Picks()
        controller.startDescribingElements { picks.all.append($0) } onRegion: { picks.regions.append(($0, $1)) } onEnd: {}
        try await Task.sleep(for: .milliseconds(100))
        return picks
    }

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

    /// A press, a move halfway and to the end, and the release there.
    private func drag(from start: (Double, Double), to end: (Double, Double)) async throws {
        try await pointer("pointerdown", x: start.0, y: start.1)
        try await pointer("pointermove", x: (start.0 + end.0) / 2, y: (start.1 + end.1) / 2)
        try await pointer("pointermove", x: end.0, y: end.1)
        try await pointer("pointerup", x: end.0, y: end.1)
    }

    private func regionOutline() async throws -> [Double]? {
        try await controller.webView?.evaluateJavaScript("window.__lunaPicker.outline()", contentWorld: .defaultClient)
            as? [Double]
    }
}
