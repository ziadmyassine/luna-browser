@testable import BrowserKit
import Foundation
import Testing
import WebKit

/// §18.8: a page reading the clipboard is asked about like the camera, and the answer
/// is kept for the site. A real `WKWebView`, a page from a string, and a delegate that
/// stands in for the toast and the pasteboard: nothing here touches the Mac's clipboard.
@Suite("Clipboard reads are asked about (§18.8)")
@MainActor
struct ClipboardPermissionTests {

    @MainActor private final class Asker: TabControllerDelegate {
        var answer: Bool?
        var clipboard: [String: String] = ["text/plain": "copied"]
        var asked: [[BrowserStore.SitePermission]] = []
        var askedHosts: [String] = []
        var reads: [ClipboardRequest] = []

        func tabController(_ controller: TabController, didChange state: TabState) {}
        func tabController(
            _ controller: TabController, wantsNewTabFor url: URL?, configuration: WKWebViewConfiguration
        ) -> WKWebView? { nil }
        func tabController(_ controller: TabController, didStartDownload download: WKDownload) {}
        func tabController(_ controller: TabController, didFailWith error: Error) {}
        func tabController(
            _ controller: TabController,
            wantsAccessTo permissions: [BrowserStore.SitePermission],
            forHost host: String
        ) async -> Bool? {
            asked.append(permissions)
            askedHosts.append(host)
            return answer
        }
        func tabController(_ controller: TabController, readsClipboard request: ClipboardRequest) async -> [String: String]? {
            reads.append(request)
            return request == .paste ? [:] : clipboard
        }
    }

    private static let page = URL(string: "https://paste.example/editor")!

    private func tab(answer: Bool?) async throws -> (TabController, Asker) {
        let controller = TabController(id: UUID(), dataStore: .nonPersistent())
        let asker = Asker()
        asker.answer = answer
        controller.delegate = asker
        controller.activate()
        let webView = try #require(controller.webView)
        webView.loadHTMLString("<textarea id=t></textarea>", baseURL: Self.page)
        for _ in 0 ..< 250 where webView.isLoading || webView.url?.host() != Self.page.host() {
            try await Task.sleep(for: .milliseconds(20))
        }
        return (controller, asker)
    }

    /// The page's own world, where its scripts would make the call.
    private func run(_ body: String, in controller: TabController) async throws -> String? {
        let webView = try #require(controller.webView)
        return try await webView.callAsyncJavaScript(body, contentWorld: .page) as? String
    }

    private static let readText = """
    try { return 'read: ' + await navigator.clipboard.readText() } catch (e) { return 'refused: ' + e.name }
    """

    @Test func anAllowedSiteReadsAndIsNotAskedAgain() async throws {
        let (controller, asker) = try await tab(answer: true)

        #expect(try await run(Self.readText, in: controller) == "read: copied")
        #expect(asker.asked == [[.clipboard]])
        #expect(asker.askedHosts == ["paste.example"])
        #expect(controller.sitePermissions.answer(.clipboard, forHost: "paste.example") == true)

        #expect(try await run(Self.readText, in: controller) == "read: copied")
        #expect(asker.asked.count == 1, "a standing yes is not asked again")
        #expect(asker.reads == [.readText, .readText])
    }

    @Test func aRefusedSiteReadsNothingAndIsNotAskedAgain() async throws {
        let (controller, asker) = try await tab(answer: false)

        #expect(try await run(Self.readText, in: controller) == "refused: NotAllowedError")
        #expect(controller.sitePermissions.answer(.clipboard, forHost: "paste.example") == false)
        #expect(try await run(Self.readText, in: controller) == "refused: NotAllowedError")
        #expect(asker.asked.count == 1)
        #expect(asker.reads.isEmpty, "the pasteboard is never read for a no")
    }

    /// The toast went away unanswered: a no for now, and the site may ask again.
    @Test func anUnansweredQuestionIsANoForNow() async throws {
        let (controller, asker) = try await tab(answer: nil)

        #expect(try await run(Self.readText, in: controller) == "refused: NotAllowedError")
        #expect(controller.sitePermissions.answer(.clipboard, forHost: "paste.example") == nil)
        _ = try await run(Self.readText, in: controller)
        #expect(asker.asked.count == 2)
    }

    @Test func readHandsOverTextAndPictureAsOneItem() async throws {
        let (controller, asker) = try await tab(answer: true)
        asker.clipboard = ["text/plain": "copied", "image/png": Data([0x89, 0x50, 0x4E, 0x47]).base64EncodedString()]

        let result = try await run("""
        const items = await navigator.clipboard.read();
        const text = await (await items[0].getType('text/plain')).text();
        const png = new Uint8Array(await (await items[0].getType('image/png')).arrayBuffer());
        return items.length + ' ' + [...items[0].types].sort().join(',') + ' ' + text + ' ' + png[1]
        """, in: controller)
        #expect(result == "1 image/png,text/plain copied 80")
        #expect(asker.reads == [.read])
    }

    /// Synchronous, so it cannot wait for the question: false at once, and Luna pastes
    /// for the page once the site may.
    @Test func execCommandPasteAsksAndHandsThePasteToLuna() async throws {
        let (controller, asker) = try await tab(answer: true)

        let result = try await run("""
        const t = document.getElementById('t'); t.focus();
        return String(document.execCommand('paste'))
        """, in: controller)
        #expect(result == "false")
        for _ in 0 ..< 100 where asker.reads.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        #expect(asker.reads == [.paste])
    }

    /// Writing is not asked about, and the page's own copy commands are untouched.
    @Test func writingIsLeftAlone() async throws {
        let (controller, asker) = try await tab(answer: false)
        let result = try await run("""
        return [navigator.clipboard.writeText, navigator.clipboard.write].map(f => String(f).includes('[native code]')).join(',')
            + ' ' + document.queryCommandSupported('copy')
        """, in: controller)
        #expect(result == "true,true true")
        #expect(asker.asked.isEmpty)
    }

    /// Answered in one Space, the clipboard question is still put in another.
    @Test func theAnswerBelongsToTheSpace() {
        let app = SitePermissions()
        let work = UUID(), personal = UUID()
        app.forSpace(work).setAllowed(true, .clipboard, forHost: "paste.example")
        #expect(app.forSpace(work).answer(.clipboard, forHost: "paste.example") == true)
        #expect(app.forSpace(personal).answer(.clipboard, forHost: "paste.example") == nil)
    }
}
