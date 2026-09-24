// The app's `ControlCapture` under `swift test`, through the same kind of
// link as `ControlStage.swift`: screenshots at a scale and of a region, and
// the recording's GIF, from a web view in no window.

import AppKit
import ImageIO
import LunaControl
import WebKit
import XCTest

@MainActor
final class ControlCaptureTests: XCTestCase {

    /// A red box at 100,100–300,200 on white, and a card field whose digits
    /// the tests swap.
    static let fixture = """
    <!doctype html><meta charset=utf-8>
    <style>body{margin:0;background:#fff}</style>
    <div style="position:absolute;left:100px;top:100px;width:200px;height:100px;background:#f00"></div>
    <input id=card autocomplete=cc-number value="4111111111111111"
      style="position:absolute;left:0;top:300px;width:600px;height:80px;font:48px monospace;border:0;outline:0">
    """

    private var webView: WKWebView!

    override func setUp() async throws {
        // Before anything makes a plain `NSApp`, so the stage suite still gets its own.
        _ = StageTestApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), configuration: configuration)
        webView.loadHTMLString(Self.fixture, baseURL: URL(string: "https://example.com/"))
        for _ in 0 ..< 100 {
            if try await webView.evaluateJavaScript("!!document.getElementById('card')") as? Bool == true { break }
            try await Task.sleep(for: .milliseconds(30))
        }
    }

    private func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> (Int, Int, Int) {
        var rgba = [UInt8](repeating: 0, count: 4)
        let context = CGContext(
            data: &rgba, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(image, in: CGRect(x: -x, y: y - image.height + 1, width: image.width, height: image.height))
        return (Int(rgba[0]), Int(rgba[1]), Int(rgba[2]))
    }

    func testZoomRegionSize() async throws {
        let whole = try await ControlCapture.image(of: webView, scale: 0.5)
        XCTAssertEqual([whole.width, whole.height], [400, 300])
        let box = ControlCommand.Region(x: 100, y: 100, width: 200, height: 100)
        let zoom = try await ControlCapture.image(of: webView, region: box)
        XCTAssertEqual([zoom.width, zoom.height], [200, 100])
        // The region is the box itself: red corner to corner, so it was taken
        // from the top left, not from AppKit's bottom left.
        for (x, y) in [(2, 2), (197, 2), (2, 97), (197, 97)] {
            let (red, green, blue) = pixel(zoom, x, y)
            XCTAssert(red > 200 && green < 60 && blue < 60, "\(x),\(y) is \(red),\(green),\(blue)")
        }
        let small = try await ControlCapture.image(of: webView, scale: 0.25, region: box)
        XCTAssertEqual([small.width, small.height], [50, 25])
    }

    /// Same length, other digits: masked, the two pictures are the same dots.
    func testCardFieldMaskedAtAnyScaleAndRegion() async throws {
        let field = ControlCommand.Region(x: 0, y: 300, width: 600, height: 80)
        for (scale, region) in [(1.0, nil), (0.5, field), (0.2, nil)] as [(Double, ControlCommand.Region?)] {
            _ = try await webView.evaluateJavaScript("card.value = '4111111111111111'")
            let first = try await ControlCapture.image(of: webView, scale: scale, region: region)
            _ = try await webView.evaluateJavaScript("card.value = '5555555555554444'")
            let second = try await ControlCapture.image(of: webView, scale: scale, region: region)
            XCTAssertEqual(ControlCapture.png(first), ControlCapture.png(second), "scale \(scale), region \(String(describing: region))")
        }
        let security = try await webView.evaluateJavaScript("getComputedStyle(card).webkitTextSecurity") as? String
        XCTAssertEqual(security, "none", "the field is put back after the picture")
    }

    func testGifHasFrames() async throws {
        var recording = ControlRecording()
        for step in 0 ..< 3 {
            _ = try await webView.evaluateJavaScript("document.body.style.background = '#\(step)\(step)\(step)'")
            try await recording.add(ControlCapture.frame(of: webView, marks: [CGPoint(x: 150, y: 150)]))
        }
        let url = URL.temporaryDirectory.appending(path: "luna-capture-\(UUID().uuidString).gif")
        defer { try? FileManager.default.removeItem(at: url) }
        try ControlCapture.writeGIF(recording.frames, to: url)
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        XCTAssertEqual(CGImageSourceGetCount(source), 3)
        XCTAssertEqual(CGImageSourceGetType(source) as String?, "com.compuserve.gif")
    }

    func testRecordingKeepsTheNewestFrames() async throws {
        var recording = ControlRecording()
        let frame = try await ControlCapture.frame(of: webView, marks: [])
        for _ in 0 ..< ControlTools.frameLimit + 5 { recording.add(frame) }
        XCTAssertEqual(recording.frames.count, ControlTools.frameLimit)
    }
}
