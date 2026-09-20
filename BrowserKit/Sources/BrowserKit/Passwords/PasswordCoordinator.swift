import Foundation
import WebKit

/// What the UI is being asked to offer, and on what evidence (§14.3).
public struct PasswordOffer: Sendable {
    /// Matching credentials, newest first. Never empty when an offer is made.
    public let credentials: [Credential]
    /// Where to anchor the popover, in web-view coordinates.
    public let fieldRect: CGRect
    /// The page's site key, for the popover's header.
    public let site: String
    /// §14.8: this page was reached through a server redirect chain. Not a
    /// refusal — a great many legitimate logins redirect — but the UI says so,
    /// because "I typed bank.example and something else is asking for my
    /// password" is the one thing the user can judge and Luna cannot.
    public let viaRedirect: Bool
    /// The page is not on HTTPS. A password typed here goes out in clear.
    public let isInsecure: Bool
}

/// A signup form where §14.5 has something to offer.
public struct PasswordSuggestion: Sendable {
    public let generated: String
    public let fieldRect: CGRect
    public let site: String
}

/// §14.4's chip. Nothing is written until the user presses Save.
public struct PasswordSaveRequest: Sendable {
    public enum Kind: Sendable {
        /// No credential for this site+username yet.
        case save
        /// One exists and the password differs — the user changed it.
        case update
    }

    public let kind: Kind
    public let site: String
    public let username: String
    public let isInsecure: Bool
    /// Held here and nowhere else until the user answers. Not in `Credential`,
    /// which is the type the rest of the app passes around.
    let password: String
    let originURL: URL?

    public var credential: NewCredential {
        NewCredential(site: site, username: username, password: password, originURL: originURL)
    }
}

/// One tab's password state and the §14.8 gate every fill passes through.
///
/// Split out of `TabController` rather than added to it: a Swift extension
/// cannot carry storage, and §33's warning about the 4,000-line manager applies
/// to the engine class most of all. `TabController` holds one reference to this
/// and forwards two calls.
///
/// # §14.8, rule by rule, and where each one is enforced
///
/// | Rule | Enforced |
/// |---|---|
/// | Never persist without an explicit user action | Nothing here writes. `PasswordSaveRequest` reaches the UI; only the user pressing Save calls `CredentialStore.save`. |
/// | Never fill cross-origin, or an iframe whose origin differs from the page | ``isFrameTrusted(_:in:)``, against `WKFrameInfo.securityOrigin` — which WebKit fills in and the page cannot forge. |
/// | Require a recent user gesture before filling | A fill only ever begins with a click on Luna's own native popover row. There is no code path from a page event to a filled field. |
/// | Never expose credentials to page JavaScript | The password is read from the Keychain inside ``fill(_:with:)`` and passed to `callAsyncJavaScript` as a bound argument. It is never in a source string, never in `TabState`, never logged. |
/// | Treat a fill after a redirect chain as suspicious | ``sawServerRedirect``, set by the navigation delegate and carried on the offer. |
@MainActor
public final class PasswordCoordinator {

    weak var tab: TabController?

    /// The form the page is currently showing, if any.
    public private(set) var form: PasswordForms.Form?

    /// The frame that reported it. Held so a fill goes back to exactly that
    /// frame rather than to whichever frame is frontmost when the user clicks.
    private var formFrame: WKFrameInfo?

    /// §14.8. Set by `didReceiveServerRedirect…`, cleared on a fresh
    /// provisional navigation, and read when an offer is built.
    var sawServerRedirect = false

    /// The last submit the page reported, awaiting the §14.4 chip's answer.
    private var pendingSave: PasswordSaveRequest?

    /// Whether a picker is currently up for this tab. Tracked here rather than
    /// asked of the view layer: `BrowserKit` cannot see AppKit, and the engine
    /// is the thing that knows whether it raised an offer.
    private var isOffering = false

    public init() {}

    // MARK: - Page events

    func handle(_ message: WKScriptMessage) {
        guard PasswordSettings.isEnabled else { return }
        guard let webView = tab?.webView, let event = PasswordForms.event(from: message.body) else { return }
        // Every branch below is reachable from a hostile page, so the origin
        // gate comes before any of them rather than inside the ones that fill.
        guard isFrameTrusted(message.frameInfo, in: webView) else { return }

        switch event {
        case let .formDetected(form):
            // **A detected form is not an offer.** The page reports one on
            // load, on every DOM mutation and on every frame of a scroll, so
            // offering here would pop a picker over a page nobody has touched
            // and then rebuild it sixty times a second while the user scrolls
            // past. All a detection does is keep the form — and move a picker
            // that is already up, because its anchor has moved with the page.
            self.form = form
            formFrame = message.frameInfo
            if isOffering { tab.map { $0.delegate?.tabController($0, wantsToMovePasswordUITo: form.fieldRect) } }
        case let .fieldFocused(form):
            // Focus is the user arriving at the field, and it is the only
            // thing that raises an offer.
            self.form = form
            formFrame = message.frameInfo
            offerIfPossible(form, in: webView)
        case let .submitted(username, password):
            noteSubmit(username: username, password: password, in: webView)
        case .dismissed:
            form = nil
            formFrame = nil
            isOffering = false
            tab.map { $0.delegate?.tabControllerDidDismissPasswordUI($0) }
        }
    }

    /// §14.8's origin rule.
    ///
    /// **Compared against `WKFrameInfo.securityOrigin`, never against anything
    /// the script said.** A script running inside a hostile iframe can claim
    /// any origin it likes; `frameInfo` is filled in by WebKit from the frame's
    /// actual security origin and is not reachable from page JavaScript.
    ///
    /// The main frame is trusted by definition — it *is* the page. A subframe
    /// must match it on scheme, host and port: a same-*site* check would let
    /// `evil.example.com` inside `bank.example.com` collect the password,
    /// which is precisely the attack the rule exists for, so this is the one
    /// place in the feature that does **not** go through `PublicSuffix`.
    func isFrameTrusted(_ frame: WKFrameInfo, in webView: WKWebView) -> Bool {
        if frame.isMainFrame { return true }
        guard let page = webView.url,
              let host = page.host?.lowercased(),
              let scheme = page.scheme?.lowercased()
        else { return false }
        let origin = frame.securityOrigin
        guard origin.host.lowercased() == host, origin.protocol.lowercased() == scheme else { return false }
        let pagePort = page.port ?? (scheme == "https" ? 443 : 80)
        // `securityOrigin.port` is 0 for the scheme's default port.
        let framePort = origin.port == 0 ? (scheme == "https" ? 443 : 80) : origin.port
        return pagePort == framePort
    }

    private func offerIfPossible(_ form: PasswordForms.Form, in webView: WKWebView) {
        guard let tab, let site = PublicSuffix.siteKey(forHost: webView.url?.host()) else { return }
        let insecure = webView.url?.scheme?.lowercased() != "https"

        // A signup form wants a *new* password, not an old one (§14.5).
        if form.isSignup, PasswordSettings.offersGeneratedPasswords {
            let rules = form.passwordRules.flatMap(PasswordGenerator.parse) ?? .default
            isOffering = true
            tab.delegate?.tabController(tab, wantsToSuggestPassword: PasswordSuggestion(
                generated: PasswordGenerator.generate(rules: rules),
                fieldRect: form.fieldRect,
                site: site
            ))
            return
        }

        Task { [weak self] in
            let matches = await CredentialStore.shared.credentials(forSite: site)
            guard let self, !matches.isEmpty, self.form?.id == form.id else { return }
            self.isOffering = true
            tab.delegate?.tabController(tab, wantsToOfferCredentials: PasswordOffer(
                credentials: matches,
                fieldRect: form.fieldRect,
                site: site,
                viaRedirect: self.sawServerRedirect,
                isInsecure: insecure
            ))
        }
    }

    // MARK: - §14.4

    private func noteSubmit(username: String, password: String, in webView: WKWebView) {
        guard PasswordSettings.offersToSave else { return }
        guard let tab, let url = webView.url, let site = PublicSuffix.siteKey(forHost: url.host()) else { return }
        // "Never for this site" (§14.4), in the same `siteSettings` row every
        // other per-site answer lives in.
        guard SitePermissions.shared.isAllowed(.savePasswords, forHost: url.host()) else { return }

        Task { [weak self] in
            let existing = await CredentialStore.shared.credentials(forSite: site)
            let match = existing.first { $0.username == username }
            // Same username *and* same password: the user signed in with what
            // is already saved, so there is nothing to ask about. This is the
            // overwhelmingly common case, and a chip here would train the user
            // to dismiss the one that matters.
            if let match, await CredentialStore.shared.password(for: match) == password { return }

            let request = PasswordSaveRequest(
                kind: match == nil ? .save : .update,
                site: site,
                username: username,
                isInsecure: url.scheme?.lowercased() != "https",
                password: password,
                originURL: url
            )
            guard let self else { return }
            self.pendingSave = request
            tab.delegate?.tabController(tab, wantsToSavePassword: request)
        }
    }

    /// The user pressed Save or Update. The only write path in the feature.
    @discardableResult
    public func confirmSave(_ request: PasswordSaveRequest) async -> Bool {
        pendingSave = nil
        return await CredentialStore.shared.save(request.credential)
    }

    /// "Never for this site" — persisted as a per-site answer so the chip never
    /// comes back for this host (§14.4, §11.1).
    public func declineForever(_ request: PasswordSaveRequest) {
        pendingSave = nil
        SitePermissions.shared.setAllowed(false, .savePasswords, forHost: request.site)
    }

    public func dismissSave() { pendingSave = nil }

    // MARK: - §14.3's fill

    /// Fills the current form with `credential`.
    ///
    /// Only ever called from a click on Luna's native popover, which is the
    /// user gesture §14.8 requires. The Keychain read happens here, one field
    /// fill later the string is out of scope, and it is never stored on the
    /// coordinator, the tab or the state.
    public func fill(_ credential: Credential) async {
        isOffering = false
        guard let webView = tab?.webView, let requested = form else { return }
        // Re-checked at the moment of the fill, not only when the offer was
        // built: a page can navigate between Luna deciding to offer and the
        // user clicking, and the credential must not follow it somewhere else.
        guard PublicSuffix.isSameSite(webView.url?.host(), credential.site) else { return }

        // Touch ID **before** the Keychain read, so a cancelled prompt means
        // the password was never fetched into this process at all.
        guard await PasswordAuthorization.confirmFill(for: credential.site) else { return }

        // That prompt is modal and can sit there as long as the user likes,
        // which is ample time for the page underneath to navigate or re-render.
        // So everything the first two guards established is established again
        // on the other side of it, against the form the page is showing *now*.
        guard let webView = tab?.webView, let current = form, current.id == requested.id,
              PublicSuffix.isSameSite(webView.url?.host(), credential.site)
        else { return }
        let form = current

        let password = await CredentialStore.shared.password(for: credential)
        await PasswordForms.fill(
            form, username: credential.username, password: password, in: webView, frame: formFrame
        )
    }

    /// §14.5 — put a generated password into the signup form.
    public func fillGenerated(_ password: String) async {
        isOffering = false
        guard let webView = tab?.webView, let form else { return }
        await PasswordForms.fill(form, username: "", password: password, in: webView, frame: formFrame)
    }
}
