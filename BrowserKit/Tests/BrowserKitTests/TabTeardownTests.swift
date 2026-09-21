import AppKit
import BrowserKit
import WebKit
import XCTest

/// What happens to a tab's sound when the tab is torn down.
///
/// The defect this was written for: a closed tab kept playing. Close a
/// pinned tab with a video running and the audio carried on in the background,
/// with nothing left on screen to stop it. `detach()` unhooked the view and let
/// go of it, on the reasoning that a deallocated `WKWebView` closes its page and
/// a closed page is silent — which is true of the last reference and says
/// nothing about the one before it. WebKit's own async completions, a floating
/// Picture-in-Picture window, element fullscreen and a snapshot in flight can
/// each outlive the teardown by an unbounded amount, and for as long as one
/// does, the page is still playing.
///
/// So the test holds the view itself. That is the point of it: this must
/// pass while something outlives the close, because that case is the bug, and a
/// test that let the view deallocate would pass without the fix.
///
/// An `XCTestCase` rather than a `Testing` suite like its neighbours: a real
/// `WKWebView` in a real window needs `setUp`/`tearDown` around the window and
/// the main actor for the whole of it.
@MainActor
final class TabTeardownTests: XCTestCase {

    private var window: NSWindow?

    override func tearDown() async throws { window = nil }

    func testATornDownTabIsSilentEvenWhenItsWebViewOutlivesIt() async throws {
        let controller = TabController(id: UUID(), dataStore: .nonPersistent())
        controller.activate()
        guard let view = controller.webView else { return XCTFail("the tab built no web view") }
        show(view)
        view.loadHTMLString(Self.page, baseURL: URL(string: "https://example.invalid/"))

        var audible = false
        for _ in 0..<100 {
            try await Task.sleep(for: .milliseconds(100))
            if controller.state.isPlayingAudio { audible = true; break }
        }
        XCTAssertTrue(audible, "the tone never played, so the silence below would prove nothing")

        controller.hibernate()
        XCTAssertNil(controller.webView, "the controller kept its view")
        try await Task.sleep(for: .milliseconds(500))
        let paused = try await view.evaluateJavaScript("document.querySelector('audio').paused") as? Bool
        XCTAssertEqual(paused, true, "a torn-down tab kept playing because something still held its view")
    }

    /// A web view nobody ever put on screen does not play anything, so a
    /// test that skipped this would assert silence it had arranged itself.
    private func show(_ view: WKWebView) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        view.frame = window.contentLayoutRect
        window.contentView?.addSubview(view)
        window.orderFrontRegardless()
        self.window = window
    }

    private static var page: String {
        """
        <html><body><audio src="data:audio/wav;base64,\(tone)" autoplay loop></audio></body></html>
        """
    }

    /// A second of 440 Hz, built here rather than checked in: a twenty-kilobyte
    /// base64 literal is neither readable nor within the line length, and what
    /// the test needs is only that the sound is real.
    private static var tone: String {
        let rate = 8_000
        let samples = (0..<rate).flatMap { index -> [UInt8] in
            let value = Int16(12_000 * sin(2 * .pi * 440 * Double(index) / Double(rate)))
            return [UInt8(truncatingIfNeeded: value), UInt8(truncatingIfNeeded: value >> 8)]
        }
        var wav = Data("RIFF".utf8)
        wav.append(little(UInt32(36 + samples.count)))
        wav.append(Data("WAVEfmt ".utf8))
        wav.append(little(UInt32(16)))                     // PCM header length
        wav.append(little(UInt16(1)))                      // PCM
        wav.append(little(UInt16(1)))                      // mono
        wav.append(little(UInt32(rate)))
        wav.append(little(UInt32(rate * 2)))               // bytes per second
        wav.append(little(UInt16(2)))                      // bytes per frame
        wav.append(little(UInt16(16)))                     // bits per sample
        wav.append(Data("data".utf8))
        wav.append(little(UInt32(samples.count)))
        wav.append(contentsOf: samples)
        return wav.base64EncodedString()
    }

    private static func little<T: FixedWidthInteger>(_ value: T) -> Data {
        withUnsafeBytes(of: value.littleEndian) { Data($0) }
    }
}
