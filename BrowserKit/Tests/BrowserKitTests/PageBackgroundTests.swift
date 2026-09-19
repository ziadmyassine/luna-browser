import Foundation
import Testing
import WebKit
@testable import BrowserKit

/// `TabState.pageBackground` — the colour WebKit says the page is painted on,
/// which §3.2b's bar wears whenever the page itself has no answer for what is
/// under the bar.
///
/// It used to be assigned and read back in the same statement of `publishState`:
/// handing WebKit nil gives the question back to it, and it answers off the next
/// paint, so the read came back with the document that had just gone away.
/// Measured on two documents, `#0a0a14` then `#3a0a0a`: `didFinish` for the
/// second reported the first's `10,10,20`, and Back to the first reported
/// `58,10,10`. Nothing re-read it afterwards, so the answer only became right if
/// some unrelated property happened to change late enough.
///
/// These load real documents, because the whole of the bug was in when WebKit
/// answers — a stubbed web view would have agreed with the broken code.
@Suite("Page background (§3.2b)")
@MainActor
struct PageBackgroundTests {

    private func live() -> TabController {
        let controller = TabController(id: UUID(), dataStore: .nonPersistent())
        controller.activate()
        return controller
    }

    private func load(_ controller: TabController, background: String) async {
        controller.webView?.loadHTMLString(
            "<html><body style='background:\(background)'>page</body></html>", baseURL: nil
        )
    }

    /// True once `condition` holds, or after `seconds` — polled rather than slept
    /// through, so a fast machine does not wait and a slow one is not flaky.
    @discardableResult
    private func settle(within seconds: Double = 5, until condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(40))
        }
        return condition()
    }

    private func matches(_ colour: RGBA?, _ red: Int, _ green: Int, _ blue: Int) -> Bool {
        guard let colour else { return false }
        let wanted = [red, green, blue].map { Double($0) / 255 }
        return zip([colour.r, colour.g, colour.b], wanted).allSatisfy { abs($0 - $1) < 0.01 }
    }

    /// The document on screen, not the one before it.
    @Test func theColourIsTheDocumentThatIsShowing() async {
        let controller = live()
        await load(controller, background: "#0a0a14")
        await settle { matches(controller.state.pageBackground, 10, 10, 20) }
        #expect(matches(controller.state.pageBackground, 10, 10, 20))

        await load(controller, background: "#3a0a0a")
        await settle { matches(controller.state.pageBackground, 58, 10, 10) }
        #expect(
            matches(controller.state.pageBackground, 58, 10, 10),
            "the second document's colour never arrived — nothing re-reads it once WebKit works it out"
        )
    }

    /// The sharp version of the same thing, and the one the old code cannot pass:
    /// a page repainting itself changes no URL, no title and no loading flag, so
    /// there is no other property whose change could carry the new colour out.
    /// A site's own dark-mode toggle is exactly this.
    @Test func aPageThatRepaintsItselfIsPublishedWithoutANavigation() async {
        let controller = live()
        await load(controller, background: "#0a0a14")
        await settle { matches(controller.state.pageBackground, 10, 10, 20) }
        #expect(matches(controller.state.pageBackground, 10, 10, 20))

        _ = try? await controller.webView?.evaluateJavaScript(
            "document.body.style.background = '#3a0a0a'; 1"
        )
        await settle { matches(controller.state.pageBackground, 58, 10, 10) }
        #expect(
            matches(controller.state.pageBackground, 58, 10, 10),
            "the page repainted and the state still carries what it was painted on before"
        )
    }

    /// A colour handed to WebKit stays until it is taken back, so the document
    /// that offered a `theme-color` must not leave it painting the next one's
    /// over-scroll. `publishState` used to re-assign on every publish and hide
    /// this; it only reads now, so the clear has to be its own act.
    @Test func aCommitTakesBackTheColourTheLastDocumentPinned() async {
        let controller = live()
        await load(controller, background: "#0a0a14")
        await settle { matches(controller.state.pageBackground, 10, 10, 20) }

        // Pin it, the way `matchBackgroundToTheme` does for a site that offers a
        // `theme-color` — using the web view's own colour keeps this AppKit-free.
        let pinned = controller.webView?.underPageBackgroundColor
        controller.webView?.underPageBackgroundColor = pinned
        controller.resetPerDocumentState()
        #expect(controller.state.pageBackground == nil)

        await load(controller, background: "#3a0a0a")
        await settle { matches(controller.state.pageBackground, 58, 10, 10) }
        #expect(
            matches(controller.state.pageBackground, 58, 10, 10),
            "the pin outlived the document that set it"
        )
    }
}
