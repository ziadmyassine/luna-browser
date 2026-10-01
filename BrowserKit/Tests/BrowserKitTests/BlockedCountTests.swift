@testable import BrowserKit
import Foundation
import Testing
import WebKit

/// §17.4: what the blocker caught on a tab's page, counted and listed by site.
@Suite("Blocked count (§17.4)")
@MainActor
struct BlockedCountTests {

    private static func blocker(test: String = #function) -> ContentBlocker {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "luna-rules/\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return ContentBlocker(store: WKContentRuleListStore(url: directory)!, defaults: scratchDefaults(test: test))
    }

    @Test func loadsAddUpAndListBySiteMostFirst() {
        let blocker = Self.blocker()
        let tab = UUID()
        for host in ["ads.example", "track.example", "ads.example", nil, "ads.example"] {
            blocker.noteBlockedLoad(host: host, tab: tab)
        }
        blocker.setYouTubeBlockedCount(2, tab: tab)

        #expect(blocker.blockedCount(tab: tab) == 7, "five loads, one with no host, and two YouTube ads")
        #expect(blocker.blockedHosts(tab: tab).map(\.host) == ["ads.example", "track.example"])
        #expect(blocker.blockedHosts(tab: tab).map(\.count) == [3, 1])
        #expect(blocker.blockedCount(tab: UUID()) == 0)
    }

    @Test func aNewPageStartsFromNothing() {
        let blocker = Self.blocker()
        let tab = UUID()
        blocker.noteBlockedLoad(host: "ads.example", tab: tab)
        blocker.resetBlockedCount(tab: tab)
        #expect(blocker.blockedCount(tab: tab) == 0)
        #expect(blocker.blockedHosts(tab: tab).isEmpty)
    }

    /// Every frame reports its own loads; none of them overwrites another's.
    @Test func everyReportFromThePageReachesTheTab() async throws {
        let controller = TabController(id: UUID(), dataStore: .nonPersistent())
        controller.activate()
        let webView = try #require(controller.webView)
        webView.loadHTMLString("<p>page</p>", baseURL: URL(string: "https://news.example/"))
        for _ in 0 ..< 250 where webView.isLoading || webView.url?.host() != "news.example" {
            try await Task.sleep(for: .milliseconds(20))
        }
        _ = try await webView.evaluateJavaScript("""
        ['https://ads.example/a.js', 'https://ads.example/b.png', 'https://pixel.example/p.gif']
          .forEach(u => webkit.messageHandlers.lunaBlocked.postMessage({ url: u })); 0
        """)
        for _ in 0 ..< 100 where ContentBlocker.shared.blockedCount(tab: controller.id) < 3 {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(ContentBlocker.shared.blockedHosts(tab: controller.id).map(\.host) == ["ads.example", "pixel.example"])
        ContentBlocker.shared.forgetTab(controller.id)
    }
}
