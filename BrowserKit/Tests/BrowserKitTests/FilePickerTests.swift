import AppKit
import BrowserKit
import WebKit
import XCTest

/// A page's `<input type=file>` reaches the host and gets the files it picks.
///
/// WebKit on macOS cancels the picker for a delegate that does not implement
/// `runOpenPanelWith`, so every upload button did nothing when clicked. The click is a
/// real mouse event because WebKit opens the picker only for a user gesture.
@MainActor
final class FilePickerTests: XCTestCase {

    private var window: NSWindow?

    override func tearDown() async throws { window = nil }

    func testAnUploadButtonAsksTheHostAndTakesItsFiles() async throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "luna-upload-\(UUID().uuidString).txt")
        try Data("moon".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let host = Host(files: [file])
        let controller = TabController(id: UUID(), dataStore: .nonPersistent())
        controller.delegate = host
        controller.activate()
        guard let view = controller.webView else { return XCTFail("the tab built no web view") }
        show(view)
        view.loadHTMLString(Self.page, baseURL: URL(string: "https://example.invalid/"))
        for _ in 0..<50 where try await view.evaluateJavaScript("document.readyState") as? String != "complete" {
            try await Task.sleep(for: .milliseconds(100))
        }

        click(view)
        for _ in 0..<50 where host.asked == nil { try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertEqual(host.asked?.multiple, true, "the page's click never reached the host")
        XCTAssertEqual(host.asked?.directories, false)

        var picked: String?
        for _ in 0..<50 where picked == nil {
            picked = try await view.evaluateJavaScript("document.getElementById('f').files[0]?.name ?? null") as? String
            if picked == nil { try await Task.sleep(for: .milliseconds(100)) }
        }
        XCTAssertEqual(picked, file.lastPathComponent, "the page did not get the file the host picked")
    }

    private func click(_ view: WKWebView) {
        guard let window = view.window else { return XCTFail("the view is in no window") }
        let point = view.convert(NSPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            guard let event = NSEvent.mouseEvent(
                with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
            ) else { return XCTFail("no event") }
            if type == .leftMouseDown { view.mouseDown(with: event) } else { view.mouseUp(with: event) }
        }
    }

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

    /// The button fills the page so the click cannot miss it, and forwards to a
    /// hidden input the way most upload buttons do.
    private static let page = """
        <html><body style="margin:0">
        <input id="f" type="file" multiple hidden>
        <button style="width:100vw;height:100vh" onclick="document.getElementById('f').click()">Browse</button>
        </body></html>
        """

    private final class Host: TabControllerDelegate {
        let files: [URL]
        var asked: (multiple: Bool, directories: Bool)?

        init(files: [URL]) { self.files = files }

        func tabController(_ controller: TabController, chooseFilesAllowingMultiple multiple: Bool, directories: Bool)
            async -> [URL]? {
            asked = (multiple, directories)
            return files
        }

        func tabController(_ controller: TabController, didChange state: TabState) {}
        func tabController(_ controller: TabController, wantsNewTabFor url: URL?, configuration: WKWebViewConfiguration)
            -> WKWebView? { nil }
        func tabController(_ controller: TabController, didStartDownload download: WKDownload) { download.cancel() }
        func tabController(_ controller: TabController, didFailWith error: Error) {}
    }
}
