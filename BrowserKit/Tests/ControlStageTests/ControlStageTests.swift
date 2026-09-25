// The app's `ControlStage` under `swift test`: `ControlStage.swift` here is a
// link to `Features/Control/ControlStage.swift`, so these run the production
// stage, not a copy. Kept out of BrowserKit's sources, which take no AppKit.
//
// Trusted input from an off-screen window that never becomes key, against a
// fixture that logs `isTrusted` and throws untrusted input away — and the
// guarantees around it: nothing reaches the user's menus, screen, focus or
// pointer. The process is `.prohibited`, so nothing here can activate.

import AppKit
import LunaControl
import WebKit
import XCTest

/// Stands in for `LunaApplication`: the one line it adds to `sendEvent`.
final class StageTestApplication: NSApplication {
    override func sendEvent(_ event: NSEvent) {
        if ControlStage.absorbs(event) { return }
        super.sendEvent(event)
    }
}

/// Stands in for the user's main menu: counts key equivalents that reached it.
final class MenuProbe: NSObject {
    var hits: [String] = []
    @objc func hit(_ sender: NSMenuItem) { hits.append(sender.keyEquivalent) }

    @MainActor func install() {
        let root = NSMenu(), edit = NSMenu()
        for key in ["a", "w"] {
            let item = NSMenuItem(title: key, action: #selector(hit(_:)), keyEquivalent: key)
            item.target = self
            edit.addItem(item)
        }
        let top = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        top.submenu = edit
        root.addItem(top)
        NSApp.mainMenu = root
    }
}

/// Everything of the user's that a stage must leave alone.
struct UserState: Equatable {
    var active: Bool
    var keyWindow: Int?
    var mouse: NSPoint
    var cursor: ObjectIdentifier
    var frontPID: pid_t?
    var otherWindows: [Int: CGRect]

    @MainActor static func now() -> UserState {
        let own = ProcessInfo.processInfo.processIdentifier
        let list = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
        var frames: [Int: CGRect] = [:]
        for info in list where (info[kCGWindowOwnerPID as String] as? pid_t) != own {
            guard let number = info[kCGWindowNumber as String] as? Int,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds) else { continue }
            frames[number] = rect
        }
        return UserState(
            active: NSApp.isActive, keyWindow: NSApp.keyWindow?.windowNumber, mouse: NSEvent.mouseLocation,
            cursor: ObjectIdentifier(NSCursor.current),
            frontPID: NSWorkspace.shared.frontmostApplication?.processIdentifier, otherWindows: frames
        )
    }
}

@MainActor
final class ControlStageTests: XCTestCase {

    /// A Google-Docs-like page: the editor throws away anything untrusted, and
    /// every listener logs `isTrusted`.
    static let fixture = """
    <!doctype html><meta charset=utf-8>
    <style>body{margin:0;font:14px system-ui} .a{position:absolute;left:20px}</style>
    <button id=b class=a style="top:20px;width:100px;height:40px">Button</button>
    <div id=ed class=a contenteditable style="top:80px;width:300px;height:60px;border:1px solid #888"></div>
    <div id=track class=a style="top:160px;width:300px;height:20px;background:#ccc;touch-action:none;user-select:none"></div>
    <div id=ctx class=a style="top:240px;width:100px;height:40px;background:#eee">ctx</div>
    <script>
    window.log = []; window.clicks = 0; window.slider = 0; window.dragging = false;
    const L = e => log.push({t: e.type, tr: e.isTrusted, k: e.key || '', b: e.button ?? -1});
    b.addEventListener('click', e => { L(e); if (e.isTrusted) clicks++; });
    for (const t of ['keydown', 'beforeinput', 'input'])
      ed.addEventListener(t, e => { L(e); if (!e.isTrusted) e.preventDefault(); });
    track.addEventListener('pointerdown', e => { L(e); if (!e.isTrusted) return;
      dragging = true; track.setPointerCapture(e.pointerId); });
    track.addEventListener('pointermove', e => { if (!dragging || !e.isTrusted) return;
      slider = Math.max(0, Math.min(1, e.offsetX / track.clientWidth)); });
    track.addEventListener('pointerup', e => { L(e); dragging = false; });
    for (const t of ['contextmenu', 'auxclick', 'mouseenter']) ctx.addEventListener(t, L);
    </script>
    """

    private var webView: WKWebView!
    private var stages: [ControlStage] = []

    override func setUp() async throws {
        guard StageTestApplication.shared is StageTestApplication else {
            throw XCTSkip("NSApp was created before this suite; run it with --filter ControlStageTests")
        }
        NSApp.setActivationPolicy(.prohibited)
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        // Windowless and sized, as `ControlService.size` leaves a hidden tab.
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 400, height: 320), configuration: configuration)
        webView.loadHTMLString(Self.fixture, baseURL: URL(string: "https://example.com/"))
        for _ in 0 ..< 100 {
            if try await js("typeof window.clicks") == "\"number\"" { break }
            try await Task.sleep(for: .milliseconds(30))
        }
    }

    override func tearDown() async throws {
        stages.forEach { $0.release() }
        stages = []
    }

    private func stage() throws -> ControlStage {
        let stage = try ControlStage(adopting: webView)
        stages.append(stage)
        return stage
    }

    private func js(_ expr: String) async throws -> String {
        try await webView.evaluateJavaScript("JSON.stringify(\(expr))") as? String ?? "null"
    }

    private func settle(_ milliseconds: Int = 150) async throws { try await Task.sleep(for: .milliseconds(milliseconds)) }

    /// `expr` once the page has caught up, or as it stands after `seconds`.
    ///
    /// A fixed wait is a guess at how fast WebContent runs. On the CI runner
    /// the typing tests took three times as long as on a Mac, and a 300 ms
    /// settle read the editor while the last word was still arriving.
    private func poll(_ expr: String, for seconds: Double = 5, until accept: (String) -> Bool) async throws -> String {
        let deadline = Date().addingTimeInterval(seconds)
        var value = try await js(expr)
        while !accept(value), Date() < deadline {
            try await Task.sleep(for: .milliseconds(50))
            value = try await js(expr)
        }
        return value
    }

    /// Waits for a click to have put the caret in the editor.
    private func focusEditor(_ stage: ControlStage) async throws {
        try stage.click(at: try await center("ed"))
        _ = try await poll("document.activeElement === ed") { $0 == "true" }
    }

    private func center(_ id: String) async throws -> CGPoint {
        let json = try await js("(r => [r.x + r.width / 2, r.y + r.height / 2])(\(id).getBoundingClientRect())")
        let xy = try JSONDecoder().decode([Double].self, from: Data(json.utf8))
        return CGPoint(x: xy[0], y: xy[1])
    }

    private func untrusted() async throws -> String { try await js("log.filter(e => !e.tr)") }

    func testTrustedClickOnAgentTab() async throws {
        let frame = webView.frame
        let stage = try stage()
        XCTAssertTrue(webView.window is ControlStageWindow)
        try stage.click(at: try await center("b"))
        try await settle()
        let clicks = try await js("clicks")
        XCTAssertEqual(clicks, "1")
        let untrusted = try await untrusted()
        XCTAssertEqual(untrusted, "[]")
        stage.release()
        XCTAssertNil(webView.window)
        XCTAssertEqual(webView.frame, frame)
    }

    /// Focus survives the tab leaving the stage between calls: a click in
    /// one call and typing in the next is how an agent fills a field.
    func testTypingAcrossCallsLandsInContentEditable() async throws {
        let first = try stage()
        try await focusEditor(first)
        first.release()
        let second = try stage()
        try await second.type(ControlInput.keys(typing: "Hej å 😀 world"))
        let text = try await poll("ed.textContent") { $0 == "\"Hej å 😀 world\"" }
        XCTAssertEqual(text, "\"Hej å 😀 world\"")
        let untrusted = try await untrusted()
        XCTAssertEqual(untrusted, "[]")
    }

    /// WebKit hands keys the page leaves alone back to `NSApp.sendEvent`,
    /// where the main menu would take Cmd+W as closing the user's tab.
    func testEnterAndCmdAStayOffTheMenu() async throws {
        let menu = MenuProbe()
        menu.install()
        let stage = try stage()
        try await focusEditor(stage)
        try await stage.type(ControlInput.keys(typing: "ab\ncd"))
        _ = try await poll("ed.innerText") { $0.contains("cd") }
        try await stage.type([try ControlInput.key("cmd+a"), try ControlInput.key("cmd+w")])
        let selected = try await poll("getSelection().toString()") { $0.contains("ab") && $0.contains("cd") }
        XCTAssertEqual(menu.hits, [])
        XCTAssertTrue(selected.contains("ab") && selected.contains("cd"), selected)
        let enter = try await js("log.filter(e => e.t == 'keydown' && e.k == 'Enter').map(e => e.tr)")
        XCTAssertEqual(enter, "[true]")
    }

    func testPointerDragMovesSlider() async throws {
        let stage = try stage()
        let track = try await center("track")
        try await stage.drag(from: CGPoint(x: track.x - 145, y: track.y), to: CGPoint(x: track.x + 75, y: track.y))
        try await settle()
        let value = Double(try await js("slider")) ?? .nan
        XCTAssertEqual(value, 0.75, accuracy: 0.03)
        let untrusted = try await untrusted()
        XCTAssertEqual(untrusted, "[]")
    }

    /// The right button reaches the page trusted, and with
    /// the library's stage mode on no context menu starts tracking.
    func testRightClickIsTrustedAndNoMenuOpens() async throws {
        var tracked = 0
        let token = NotificationCenter.default.addObserver(
            forName: NSMenu.didBeginTrackingNotification, object: nil, queue: nil
        ) { _ in MainActor.assumeIsolated { tracked += 1 } }
        defer { NotificationCenter.default.removeObserver(token) }
        let stage = try stage()
        _ = try await webView.callAsyncJavaScript(
            ControlScripts.call("stage"), arguments: ["args": ["on": true]], in: nil, contentWorld: .world(name: "luna-control")
        )
        let ctx = try await center("ctx")
        try stage.click(at: ctx, right: true)
        try await settle(400)
        XCTAssertEqual(tracked, 0)
        let seen = try await js("log.map(e => e.t + ':' + e.b + ':' + e.tr)")
        XCTAssertTrue(seen.contains("contextmenu:2:true"), seen)
        let untrusted = try await untrusted()
        XCTAssertEqual(untrusted, "[]")
    }

    /// A tab the user has on screen is theirs: the stage never takes it, so
    /// it never takes first responder from the user's window.
    func testUserViewingTabRefusesInput() throws {
        let userWindow = NSWindow(contentRect: webView.frame, styleMask: [.titled], backing: .buffered, defer: true)
        userWindow.isReleasedWhenClosed = false
        userWindow.contentView = webView
        XCTAssertThrowsError(try ControlStage(adopting: webView))
        XCTAssertTrue(webView.window === userWindow)
        userWindow.contentView = nil
    }

    /// If the user shows the tab while a call is running, the next event is
    /// refused rather than sent into their window.
    func testTabShownMidCallStopsTheStage() throws {
        let stage = try stage()
        let userWindow = NSWindow(contentRect: webView.frame, styleMask: [.titled], backing: .buffered, defer: true)
        userWindow.isReleasedWhenClosed = false
        userWindow.contentView = webView
        XCTAssertThrowsError(try stage.click(at: CGPoint(x: 10, y: 10)))
        stage.release()
        XCTAssertTrue(webView.window === userWindow)
        userWindow.contentView = nil
    }

    /// The pointer check reads the real pointer, so it fails if the user
    /// moves it during the second the test runs; nothing here posts a system
    /// event.
    func testNoFocusOrWindowMoves() async throws {
        let before = UserState.now()
        let stage = try stage()
        try stage.click(at: try await center("b"))
        try stage.click(at: try await center("ed"))
        try await stage.type(ControlInput.keys(typing: "leak check"))
        try await stage.type([try ControlInput.key("cmd+a")])
        try await settle()
        let after = UserState.now()
        let moved = before.otherWindows.filter { old in after.otherWindows[old.key].map { $0 != old.value } ?? false }
        XCTAssertFalse(after.active)
        XCTAssertNil(after.keyWindow)
        XCTAssertEqual(after.mouse, before.mouse)
        XCTAssertEqual(after.cursor, before.cursor)
        XCTAssertEqual(after.frontPID, before.frontPID)
        XCTAssertTrue(moved.isEmpty, "\(moved)")
        let frame = try XCTUnwrap(webView.window).frame
        XCTAssertFalse(NSScreen.screens.contains { $0.frame.intersects(frame) })
    }
}
