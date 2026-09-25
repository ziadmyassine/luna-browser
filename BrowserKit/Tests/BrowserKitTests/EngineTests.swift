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
    /// type counts, so a file merely named "attachment.pdf" still displays.
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
            try Self.onePixelPNG.write(to: #require(service.fileURL(for: host)))
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

    /// §5.6: a private window's icons never reach the disk. The disk-backed half
    /// is the control — without it, a `remember` that wrote nowhere would pass.
    @Test func memoryOnlyServiceWritesNothing() async throws {
        let (disk, directory) = try makeService(limit: 8)
        await disk.remember(Self.onePixelPNG, for: "kept.example")
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path()).count == 1)

        // Letters and digits only, so the file name it would have had is the host.
        let host = "private" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let memoryOnly = FaviconService(directory: nil)
        await memoryOnly.remember(Self.onePixelPNG, for: host)
        #expect(memoryOnly.favicon(forHost: host) == Self.onePixelPNG)
        #expect(memoryOnly.fileURL(for: host) == nil)
        let wouldBe = FaviconService.defaultDirectory.appending(path: host + ".png")
        #expect(!FileManager.default.fileExists(atPath: wouldBe.path()))
        #expect(FaviconService.shared.favicon(forHost: host) == nil, "leaked into the shared cache")
    }

    /// The whole "no broken-image glyph" guarantee: bytes that do not decode never
    /// become a cached icon.
    @Test func rejectsBytesThatAreNotAnImage() {
        #expect(FaviconService.png(from: Data("<!doctype html><title>404</title>".utf8)) == nil)
        #expect(FaviconService.png(from: Data()) == nil)
        #expect(FaviconService.png(from: Self.onePixelPNG) != nil)
    }

    /// Why `rasterize` exists. ImageIO hands back a source with no images at all
    /// for a vector, and several sites serve one straight from `/favicon.ico` —
    /// so without the seam those hosts have no icon. If this ever starts passing
    /// an SVG, the seam is dead code and should go.
    @Test func cannotReadAVectorWithoutTheAppsHelp() {
        #expect(FaviconService.png(from: Self.squareSVG) == nil)
        #expect(FaviconService.rasterize == nil, "BrowserKit must not install one itself")
    }

    /// A vector icon, as small as one gets.
    static let squareSVG = Data("""
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16"><rect width="16" height="16"/></svg>
    """.utf8)
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

    /// §19.2 is the whole memory strategy: hibernating must leave nothing behind.
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

/// §3.2b's plane follows the page down, which means the page has to say what
/// colour it is under the bar. The sample is three numbers or nothing, and
/// "nothing" is a real answer — the top edge of a page can genuinely have no
/// single colour, and reading that as black would paint the bar black.
@Suite("Page colour sample (§3.2b)")
@MainActor
struct PageColourSampleTests {

    @Test func theScriptAsksThePageWhatIsDrawnUnderTheBar() {
        #expect(TabController.scrollScript.contains("elementsFromPoint"))
        #expect(TabController.scrollScript.contains("getComputedStyle"))
        #expect(TabController.scrollScript.contains("top: top(y)"))
    }

    /// The hit tests are the cost of this, so they are not run per frame of a
    /// drag — and a resize is the one thing that changes the answer without a
    /// scroll, because the bar's own two heights resize the page.
    @Test func theSampleIsCachedAcrossSmallMovesAndDroppedOnAResize() {
        #expect(TabController.scrollScript.contains("< 4"))
        #expect(TabController.scrollScript.contains("'resize'"))
    }

    /// The sidebar's selected row fills with this, so it has to be a fraction,
    /// and "cannot scroll" has to stay apart from "has not scrolled yet".
    @Test func progressIsAFractionOrNothing() {
        #expect(TabController.progress(from: NSNumber(value: 0.25)) == 0.25)
        #expect(TabController.progress(from: NSNumber(value: 0)) == 0)
        #expect(TabController.progress(from: NSNumber(value: 1.4)) == 1)
        #expect(TabController.progress(from: NSNumber(value: -0.2)) == 0)
        #expect(TabController.progress(from: nil) == nil)
        #expect(TabController.progress(from: NSNull()) == nil)
        #expect(TabController.progress(from: NSNumber(value: Double.nan)) == nil)
        #expect(TabController.progress(from: "0.5") == nil)
        #expect(TabController.scrollScript.contains("p: through(y)"))
    }

    @Test func threeComponentsAreAColour() {
        let sample = [1.0, 0.5, 0.0].map(NSNumber.init(value:))
        #expect(TabController.sampledColour(from: sample) == RGBA(r: 1, g: 0.5, b: 0, a: 1))
    }

    /// Every shape that is not three components in range is the page saying it
    /// has no answer, and none of them may come out as a colour — least of all
    /// as an all-zero one, which is black.
    @Test func anythingElseIsNoColourAtAll() {
        let samples: [Any?] = [
            nil,
            NSNull(),
            [1.0, 1.0].map(NSNumber.init(value:)),
            [1.0, 1.0, 1.0, 1.0].map(NSNumber.init(value:)),
            [1.0, 2.0, 0.0].map(NSNumber.init(value:)),
            [-0.5, 0.0, 0.0].map(NSNumber.init(value:)),
            "rgb(255, 255, 255)"
        ]
        for sample in samples {
            #expect(TabController.sampledColour(from: sample) == nil)
        }
    }
}

@Suite("Link tracking in private windows (§8.1)")
struct LinkTrackingTests {

    private func stripped(_ string: String) -> String? {
        NavigationPolicy.strippingTracking(from: URL(string: string)!)?.absoluteString
    }

    @Test func stripsListedParametersAndKeepsTheRestInOrder() {
        #expect(stripped("https://a.com/p?b=2&utm_source=x&a=1&fbclid=y&c=%20z")
            == "https://a.com/p?b=2&a=1&c=%20z")
    }

    @Test func dropsTheQuestionMarkWhenNothingIsLeft() {
        #expect(stripped("https://a.com/p?gclid=1&utm_medium=e") == "https://a.com/p")
    }

    @Test func keepsTheFragment() {
        #expect(stripped("https://a.com/p?q=1&msclkid=2#top") == "https://a.com/p?q=1#top")
    }

    @Test func matchesNamesInAnyCase() {
        #expect(stripped("https://a.com/?UTM_Source=x&k=v") == "https://a.com/?k=v")
    }

    @Test func stripsEmptyAndValuelessParameters() {
        #expect(stripped("https://a.com/?utm_source=&utm_campaign&k=v") == "https://a.com/?k=v")
    }

    @Test(arguments: [
        "https://a.com/p", "https://a.com/p?q=utm_source", "https://a.com/p?utm_sourcex=1#f",
        "ftp://a.com/?utm_source=x", "mailto:a@b.com?utm_source=x"
    ])
    func leavesAURLWithNothingToStripAlone(_ string: String) {
        #expect(stripped(string) == nil)
    }

    private func target(
        _ string: String = "https://a.com/?fbclid=1",
        persistent: Bool = false,
        mainFrame: Bool = true,
        method: String? = "GET",
        type: WKNavigationType = .linkActivated,
        current: String? = nil
    ) -> URL? {
        var request = URLRequest(url: URL(string: string)!)
        request.httpMethod = method
        return NavigationPolicy.trackingFreeTarget(
            for: request,
            isPersistentStore: persistent,
            isMainFrame: mainFrame,
            navigationType: type,
            currentURL: current.flatMap(URL.init(string:))
        )
    }

    @Test func reloadsOnlyAPrivateMainFrameGET() {
        #expect(target() == URL(string: "https://a.com/"))
        #expect(target(method: nil) == URL(string: "https://a.com/"))
        #expect(target(persistent: true) == nil)
        #expect(target(mainFrame: false) == nil)
        #expect(target(method: "POST") == nil)
        #expect(target(type: .backForward) == nil)
        #expect(target(type: .reload) == nil)
    }

    @Test func leavesAFragmentJumpOnTheSamePageAlone() {
        #expect(target("https://a.com/?fbclid=1#b", current: "https://a.com/?fbclid=1#a") == nil)
    }
}
