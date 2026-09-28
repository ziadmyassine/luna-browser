@testable import BrowserKit
import Foundation
import Testing
import WebKit

/// The parts of pages hidden for good: which site a list is filed under, the
/// stylesheet it becomes, the table it is kept in, and a private window's copy.
@Suite("Hidden elements")
@MainActor
struct HiddenElementsTests {

    private let banner = HiddenElements.Element(selector: "#cookie-bar", label: "Cookie bar")
    private let rail = HiddenElements.Element(selector: "aside.related", label: "Sidebar")

    @Test func aSiteIsItsHostWithoutWWW() {
        #expect(HiddenElements.site(of: "WWW.Example.COM.") == "example.com")
        #expect(HiddenElements.site(of: "news.example.com") == "news.example.com")
        // `www.com` is a site, not a prefix on nothing.
        #expect(HiddenElements.site(of: "www.com") == "www.com")
        #expect(HiddenElements.site(of: nil) == nil)
        #expect(HiddenElements.site(of: "") == nil)
    }

    /// One rule per selector, so a selector WebKit cannot parse takes only
    /// itself down.
    @Test func theStylesheetIsOneRulePerSelectorInTheOrderTheyWereHidden() {
        let elements = HiddenElements()
        elements.hide(banner, onHost: "www.example.com")
        elements.hide(rail, onHost: "example.com")
        elements.hide(banner, onHost: "example.com")
        #expect(elements.elements(onHost: "example.com").map(\.selector) == ["#cookie-bar", "aside.related"])
        #expect(elements.css(forHost: "www.example.com") == """
        #cookie-bar { display: none !important; }
        aside.related { display: none !important; }
        """)
        #expect(elements.css(forHost: "other.example").isEmpty)

        elements.restore(selector: "#cookie-bar", onHost: "example.com")
        #expect(elements.elements(onHost: "example.com") == [rail])
    }

    @Test func theTableKeepsEachSitesListAcrossLaunches() async throws {
        let store = try makeTemporaryStore()
        try await store.hideElement(banner, host: "example.com")
        try await store.hideElement(rail, host: "example.com")
        try await store.hideElement(banner, host: "news.example")
        // The same selector again replaces its row rather than adding a second.
        try await store.hideElement(HiddenElements.Element(selector: "#cookie-bar", label: "Banner"), host: "example.com")
        try await store.restoreElement(selector: "aside.related", host: "example.com")

        let loaded = try await store.hiddenElements()
        #expect(loaded["example.com"]?.map(\.label) == ["Banner"])
        #expect(loaded["news.example"]?.map(\.selector) == ["#cookie-bar"])

        let elements = HiddenElements()
        elements.start(browserStore: store)
        for _ in 0 ..< 100 where elements.elements(onHost: "example.com").isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(elements.elements(onHost: "www.example.com").map(\.label) == ["Banner"])
    }

    /// §5.6: a private window wears what the user has hidden everywhere, and
    /// what it hides or shows again stays in that window.
    @Test func aPrivateScopeReadsThroughAndWritesOnlyToItself() {
        let main = HiddenElements()
        main.hide(banner, onHost: "example.com")
        let scoped = HiddenElements(fallback: main)
        #expect(scoped.elements(onHost: "example.com") == [banner])

        scoped.hide(rail, onHost: "example.com")
        scoped.restore(selector: "#cookie-bar", onHost: "example.com")
        #expect(scoped.elements(onHost: "example.com") == [rail])
        #expect(main.elements(onHost: "example.com") == [banner])

        scoped.hide(banner, onHost: "example.com")
        #expect(scoped.elements(onHost: "example.com").map(\.selector) == ["#cookie-bar", "aside.related"])
    }

    @Test func aPersistentStoreSharesTheAppsListAndAPrivateOneDoesNot() {
        #expect(HiddenElements.scope(for: .default()) === HiddenElements.shared)
        let store = WKWebsiteDataStore.nonPersistent()
        let scoped = HiddenElements.scope(for: store)
        #expect(scoped !== HiddenElements.shared)
        #expect(HiddenElements.scope(for: store) === scoped)
    }
}
