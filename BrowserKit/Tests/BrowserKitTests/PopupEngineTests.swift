import Foundation
import Testing
import WebKit
@testable import BrowserKit

/// §17's pop-up blocker in a real `WKWebView`: what WebKit refuses on its own,
/// what reaches `createWebViewWith`, and the tab-under guard in
/// `decidePolicyFor`. Nothing here touches the network — every page is a string,
/// and every navigation that would leave it is either refused or never waited on.
@Suite("Pop-up blocking in the engine (§17)")
@MainActor
struct PopupEngineTests {

    /// Opens each pop-up in a tab of its own, as the app does, so the child's
    /// navigations come back through a `TabController`.
    @MainActor private final class Recorder: TabControllerDelegate {
        var opened: [URL?] = []
        var blocked: [URL] = []
        var children: [TabController] = []
        var closed: [UUID] = []
        var settings = UserDefaults.standard

        func tabController(_ controller: TabController, didChange state: TabState) {}
        func tabController(
            _ controller: TabController,
            wantsNewTabFor url: URL?,
            configuration: WKWebViewConfiguration
        ) -> WKWebView? {
            opened.append(url)
            let child = TabController(id: UUID(), dataStore: configuration.websiteDataStore)
            child.settings = settings
            child.delegate = self
            children.append(child)
            return child.activate(with: configuration)
        }
        func tabControllerWantsToClose(_ controller: TabController) { closed.append(controller.id) }
        func tabController(_ controller: TabController, didStartDownload download: WKDownload) {}
        func tabController(_ controller: TabController, didFailWith error: Error) {}
        func tabController(_ controller: TabController, didBlockPopup url: URL) { blocked.append(url) }
    }

    private static let page = URL(string: "https://news.example.com/story")!

    /// A tab reading its mode from a suite of its own, so no test here writes
    /// the shared defaults another suite is reading.
    private func tab(
        _ mode: PopupMode, html: String = "<p>page</p>", test: String = #function
    ) async -> (TabController, Recorder) {
        let defaults = scratchDefaults(test: test)
        PopupPolicy.setMode(mode, in: defaults)
        let controller = TabController(id: UUID(), dataStore: .nonPersistent())
        controller.settings = defaults
        let recorder = Recorder()
        recorder.settings = defaults
        controller.delegate = recorder
        controller.activate()
        controller.webView?.loadHTMLString(html, baseURL: Self.page)
        await settle { controller.webView?.isLoading == false && controller.webView?.url?.host() == Self.page.host() }
        return (controller, recorder)
    }

    @discardableResult
    private func settle(within seconds: Double = 5, until condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(40))
        }
        return condition()
    }

    private func run(_ script: String, in controller: TabController) async {
        _ = try? await controller.webView?.evaluateJavaScript("\(script); 0")
    }

    /// No gesture, so WebKit drops it before any delegate hears of it — and the
    /// page script is the only witness.
    @Test func aGesturelessPopupIsBlockedAndReported() async {
        let (controller, recorder) = await tab(
            .smart, html: "<script>window.open('https://ads.example.net/pop')</script>"
        )
        await settle { !controller.popups.blocked.isEmpty }
        #expect(controller.popups.blocked.first?.url.absoluteString == "https://ads.example.net/pop")
        #expect(recorder.blocked.map(\.absoluteString) == ["https://ads.example.net/pop"])
        #expect(recorder.opened.isEmpty, "WebKit let a gesture-less window.open through")
    }

    /// Off leaves WebKit's macOS default in place, including on a view built
    /// while another mode was set: the preference is re-read per navigation.
    @Test func offLetsTheSamePopupThrough() async {
        let (controller, recorder) = await tab(
            .off, html: "<script>window.open('https://ads.example.net/pop')</script>"
        )
        await settle { !recorder.opened.isEmpty }
        #expect(recorder.opened.map { $0?.absoluteString } == ["https://ads.example.net/pop"])
        #expect(controller.popups.blocked.isEmpty)
    }

    /// `evaluateJavaScript` runs as a user gesture, so its `window.open` reaches
    /// `createWebViewWith` and the rules decide.
    @Test func aGesturedPopupIsRoutedByTheRules() async {
        let (controller, recorder) = await tab(.smart)

        await run("window.open('https://video.example.com/watch')", in: controller)
        await settle { !recorder.opened.isEmpty }
        #expect(recorder.opened.map { $0?.absoluteString } == ["https://video.example.com/watch"])

        await run("window.open('https://ads.example.net/')", in: controller)
        await settle { !controller.popups.blocked.isEmpty }
        #expect(controller.popups.blocked.map(\.url.absoluteString) == ["https://ads.example.net/"])
        #expect(recorder.opened.count == 1)
    }

    /// The classic tab-under: open the pop-up on the click, and move the page
    /// underneath it somewhere else in the same breath.
    @Test func theTabUnderGuardRefusesAScriptedCrossSiteMove() async {
        let (controller, _) = await tab(.smart)
        await run(
            "window.open('https://ads.example.net/'); location.href = 'https://casino.example.org/'",
            in: controller
        )
        await settle { controller.popups.blocked.contains { $0.url.host() == "casino.example.org" } }
        #expect(controller.popups.blocked.contains { $0.url.host() == "casino.example.org" })
        #expect(controller.webView?.url?.host() == Self.page.host())
    }

    // MARK: - A blank pop-up on probation

    /// The click-hijack: open blank on the click, then point it at the ad.
    /// The blank window is allowed; where it is sent is judged as if it had
    /// been the pop-up's address all along, on the opener's behalf.
    @Test func aBlankPopupSentToAnAdIsClosedAndRecordedOnTheOpener() async {
        let (controller, recorder) = await tab(.smart)
        await run("var w = window.open('about:blank'); w.location = 'https://ads.example.net/hijack'", in: controller)
        await settle { !controller.popups.blocked.isEmpty && !recorder.closed.isEmpty }
        #expect(controller.popups.blocked.map(\.url.absoluteString) == ["https://ads.example.net/hijack"])
        #expect(recorder.blocked.map(\.absoluteString) == ["https://ads.example.net/hijack"])
        #expect(recorder.closed == recorder.children.map(\.id))
        #expect(recorder.children.first?.popups.blocked.isEmpty == true, "the entry belongs to the opener")
    }

    /// The sign-in button's version of the same shape must still work.
    @Test func aBlankPopupSentToASignInProviderCarriesOn() async {
        let (controller, recorder) = await tab(.smart)
        await run("var w = window.open(''); w.location = 'https://accounts.google.com/o/oauth2/auth'", in: controller)
        await settle { recorder.children.first?.webView?.url?.host() == "accounts.google.com" }
        #expect(recorder.children.first?.webView?.url?.host() == "accounts.google.com")
        #expect(recorder.closed.isEmpty)
        #expect(controller.popups.blocked.isEmpty)
    }

    /// Written into rather than sent anywhere: nothing to judge, and the tab stands.
    @Test func aBlankPopupThePageWritesIntoStands() async {
        let (controller, recorder) = await tab(.smart)
        await run("var w = window.open(''); w.document.write('<p>receipt</p>'); w.document.close()", in: controller)
        await settle { !recorder.children.isEmpty }
        let text = try? await recorder.children.first?.webView?.evaluateJavaScript("document.body.textContent")
        #expect(text as? String == "receipt")
        #expect(recorder.closed.isEmpty)
        #expect(controller.popups.blocked.isEmpty)
    }

    @Test func blockAllRefusesABlankPopupOutright() async {
        let (controller, recorder) = await tab(.blockAll)
        await run("window.open('about:blank')", in: controller)
        try? await Task.sleep(for: .milliseconds(200))
        #expect(recorder.opened.isEmpty)
        _ = controller
    }
}
