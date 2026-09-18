import CoreGraphics
import Foundation
import Testing
import WebKit
@testable import BrowserKit

@Suite("Navigation policy (§4.2, §15.2)")
struct NavigationPolicyTests {

    @Test(arguments: [
        "https://example.com", "http://example.com", "about:blank",
        "data:text/html,hi", "blob:https://example.com/x", "file:///tmp/x.html",
        "luna://newtab"
    ])
    func rendersWebSchemesItself(_ string: String) {
        #expect(NavigationPolicy.disposition(for: URL(string: string)!) == .display)
    }

    @Test(arguments: ["mailto:a@b.com", "tel:+4512345678", "zoommtg://zoom.us/join", "itms-apps://x"])
    func handsOtherAppsTheirSchemes(_ string: String) {
        #expect(NavigationPolicy.disposition(for: URL(string: string)!) == .external)
    }

    /// A `javascript:` URL must never reach the OS handoff — that is an XSS vector, not
    /// an app link.
    @Test func blocksJavaScriptURLs() {
        #expect(NavigationPolicy.disposition(for: URL(string: "javascript:alert(1)")!) == .block)
        #expect(NavigationPolicy.disposition(for: URL(string: "JavaScript:alert(1)")!) == .block)
    }

    @Test func treatsASchemelessURLAsInternal() {
        #expect(NavigationPolicy.disposition(for: URL(string: "/about")!) == .display)
    }

    @Test func downloadsWhatWebKitCannotRender() {
        #expect(NavigationPolicy.shouldDownload(
            canShowMIMEType: false, contentDisposition: nil, isForMainFrame: true
        ))
        #expect(!NavigationPolicy.shouldDownload(
            canShowMIMEType: true, contentDisposition: nil, isForMainFrame: true
        ))
    }

    /// §15.4 — an unrenderable MIME type in a background frame is not a file the user
    /// asked for. An explicit `attachment` still is: that is how sites start downloads
    /// from a hidden iframe.
    @Test func doesNotLetBackgroundFramesDownloadOnMIMETypeAlone() {
        #expect(!NavigationPolicy.shouldDownload(
            canShowMIMEType: false, contentDisposition: nil, isForMainFrame: false
        ))
        #expect(NavigationPolicy.shouldDownload(
            canShowMIMEType: false, contentDisposition: "attachment", isForMainFrame: false
        ))
    }

    /// §15.5 — WebKit renders PDFs and we do not take that away. Only the disposition
    /// *type* counts, so a file merely named "attachment.pdf" still displays.
    @Test func readsOnlyTheDispositionType() {
        #expect(NavigationPolicy.isAttachment("attachment; filename=\"report.pdf\""))
        #expect(NavigationPolicy.isAttachment("  ATTACHMENT  "))
        #expect(!NavigationPolicy.isAttachment("inline; filename=\"attachment.pdf\""))
        #expect(!NavigationPolicy.isAttachment("inline"))
        #expect(!NavigationPolicy.isAttachment(nil))
    }

    @Test func normalisesFaviconKeys() {
        #expect(NavigationPolicy.faviconKey(forHost: "WWW.Example.COM") == "example.com")
        #expect(NavigationPolicy.faviconKey(forHost: "docs.example.com") == "docs.example.com")
    }
}

@Suite("Theme colour bridge (§4.3)")
struct ColorBridgeTests {

    @Test func convertsToSRGBComponents() throws {
        let color = CGColor(srgbRed: 1, green: 0.5, blue: 0, alpha: 0.8)
        let rgba = try #require(ColorBridge.rgba(from: color))
        #expect(abs(rgba.r - 1) < 0.001)
        #expect(abs(rgba.g - 0.5) < 0.001)
        #expect(abs(rgba.b - 0) < 0.001)
        #expect(abs(rgba.a - 0.8) < 0.001)
    }

    /// Greyscale has two components, not four — the conversion must widen it rather
    /// than read past the end.
    @Test func convertsAGreyscaleColour() throws {
        let space = try #require(CGColorSpace(name: CGColorSpace.linearGray))
        let grey = try #require(CGColor(colorSpace: space, components: [0.5, 1]))
        let rgba = try #require(ColorBridge.rgba(from: grey))
        #expect(rgba.r == rgba.g && rgba.g == rgba.b)
        #expect(rgba.a == 1)
    }
}

@Suite("FaviconService (§4.7)")
@MainActor
struct FaviconServiceTests {

    /// The smallest valid PNG there is.
    static let onePixelPNG = Data(base64Encoded: """
    iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==
    """)!

    private func makeService(limit: Int) throws -> (FaviconService, URL) {
        let directory = URL.temporaryDirectory.appending(path: "luna-favicon-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (FaviconService(directory: directory, memoryLimit: limit), directory)
    }

    @Test func evictsTheLeastRecentlyUsedHost() throws {
        let (service, _) = try makeService(limit: 2)
        for host in ["a.com", "b.com", "c.com"] {
            try Self.onePixelPNG.write(to: service.fileURL(for: host))
        }

        #expect(service.favicon(forHost: "a.com") != nil)
        #expect(service.favicon(forHost: "b.com") != nil)
        #expect(service.favicon(forHost: "c.com") != nil)

        #expect(service.memoryCount == 2, "the memory tier grew past its limit")
        // Evicted from memory, still on disk: the icon must not disappear.
        #expect(service.favicon(forHost: "a.com") != nil)
    }

    /// A host with no icon is remembered as a miss, so the sidebar redrawing does not
    /// hit the disk once per frame.
    @Test func remembersMisses() throws {
        let (service, _) = try makeService(limit: 8)
        #expect(service.favicon(forHost: "nothing.example") == nil)
        #expect(service.memoryCount == 1)
        #expect(service.favicon(forHost: "nothing.example") == nil)
    }

    /// The whole "no broken-image glyph" guarantee: bytes that do not decode never
    /// become a cached icon.
    @Test func rejectsBytesThatAreNotAnImage() {
        #expect(FaviconService.png(from: Data("<!doctype html><title>404</title>".utf8)) == nil)
        #expect(FaviconService.png(from: Data()) == nil)
        #expect(FaviconService.png(from: Self.onePixelPNG) != nil)
    }
}

@Suite("TabController lifecycle (§19.2)")
@MainActor
struct TabControllerTests {

    @MainActor private final class Recorder: TabControllerDelegate {
        var states: [TabState] = []
        func tabController(_ controller: TabController, didChange state: TabState) { states.append(state) }
        func tabController(
            _ controller: TabController,
            wantsNewTabFor url: URL?,
            configuration: WKWebViewConfiguration
        ) -> WKWebView? { nil }
        func tabController(_ controller: TabController, didStartDownload download: WKDownload) {}
        func tabController(_ controller: TabController, didFailWith error: Error) {}
    }

    private func makeController() -> TabController {
        TabController(id: UUID(), dataStore: .nonPersistent())
    }

    /// §19.4: a tab that has never been selected has never built a web view.
    @Test func isBornCold() {
        #expect(makeController().webView == nil)
    }

    /// §19.2 is the whole memory strategy: hibernating must leave *nothing* behind.
    @Test func hibernationReleasesTheWebView() {
        let controller = makeController()
        controller.activate()
        #expect(controller.webView != nil)

        controller.hibernate()
        #expect(controller.webView == nil)
        #expect(controller.state.isLoading == false)
        #expect(controller.state.canGoBack == false)
        #expect(controller.state.isPlayingAudio == false)
    }

    @Test func activatingTwiceReusesTheSameWebView() {
        let controller = makeController()
        controller.activate()
        let first = controller.webView
        controller.activate()
        #expect(controller.webView === first)
    }

    @Test func hibernatingWhileColdDoesNothing() {
        let controller = makeController()
        let recorder = Recorder()
        controller.delegate = recorder
        controller.hibernate()
        #expect(controller.webView == nil)
        #expect(recorder.states.isEmpty)
    }

    /// A restored tab must still know where to go when its `interactionState` blob is
    /// missing or stale, or it wakes up blank.
    @Test func restoreKeepsAFallbackURL() {
        let controller = makeController()
        controller.restore(interactionState: nil, fallbackURL: URL(string: "about:blank")!)
        #expect(controller.state.url?.absoluteString == "about:blank")
    }

    /// The saved session has to outlive the web view — that is the only thing §19.3 can
    /// restore from once a WebContent process is gone.
    @Test func capturedSessionSurvivesWithoutAWebView() {
        let controller = makeController()
        let blob = Data("pretend-session".utf8)
        controller.restore(interactionState: blob)
        #expect(controller.captureInteractionState() == blob)
    }
}

/// §3.2b's scroll signal. The script and the handler name are written in two
/// places that cannot see each other — a string in Swift and a property lookup
/// in JavaScript — and a typo in either is silent: the page posts into nothing
/// and the bar simply never collapses.
@Suite("Page scroll signal (§3.2b)")
@MainActor
struct PageScrollSignalTests {

    @Test func theScriptPostsToTheNameTheControllerRegisters() {
        #expect(TabController.scrollScript.contains(TabController.scrollMessageName))
    }

    @Test func theNameIsNotOneOfTheOtherTwo() {
        #expect(TabController.scrollMessageName != TabController.mediaMessageName)
        #expect(TabController.scrollMessageName != ContentBlocker.blockedMessageName)
    }

    /// The listener must never be able to delay a scroll, and it must coalesce to
    /// a frame — posting once per scroll event crosses the process boundary
    /// hundreds of times a second during a drag.
    @Test func theListenerIsPassiveAndFrameCoalesced() {
        #expect(TabController.scrollScript.contains("passive: true"))
        #expect(TabController.scrollScript.contains("requestAnimationFrame"))
    }

    /// `scroll` does not bubble, but it does capture — which is the only way one
    /// listener sees the app-shell sites that scroll an inner element instead of
    /// the document.
    @Test func itSeesTheSitesThatScrollSomethingOtherThanTheDocument() {
        #expect(TabController.scrollScript.contains("capture: true"))
        #expect(TabController.scrollScript.contains("scrollingElement"))
    }
}
