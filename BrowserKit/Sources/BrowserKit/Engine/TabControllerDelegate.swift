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

    /// The receiver must set `download.delegate` before returning, and must keep
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

    // MARK: - §14's password UI
    //
    // The engine finds the form and holds the secrets; the popover and the chip
    // are AppKit and live in `UI/Passwords/`. These three are how one reaches
    // the other. They default to no-ops like the rest of the optional set, so a
    // host that has not built the UI simply never offers to fill — which is a
    // browser without autofill, not a broken one.

    /// A login form on this page has saved credentials to offer (§14.3).
    /// Show a native popover anchored to `offer.fieldRect` — never an
    /// injected overlay, which a page could read or spoof.
    func tabController(_ controller: TabController, wantsToOfferCredentials offer: PasswordOffer)

    /// A signup form, and §14.5 has a password to suggest.
    func tabController(_ controller: TabController, wantsToSuggestPassword suggestion: PasswordSuggestion)

    /// Credentials were just submitted (§14.4). Show the non-modal chip.
    /// Nothing has been saved — `PasswordCoordinator.confirmSave` is the
    /// only thing that writes, and only the user can call it.
    func tabController(_ controller: TabController, wantsToSavePassword request: PasswordSaveRequest)

    /// The anchor field moved — the page scrolled, or re-laid itself out —
    /// while a picker is up. Move it; do not rebuild it.
    func tabController(_ controller: TabController, wantsToMovePasswordUITo fieldRect: CGRect)

    /// The form or the field went away; take any password UI down with it.
    func tabControllerDidDismissPasswordUI(_ controller: TabController)
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

    func tabController(_ controller: TabController, wantsToOfferCredentials offer: PasswordOffer) {}

    func tabController(_ controller: TabController, wantsToSuggestPassword suggestion: PasswordSuggestion) {}

    func tabController(_ controller: TabController, wantsToSavePassword request: PasswordSaveRequest) {}

    func tabController(_ controller: TabController, wantsToMovePasswordUITo fieldRect: CGRect) {}

    func tabControllerDidDismissPasswordUI(_ controller: TabController) {}
}
