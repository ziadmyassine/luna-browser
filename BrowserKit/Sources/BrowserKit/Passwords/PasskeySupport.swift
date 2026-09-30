import Foundation
import Security
import WebKit

/// §14.10 — passkeys, and the entitlement that gates them.
///
/// WebAuthn in a third-party `WKWebView` requires
/// `com.apple.developer.web-browser.public-key-credential`, which Apple grants
/// on request and attaches to a provisioning profile for a real team; it is
/// how Chrome and Firefox reach passkeys in Apple Passwords, and
/// `AuthenticationServices` refuses the same requests without it. Luna signs
/// ad-hoc today (`CODE_SIGN_IDENTITY: "-"`), so the entitlement lands with the
/// Developer ID work in M4 (§24.4).
///
/// Without it, `window.PublicKeyCredential` is still defined, so a site offers
/// "Sign in with a passkey" and the call then fails. Deleting the interface is
/// too blunt: GitHub fetches the fragment holding "Continue with Google",
/// "Continue with Apple" and the passkey button only when the interface
/// exists, and sites group sign-in options like this far more often than they
/// gate them apart. So the interface stays and Luna answers the question a
/// site asks before offering a passkey, whether a platform authenticator is
/// available, with the spec-defined no; GitHub then hides the passkey button
/// itself.
///
/// The check is at runtime: once a signed build carries the entitlement,
/// ``isAvailable`` turns true, the script stops being injected, and sites see
/// passkeys with no edit here.
public enum PasskeySupport {

    /// The entitlement, spelled once.
    public static let entitlement = "com.apple.developer.web-browser.public-key-credential"

    // No second entitlement belongs here. `com.apple.developer.web-browser` is
    // iOS and iPadOS only, per Apple's entitlement documentation; a macOS app
    // becomes the default browser by declaring `http` and `https` in
    // `CFBundleURLTypes` and calling `LSSetDefaultHandlerForURLScheme`.

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
    ///  · The interface is left in place, for the reason given on this type.
    ///  · `isUserVerifyingPlatformAuthenticatorAvailable` and
    ///    `isConditionalMediationAvailable` resolve false: the gates a site
    ///    checks before offering a platform passkey or a passkey autofill field.
    ///  · `navigator.credentials.get/create` reject `publicKey` requests with
    ///    `NotSupportedError`, the spec's error for an authenticator that cannot
    ///    serve the request, so a library that skipped the gates gets a failure
    ///    it already handles rather than WebKit's `NotAllowedError`, which reads
    ///    as "the user cancelled" and invites a retry. Other requests pass
    ///    through untouched.
    ///
    /// `getClientCapabilities`, WebAuthn L3's replacement for those predicates,
    /// is wrapped only where WebKit ships it, and only the keys that name an
    /// authenticator are overridden; the rest are WebKit's to answer.
    ///
    /// `forMainFrameOnly: false` at the call site: a federated login in an
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
