import Foundation
import WebKit

/// Everything a `TabController` cannot do itself, because doing it needs AppKit or the
/// tab list — native sheets, opening a new tab, handing a URL to another app.
///
/// The first four methods are the contract's required set. The rest carry the parts of
/// §4.2 that have no AppKit-free implementation; they have safe defaults so a host can
/// adopt them one at a time, but a browser that leaves them all at the default has no
/// JS dialogs, no camera prompt and no `mailto:`.
@MainActor
public protocol TabControllerDelegate: AnyObject {
    func tabController(_ controller: TabController, didChange state: TabState)

    /// Must return a web view built from `configuration` — see
    /// `TabController.activate(with:)`. Returning nil makes `window.open` and
    /// `target="_blank"` silently do nothing.
    func tabController(
        _ controller: TabController,
        wantsNewTabFor url: URL?,
        configuration: WKWebViewConfiguration
    ) -> WKWebView?

    /// The receiver **must** set `download.delegate` before returning, and must keep
    /// that delegate alive itself — `WKDownload.delegate` is weak, WebKit asks for a
    /// destination immediately, and a download with no live delegate stalls silently.
    func tabController(_ controller: TabController, didStartDownload download: WKDownload)

    func tabController(_ controller: TabController, didFailWith error: Error)

    /// A non-web scheme (`mailto:`, `tel:`, an app's own). Return true if it was handed
    /// off; the navigation is cancelled either way.
    @discardableResult
    func tabController(_ controller: TabController, wantsToOpenExternally url: URL) -> Bool

    /// PNG bytes for the page's icon, or nil when none could be found (§4.7).
    func tabController(_ controller: TabController, didUpdateFavicon png: Data?)

    /// The WebContent process died and was rebuilt from `interactionState` (§19.3).
    /// Show the "restored" toast here.
    func tabControllerDidRecoverFromProcessTermination(_ controller: TabController)

    func tabController(_ controller: TabController, runJavaScriptAlert message: String) async
    func tabController(_ controller: TabController, runJavaScriptConfirm message: String) async -> Bool
    func tabController(
        _ controller: TabController,
        runJavaScriptPrompt prompt: String,
        defaultText: String?
    ) async -> String?

    func tabController(
        _ controller: TabController,
        requestMediaCapture type: WKMediaCaptureType,
        origin: URL?
    ) async -> WKPermissionDecision
}

public extension TabControllerDelegate {

    @discardableResult
    func tabController(_ controller: TabController, wantsToOpenExternally url: URL) -> Bool { false }

    func tabController(_ controller: TabController, didUpdateFavicon png: Data?) {}

    func tabControllerDidRecoverFromProcessTermination(_ controller: TabController) {}

    func tabController(_ controller: TabController, runJavaScriptAlert message: String) async {}

    func tabController(_ controller: TabController, runJavaScriptConfirm message: String) async -> Bool { false }

    func tabController(
        _ controller: TabController,
        runJavaScriptPrompt prompt: String,
        defaultText: String?
    ) async -> String? { nil }

    /// Fail closed: a browser with no permission UI must not hand out the camera.
    func tabController(
        _ controller: TabController,
        requestMediaCapture type: WKMediaCaptureType,
        origin: URL?
    ) async -> WKPermissionDecision { .deny }
}
