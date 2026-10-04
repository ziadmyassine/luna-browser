import Foundation
import WebKit

/// Everything a `TabController` cannot do itself, because doing it needs AppKit or the
/// tab list — native sheets, opening a new tab, handing a URL to another app.
///
/// The first four methods are the contract's required set. The rest carry the parts of
/// §4.2 that have no AppKit-free implementation; they have safe defaults so a host can
/// adopt them one at a time, but a browser that leaves them all at the default has no
/// JS dialogs, no camera prompt, no file picker and no `mailto:`.
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

    /// A link ⌘-clicked or middle-clicked: a new tab beside this one, left
    /// behind it unless `inBackground` is false (⌘⇧, as Safari).
    func tabController(_ controller: TabController, wantsToOpenInNewTab url: URL, inBackground: Bool)

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
    /// The tab built itself another web view — crossing between an extension's
    /// pages and the web — and whoever shows it has to show the new one.
    func tabControllerDidReplaceWebView(_ controller: TabController)

    func tabController(_ controller: TabController, runJavaScriptAlert message: String) async
    func tabController(_ controller: TabController, runJavaScriptConfirm message: String) async -> Bool
    func tabController(
        _ controller: TabController,
        runJavaScriptPrompt prompt: String,
        defaultText: String?
    ) async -> String?

    /// §17.8: the page at `host` wants the camera, the microphone or the location, and
    /// has no answer for this site yet. True or false is the user's answer, which the
    /// controller keeps; nil is no answer (unseen, or dismissed), a no for now only.
    func tabController(
        _ controller: TabController,
        wantsAccessTo permissions: [BrowserStore.SitePermission],
        forHost host: String
    ) async -> Bool?

    /// A page's `<input type=file>`: the files the user picked, or nil for Cancel.
    func tabController(
        _ controller: TabController,
        chooseFilesAllowingMultiple multiple: Bool,
        directories: Bool
    ) async -> [URL]?

    /// §18.8: a site that may read the clipboard is reading it. The pasteboard by MIME
    /// type, an image as base64 and an empty clipboard as an empty map; for `.paste`,
    /// Edit ▸ Paste on the page and an empty map. Nil refuses: the tab is not the one
    /// in front of the user, or the clipboard is not the host's to read.
    func tabController(_ controller: TabController, readsClipboard request: ClipboardRequest) async -> [String: String]?

    // MARK: - §14's password UI
    //
    // The engine finds the form and holds the secrets; the popover and the chip
    // are AppKit and live in `Luna/UI/Passwords/`. These three are how one reaches
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

    /// §17: a pop-up or a tab-under was refused and is now first in
    /// `controller.popups.blocked`.
    func tabController(_ controller: TabController, didBlockPopup url: URL)

    /// §17: this tab is a pop-up whose destination was refused. Close it, and
    /// leave the user on the tab that opened it.
    func tabControllerWantsToClose(_ controller: TabController)

    /// A copy button on a rendered Markdown page was pressed. BrowserKit has
    /// no pasteboard; the host puts `code` on it.
    func tabController(_ controller: TabController, didCopyCode code: String)

    /// The Markdown file being edited changed on disk since it was read.
    /// Saving has stopped; `resolveDiskConflict` restarts it either way.
    func tabController(_ controller: TabController, markdownChangedOnDisk url: URL)

    /// §15.5: a PDF big enough, or slow enough, that the viewer will sit empty
    /// for a while. `downloadArrivingPDFInstead` is the offer to make.
    func tabController(_ controller: TabController, isSlowToOpen pdf: PDFArrival)

    /// §18.4a: the Picture in Picture window's "back to tab" was pressed for a
    /// video from this tab. Select it, in its window and Space.
    func tabControllerDidReturnFromPictureInPicture(_ controller: TabController)
}

public extension TabControllerDelegate {

    @discardableResult
    func tabController(_ controller: TabController, wantsToOpenExternally url: URL) -> Bool { false }

    func tabController(_ controller: TabController, didUpdateFavicon png: Data?) {}

    func tabController(_ controller: TabController, wantsToOpenInNewTab url: URL, inBackground: Bool) {}

    func tabControllerDidRecoverFromProcessTermination(_ controller: TabController) {}
    func tabControllerDidReplaceWebView(_ controller: TabController) {}

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
        wantsAccessTo permissions: [BrowserStore.SitePermission],
        forHost host: String
    ) async -> Bool? { nil }

    func tabController(
        _ controller: TabController,
        chooseFilesAllowingMultiple multiple: Bool,
        directories: Bool
    ) async -> [URL]? { nil }

    /// Fail closed, like the camera.
    func tabController(_ controller: TabController, readsClipboard request: ClipboardRequest) async -> [String: String]? { nil }

    func tabController(_ controller: TabController, wantsToOfferCredentials offer: PasswordOffer) {}

    func tabController(_ controller: TabController, wantsToSuggestPassword suggestion: PasswordSuggestion) {}

    func tabController(_ controller: TabController, wantsToSavePassword request: PasswordSaveRequest) {}

    func tabController(_ controller: TabController, wantsToMovePasswordUITo fieldRect: CGRect) {}

    func tabControllerDidDismissPasswordUI(_ controller: TabController) {}

    func tabController(_ controller: TabController, didBlockPopup url: URL) {}

    func tabControllerWantsToClose(_ controller: TabController) {}

    func tabController(_ controller: TabController, didCopyCode code: String) {}

    func tabController(_ controller: TabController, markdownChangedOnDisk url: URL) {}

    func tabController(_ controller: TabController, isSlowToOpen pdf: PDFArrival) {}

    func tabControllerDidReturnFromPictureInPicture(_ controller: TabController) {}
}
