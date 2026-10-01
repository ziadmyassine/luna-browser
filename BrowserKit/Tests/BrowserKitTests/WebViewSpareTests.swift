import Foundation
import Testing
import WebKit
@testable import BrowserKit

@MainActor
@Suite("The spare web view", .serialized)
struct WebViewSpareTests {

    /// Polled with `await`, which lets WebKit's callbacks reach the main
    /// actor; spinning the run loop by hand from a test does not.
    private func settle(until done: () -> Bool) async {
        let deadline = Date().addingTimeInterval(20)
        while !done(), Date() < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    @Test("a tab in the spare's Space gets the spare, with nothing in its back list")
    func tabTakesTheSpare() async throws {
        WebViewFactory.keepsSpare = true
        defer { WebViewFactory.keepsSpare = false; WebViewFactory.dropSpare() }
        let store = WKWebsiteDataStore.nonPersistent()
        WebViewFactory.prepareSpare(dataStore: store, webExtensionController: nil)
        let spare = try #require(WebViewFactory.spareWebView)
        await settle { !spare.isLoading }

        let tab = TabController(id: UUID(), dataStore: store)
        tab.load(URL(string: "about:blank#page")!)
        #expect(tab.webView === spare)
        await settle { !spare.isLoading }
        #expect(spare.backForwardList.backList.isEmpty, "the empty document became a page to go back to")
        tab.hibernate()
    }

    /// The route every new tab and every waking tab takes: a cold controller
    /// told its address, then activated. The spare's `about:blank` once read
    /// as a page already there, and the tab stayed empty.
    @Test("a tab woken with only its address loads that address into the spare")
    func wokenTabLoadsIntoTheSpare() async throws {
        WebViewFactory.keepsSpare = true
        defer { WebViewFactory.keepsSpare = false; WebViewFactory.dropSpare() }
        let store = WKWebsiteDataStore.nonPersistent()
        WebViewFactory.prepareSpare(dataStore: store, webExtensionController: nil)
        let spare = try #require(WebViewFactory.spareWebView)
        await settle { !spare.isLoading }

        let page = URL(string: "about:blank#typed")!
        let tab = TabController(id: UUID(), dataStore: store)
        tab.restore(interactionState: nil, fallbackURL: page)
        tab.activate()
        #expect(tab.webView === spare)
        await settle { spare.url == page && !spare.isLoading }
        #expect(spare.url == page, "the tab kept the spare's empty document")
        tab.hibernate()
    }

    @Test("a tab in another Space builds its own, and the spare stays")
    func otherSpaceBuildsItsOwn() async throws {
        WebViewFactory.keepsSpare = true
        defer { WebViewFactory.keepsSpare = false; WebViewFactory.dropSpare() }
        let mine = WKWebsiteDataStore.nonPersistent()
        WebViewFactory.prepareSpare(dataStore: mine, webExtensionController: nil)
        let spare = try #require(WebViewFactory.spareWebView)
        await settle { !spare.isLoading }

        let theirs = WebViewFactory.makeWebView(dataStore: .nonPersistent())
        #expect(theirs !== spare)
        #expect(WebViewFactory.spareWebView === spare)
    }

    @Test("with the spare off, nothing is built ahead")
    func offBuildsNothing() {
        WebViewFactory.prepareSpare(dataStore: .nonPersistent(), webExtensionController: nil)
        #expect(WebViewFactory.spareWebView == nil)
    }
}
