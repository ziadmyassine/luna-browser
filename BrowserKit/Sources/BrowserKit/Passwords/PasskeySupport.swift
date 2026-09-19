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
/// # Why Luna actively hides passkeys until then
///
/// This is the part that is easy to get wrong by doing nothing. Without the
/// entitlement, `window.PublicKeyCredential` is still **present** in the DOM —
/// WebKit defines the interface regardless — so feature detection succeeds and
/// a site cheerfully shows "Sign in with a passkey". The call then fails, or
/// worse hangs on a sheet that never appears. The user is left on a login page
/// whose only offered method does not work, and the password field they could
/// have used is behind a "use another method" link they have no reason to
/// press.
///
/// A dead passkey button is **worse than no passkey button**. So until the
/// entitlement is real, Luna removes the interface and lets sites fall back to
/// passwords — which Luna does support. This is the workaround §14.10 names,
/// and `suppressionScript` is it.
///
/// The check is at runtime, not compile time: the day a signed build carries
/// the entitlement, ``isAvailable`` turns true on its own, the script stops
/// being injected, and sites see passkeys. Nothing here needs editing.
public enum PasskeySupport {

    /// The entitlement, spelled once.
    public static let entitlement = "com.apple.developer.web-browser.public-key-credential"

    /// The sibling entitlement a default browser needs. Not used here, but
    /// named so the M4 request covers both in one submission rather than two
    /// round trips through Apple.
    public static let browserEntitlement = "com.apple.developer.web-browser"

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
    ///  · **`delete window.PublicKeyCredential`** so `if (window.PublicKeyCredential)`
    ///    — the detection every WebAuthn library performs — is false.
    ///  · **`navigator.credentials.get/create` reject** for `publicKey` requests
    ///    with `NotSupportedError`, which is the error the spec defines for an
    ///    authenticator that cannot serve the request. Libraries that skipped
    ///    detection and called straight in get a *defined* failure they already
    ///    handle, instead of a hang. Requests that are not `publicKey`
    ///    (`password`, `federated`) are passed through untouched.
    ///  · **`isUserVerifyingPlatformAuthenticatorAvailable` is gone with the
    ///    interface**, which is what conditional-UI sites check before showing
    ///    a passkey field at all.
    ///
    /// Written to be indistinguishable from a browser that never shipped
    /// WebAuthn: the properties are deleted, not stubbed with something a page
    /// can detect and complain about.
    ///
    /// `forMainFrameOnly: false` at the call site — a federated login in an
    /// iframe checks for the same interface.
    public static let suppressionScript = """
    (function () {
      'use strict';
      try {
        delete window.PublicKeyCredential;
        delete window.AuthenticatorAttestationResponse;
        delete window.AuthenticatorAssertionResponse;
        delete window.AuthenticatorResponse;
      } catch (e) { /* a frozen window is still better served by the wrappers below */ }

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
            and Luna has not been granted it yet. Until then Luna hides passkeys from sites rather \
            than offering a sign-in button that cannot work, so sites fall back to a password.
            """)
    }
}
