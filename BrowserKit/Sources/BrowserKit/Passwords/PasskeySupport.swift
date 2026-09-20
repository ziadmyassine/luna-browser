import Foundation
import Security
import WebKit

/// §14.10 — passkeys, and the entitlement that gates them.
///
/// # The situation, verified against current documentation
///
/// WebAuthn in a third-party `WKWebView` requires
/// **`com.apple.developer.web-browser.public-key-credential`**. The name is
/// confirmed against Apple's entitlement documentation, and the entitlement is
/// **apply-only**: there is a request form, Apple decides, and the turnaround
/// is theirs. It is how Chrome and Firefox reach passkeys held in Apple
/// Passwords on macOS, and there is no other route — `AuthenticationServices`
/// refuses the same requests without it.
///
/// Luna does not have it today, and cannot: `project.yml` signs ad-hoc
/// (`CODE_SIGN_IDENTITY: "-"`, no team), and the entitlement is attached to a
/// provisioning profile issued against a real team. So the order of operations
/// is the one §14.10 sets out — **request it early, because the wait is
/// Apple's** — and it lands with the Developer ID work in M4 (§24.4).
///
/// # Why Luna says "no authenticator" rather than "no WebAuthn"
///
/// This is the part that is easy to get wrong in either direction. Without the
/// entitlement, `window.PublicKeyCredential` is still **present** in the DOM —
/// WebKit defines the interface regardless — so feature detection succeeds and
/// a site cheerfully shows "Sign in with a passkey". The call then fails. The
/// user is left on a login page whose only offered method does not work, and
/// the password field they could have used is behind a "use another method"
/// link they have no reason to press. **A dead passkey button is worse than no
/// passkey button.**
///
/// The first version of this file therefore deleted the interface outright, so
/// that a page saw a browser which had never shipped WebAuthn. That is too
/// blunt, and GitHub's sign-in page is the case that proves it: "Continue with
/// Google", "Continue with Apple" and the passkey button all arrive in one
/// lazily-fetched fragment, and GitHub only fetches that fragment when
/// `window.PublicKeyCredential` exists. Delete the interface and two sign-in
/// methods that have nothing to do with passkeys vanish with it — leaving a
/// login page that looks broken rather than one that looks passwordless. Sites
/// group their sign-in options together far more often than they gate them
/// apart, so this is not a GitHub quirk to special-case.
///
/// So the interface stays, and Luna answers the question a site actually asks
/// before offering a passkey: **is a platform authenticator available?** No —
/// which is the plain truth about this build, and a state the spec already
/// defines, so a site meeting it is on its documented path rather than a
/// bespoke one. GitHub then loads its fragment, shows Google and Apple, and
/// hides the passkey button on its own. `suppressionScript` is that answer.
///
/// The check is at runtime, not compile time: the day a signed build carries
/// the entitlement, ``isAvailable`` turns true on its own, the script stops
/// being injected, and sites see passkeys. Nothing here needs editing.
public enum PasskeySupport {

    /// The entitlement, spelled once.
    public static let entitlement = "com.apple.developer.web-browser.public-key-credential"

    // There is deliberately no second entitlement named here. An earlier
    // version carried `com.apple.developer.web-browser` as "the one a default
    // browser needs", to be filed alongside. That is wrong: it is **iOS and
    // iPadOS only**, per Apple's entitlement documentation, and is about being
    // the default browser there. macOS needs nothing of the sort — a macOS app
    // becomes the default browser by declaring the `http` and `https` schemes
    // in `CFBundleURLTypes` and calling `LSSetDefaultHandlerForURLScheme`.

    /// Whether this build may actually perform WebAuthn.
    ///
    /// Read from the running process's own code signature rather than from a
    /// build flag, so a Debug build launched from Xcode and a notarised one
    /// answer the same way — and so the answer cannot drift from the bundle
    /// that shipped.
    public static let isAvailable: Bool = hasEntitlement(entitlement)

    /// Reads a boolean entitlement off the current process.
    ///
    /// `SecTaskCreateFromSelf` reads the signature actually loaded into this
    /// process. An unsigned or ad-hoc-signed binary simply has no entitlement
    /// dictionary, which reads as false — the correct answer.
    static func hasEntitlement(_ key: String) -> Bool {
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        guard let value = SecTaskCopyValueForEntitlement(task, key as CFString, nil) else { return false }
        return (value as? Bool) ?? false
    }

    /// Injected at `documentStart` when ``isAvailable`` is false.
    ///
    /// Three things, and each is load-bearing:
    ///
    ///  · **The interface is left in place.** Deleting it takes unrelated
    ///    sign-in options down with it, for the reason set out above this type.
    ///  · **`isUserVerifyingPlatformAuthenticatorAvailable` resolves false**,
    ///    which is the gate a site checks before offering a platform passkey,
    ///    and **`isConditionalMediationAvailable` resolves false**, which is
    ///    the same question asked of the autofill-style passkey field. Both are
    ///    the honest answer for a build that has no authenticator behind them.
    ///  · **`navigator.credentials.get/create` reject** for `publicKey` requests
    ///    with `NotSupportedError`, which is the error the spec defines for an
    ///    authenticator that cannot serve the request. Libraries that skipped
    ///    the gates above and called straight in get a *defined* failure they
    ///    already handle, instead of WebKit's own `NotAllowedError`, which reads
    ///    as "the user cancelled" and invites a retry. Requests that are not
    ///    `publicKey` (`password`, `federated`) are passed through untouched.
    ///
    /// `getClientCapabilities` is WebAuthn L3's replacement for those two
    /// predicates. It is wrapped only where WebKit has shipped it, and only the
    /// keys that name an authenticator are overridden — the rest are left at
    /// whatever WebKit reported, because they are not this script's to answer.
    ///
    /// `forMainFrameOnly: false` at the call site — a federated login in an
    /// iframe checks for the same interface.
    public static let suppressionScript = """
    (function () {
      'use strict';
      var credential = window.PublicKeyCredential;
      if (typeof credential !== 'undefined') {
        var no = function () { return Promise.resolve(false); };
        try {
          credential.isUserVerifyingPlatformAuthenticatorAvailable = no;
          credential.isConditionalMediationAvailable = no;
        } catch (e) { /* a frozen interface is still served by the wrappers below */ }

        var reported = credential.getClientCapabilities;
        if (typeof reported === 'function') {
          var gates = ['passkeyPlatformAuthenticator', 'userVerifyingPlatformAuthenticator',
                       'conditionalCreate', 'conditionalGet', 'hybridTransport'];
          try {
            credential.getClientCapabilities = function () {
              return reported.apply(credential, arguments).then(function (capabilities) {
                var answer = Object.assign({}, capabilities);
                gates.forEach(function (gate) { if (gate in answer) { answer[gate] = false; } });
                return answer;
              });
            };
          } catch (e) { /* as above */ }
        }
      }

      if (!navigator.credentials) { return; }
      var reject = function (name) {
        var original = navigator.credentials[name];
        if (typeof original !== 'function') { return; }
        navigator.credentials[name] = function (options) {
          if (options && options.publicKey) {
            return Promise.reject(new DOMException(
              'Passkeys are not available in this browser yet.', 'NotSupportedError'));
          }
          return original.apply(navigator.credentials, arguments);
        };
      };
      reject('get');
      reject('create');
    })();
    """

    /// The user script, or nil once the entitlement is real.
    ///
    /// Returning nil rather than an empty script matters: an empty
    /// `WKUserScript` is still compiled and run in every frame of every page.
    ///
    /// `@MainActor` because `WKUserScript.init` is — the only caller is
    /// `TabController.attach`, which is main-actor anyway.
    @MainActor
    public static func userScript() -> WKUserScript? {
        guard !isAvailable else { return nil }
        return WKUserScript(
            source: suppressionScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
    }

    /// What the Settings pane says about passkeys. Kept here, beside the flag
    /// it describes, so the copy cannot outlive the state it is describing.
    public static var statusDescription: String {
        isAvailable
            ? String(localized: "Passkeys are available. Luna uses the passkeys in your Apple Passwords.")
            : String(localized: """
            Passkeys are turned off. Using them needs an entitlement only Apple can grant a browser, \
            and Luna has not been granted it yet. Until then Luna tells sites it has no passkey \
            authenticator, so they offer you a password instead of a button that cannot work.
            """)
    }
}
