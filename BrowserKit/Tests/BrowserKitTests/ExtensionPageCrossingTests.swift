import Foundation
import Testing
@testable import BrowserKit

/// A tab's web view can show one extension's pages or the web, never both
/// (`WKWebExtensionContext.webViewConfiguration`), so crossing between them
/// takes another view. 1Password's Sign in, sending its welcome page to its
/// website, was dropped in silence before this.
@Suite("Crossing between an extension and the web")
struct ExtensionPageCrossingTests {

    private let welcome = URL(string: "webkit-extension://aeblfdkh/app/app.html#/page/welcome")!
    private let options = URL(string: "webkit-extension://aeblfdkh/options.html")!
    private let other = URL(string: "webkit-extension://zzzzzzzz/popup.html")!
    private let site = URL(string: "https://start.1password.com/signin/?auth-only=1")!

    @Test func anExtensionPageGoingToTheWebCrosses() {
        #expect(TabController.crossesExtensionBoundary(from: welcome, to: site))
    }

    @Test func aWebPageGoingToAnExtensionPageCrosses() {
        #expect(TabController.crossesExtensionBoundary(from: site, to: welcome))
    }

    @Test func anotherExtensionsPageCrosses() {
        #expect(TabController.crossesExtensionBoundary(from: welcome, to: other))
    }

    @Test func movingWithinOneSideDoesNot() {
        #expect(!TabController.crossesExtensionBoundary(from: welcome, to: options))
        #expect(!TabController.crossesExtensionBoundary(from: site, to: URL(string: "https://example.com")!))
    }

    /// An extension tab's first load arrives before its view has a page, in a
    /// view already built for it.
    @Test func aFirstLoadDoesNot() {
        #expect(!TabController.crossesExtensionBoundary(from: nil, to: welcome))
        #expect(!TabController.crossesExtensionBoundary(from: nil, to: site))
    }
}
