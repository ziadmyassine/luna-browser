@testable import BrowserKit
import XCTest

/// The picker and Hide Something on a page whose Content Security Policy
/// refuses inline style elements and style attributes alike, as some sites
/// send it. Apart from `PageToolsTests.swift` only for SwiftLint's length limits.
extension PageToolsTests {

    private static let strict = """
    <html><head><meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'self'"></head>
    <body><nav><a id="link" href="/a">Alpha</a></nav><div id="cookie-bar">We use cookies</div></body></html>
    """

    func testTheOutlineIsDrawnUnderAStrictPolicy() async throws {
        try await load(Self.strict)
        controller.startDescribingElements { _ in } onEnd: {}
        try await Task.sleep(for: .milliseconds(100))
        _ = try await page("dispatchEvent(new MouseEvent('mousemove', { clientX: 20, clientY: 15 })); 1")
        let look = try await controller.webView?.evaluateJavaScript("window.__lunaPicker.look()", contentWorld: .defaultClient)
        let styled = try XCTUnwrap(look as? [String: String])
        XCTAssertEqual(styled["position"], "fixed", "\(styled)")
        XCTAssertEqual(styled["borderWidth"], "2px", "\(styled)")
        let cursor = try await page("getComputedStyle(document.getElementById('link')).cursor") as? String
        XCTAssertEqual(cursor, "crosshair")
        controller.stopPickingElements()
    }

    func testAnElementIsHiddenUnderAStrictPolicy() async throws {
        try await load(Self.strict, host: "strict.invalid")
        controller.hiddenElements.hide(.init(selector: "#cookie-bar", label: "Cookie bar"), onHost: "strict.invalid")
        controller.applyHiddenElements()
        try await Task.sleep(for: .milliseconds(100))
        let display = try await page("getComputedStyle(document.getElementById('cookie-bar')).display") as? String
        XCTAssertEqual(display, "none")
    }
}
