import Foundation
import WebKit

/// The page side of §14.3–§14.5: finding login forms, reporting them, filling
/// them, and noticing a submit.
///
/// Nothing in this file renders UI. §14.3 is explicit that the credential
/// picker is a native popover anchored to the field and never an injected DOM
/// overlay, "a page must not be able to read or spoof it". So the script's
/// entire job is to describe the form and its geometry; the list of usernames
/// exists only in Swift, and a compromised page can learn nothing from it but
/// the fact that Luna noticed a password field — which it can see anyway.
public enum PasswordForms {

    /// One `postMessage` name for every direction. Registered per web view by
    /// `TabController.attach`.
    public static let messageName = "lunaPasswords"

    /// What the page is telling us.
    public enum Event: Sendable {
        /// A login form appeared, or changed. Carries the field geometry the
        /// popover anchors to.
        case formDetected(Form)
        /// The user focused a field Luna can fill.
        case fieldFocused(Form)
        /// Credentials went out on a submit — the §14.4 trigger.
        case submitted(username: String, password: String)
        /// The form or the field went away; take the popover down with it.
        case dismissed
    }

    /// A login form as the page describes it.
    public struct Form: Sendable, Equatable {
        /// Our own handle for the form, so a fill names the same element the
        /// detection did even after the page re-renders around it.
        public let id: String
        /// The focused/primary field's rect in view coordinates — CSS
        /// pixels from the top-left of the web view, already adjusted for
        /// scroll and for any scaling the page applied.
        public let fieldRect: CGRect
        /// Whether this looks like a signup rather than a sign-in, which is
        /// what decides between offering to fill and offering to generate
        /// (§14.5).
        public let isSignup: Bool
        /// The site's `passwordrules` attribute, verbatim, when it set one.
        public let passwordRules: String?
        /// Whether a `one-time-code` field is present (§14.6).
        public let hasOneTimeCode: Bool
        /// True when the field the user is in is the password field rather
        /// than the username field.
        public let isPasswordField: Bool
    }

    /// Decodes a `WKScriptMessage` body. Returns nil for anything malformed —
    /// the body comes from the page, so every field is untrusted input and a
    /// missing key is a page doing something odd, not a reason to crash.
    public static func event(from body: Any) -> Event? {
        guard let dict = body as? [String: Any], let kind = dict["kind"] as? String else { return nil }
        switch kind {
        case "dismissed":
            return .dismissed
        case "submitted":
            guard let password = dict["password"] as? String, !password.isEmpty else { return nil }
            return .submitted(username: dict["username"] as? String ?? "", password: password)
        case "detected", "focused":
            guard let form = form(from: dict) else { return nil }
            return kind == "detected" ? .formDetected(form) : .fieldFocused(form)
        default:
            return nil
        }
    }

    private static func form(from dict: [String: Any]) -> Form? {
        guard let id = dict["id"] as? String,
              let rect = dict["rect"] as? [String: Any],
              let x = rect["x"] as? Double, let y = rect["y"] as? Double,
              let width = rect["width"] as? Double, let height = rect["height"] as? Double
        else { return nil }
        return Form(
            id: id,
            fieldRect: CGRect(x: x, y: y, width: width, height: height),
            isSignup: dict["isSignup"] as? Bool ?? false,
            passwordRules: dict["passwordRules"] as? String,
            hasOneTimeCode: dict["hasOneTimeCode"] as? Bool ?? false,
            isPasswordField: dict["isPasswordField"] as? Bool ?? false
        )
    }

    // MARK: - Filling, from Swift

    /// Fills `form` with `username` / `password`.
    ///
    /// `callAsyncJavaScript`, not `evaluateJavaScript`, and that is a
    /// security requirement rather than a style preference. Arguments are
    /// marshalled by WebKit and bound as real JS values, so the password never
    /// appears inside a source string. Interpolating it would mean quoting it
    /// correctly for JS — a password is exactly the kind of string that breaks
    /// naive quoting — and would leave the secret in a script the page's own
    /// error handlers and any `Function.prototype.toString` hook could read.
    ///
    /// `in: frame` pins the fill to the frame that asked. §14.8 forbids filling
    /// an iframe whose origin does not match the page, and the caller checks
    /// that before reaching here; passing the frame makes it impossible for the
    /// fill to land anywhere else even so.
    ///
    /// `.defaultClient`, not the page world. The detection script runs in the
    /// page world because it has to see the page's DOM; the fill does not,
    /// since the handles it follows are `data-luna-*` attributes, which are DOM
    /// state and shared across worlds. In the client world the prototypes and
    /// built-ins it relies on are ones the page cannot have patched, so a page
    /// cannot hook `Object.getOwnPropertyDescriptor` or `Event` to observe the
    /// fill. Verified against a page installing React's own swallowing value
    /// setter: the fill lands and the page's `input`/`change` listeners still
    /// fire, because events cross worlds.
    @MainActor
    public static func fill(
        _ form: Form,
        username: String,
        password: String?,
        in webView: WKWebView,
        frame: WKFrameInfo?
    ) async {
        _ = try? await webView.callAsyncJavaScript(
            fillFunction,
            arguments: ["formID": form.id, "username": username, "password": password ?? ""],
            in: frame,
            contentWorld: .defaultClient
        )
    }

    /// The body of the fill, run with `formID`, `username` and `password` bound
    /// as arguments.
    ///
    /// The `input` and `change` events are not optional. React, Vue and
    /// every other framework that controls an input tracks its value in
    /// component state; setting `.value` directly updates the DOM node and
    /// leaves the framework's copy stale, so the form submits the empty string
    /// it still believes is there. Worse, React installs its own value setter
    /// on the element, so assigning through it is swallowed — hence the walk up
    /// the prototype chain to the native setter, which is the documented way
    /// to drive a controlled input from outside.
    private static let fillFunction = """
    var root = document.querySelector('[data-luna-form="' + formID + '"]') || document;
    var setValue = function (el, value) {
      if (!el) { return; }
      var proto = el instanceof HTMLTextAreaElement
        ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
      var setter = Object.getOwnPropertyDescriptor(proto, 'value');
      if (setter && setter.set) { setter.set.call(el, value); } else { el.value = value; }
      el.dispatchEvent(new Event('input', { bubbles: true }));
      el.dispatchEvent(new Event('change', { bubbles: true }));
    };
    var user = root.querySelector('[data-luna-field="username"]');
    var pass = root.querySelector('[data-luna-field="password"]');
    if (username) { setValue(user, username); }
    if (password) { setValue(pass, password); }
    return true;
    """

    // MARK: - The page script

    /// Injected at `documentEnd` in every frame.
    ///
    /// Every frame, because a login form in an iframe is the normal shape of a
    /// federated sign-in. The origin check that §14.8 demands is not made here
    /// — a script running in the frame cannot be trusted to report its own
    /// origin honestly — it is made in Swift against `WKScriptMessage.frameInfo`,
    /// which WebKit fills in and the page cannot touch.
    ///
    /// Why the DOM is re-scanned rather than watched once. Login forms
    /// arrive late: behind a "Sign in" button, inside a modal, after a
    /// client-side route change. A one-shot scan at `documentEnd` misses most
    /// real sites, so a `MutationObserver` re-scans — debounced, because a busy
    /// page mutates hundreds of times a second and this runs on the main
    /// thread of the WebContent process.
    public static let script = """
    (function () {
      'use strict';
      var handler = function () {
        return window.webkit && window.webkit.messageHandlers
          && window.webkit.messageHandlers.\(messageName);
      };
      if (!handler()) { return; }

      var counter = 0;
      var current = null;
      var lastSent = '';
      var lastSubmit = '';
      var lastSubmitAt = 0;

      var post = function (payload) {
        var h = handler();
        if (!h) { return; }
        var stamp = JSON.stringify(payload);
        if (payload.kind === 'submitted') {
          // A real `<button type="submit">` inside a `<form>` fires the click
          // handler *and* the form's own submit event, so one sign-in arrives
          // twice and the chip is built twice over itself.
          //
          // Content alone cannot settle it — someone who mistypes and retries
          // with the same password has to be offered the save again — so the
          // window is short rather than permanent. It is kept apart from
          // `lastSent` because a submit passing through that one would mask
          // the next detection of the very same form.
          var now = Date.now();
          if (stamp === lastSubmit && now - lastSubmitAt < 1500) { return; }
          lastSubmit = stamp;
          lastSubmitAt = now;
          h.postMessage(payload);
          return;
        }
        // Identical consecutive reports are the common case under the
        // observer; sending them would wake Swift and re-lay-out a popover to
        // put it exactly where it already is.
        if (stamp === lastSent) { return; }
        lastSent = stamp;
        h.postMessage(payload);
      };

      var visible = function (el) {
        if (!el || el.disabled || el.readOnly) { return false; }
        if (el.type === 'hidden') { return false; }
        var r = el.getBoundingClientRect();
        if (r.width < 8 || r.height < 8) { return false; }
        var s = window.getComputedStyle(el);
        return s.visibility !== 'hidden' && s.display !== 'none' && s.opacity !== '0';
      };

      // A username field is whatever sits closest *above* the password field.
      // Matching on name/id keywords alone fails on the many sites that call it
      // `login[identity]` or nothing at all; position is the more reliable
      // signal and the keywords only break ties.
      var findUsername = function (scope, passwordEl) {
        var candidates = [].slice.call(scope.querySelectorAll(
          'input[type="text"], input[type="email"], input[type="tel"], input:not([type])'
        )).filter(visible);
        if (!candidates.length) { return null; }
        var above = candidates.filter(function (el) {
          return el.compareDocumentPosition(passwordEl) & Node.DOCUMENT_POSITION_FOLLOWING;
        });
        var pool = above.length ? above : candidates;
        var keyed = pool.filter(function (el) {
          var hay = ((el.name || '') + ' ' + (el.id || '') + ' ' +
                     (el.getAttribute('autocomplete') || '') + ' ' +
                     (el.getAttribute('aria-label') || '')).toLowerCase();
          return /user|email|login|account|ident/.test(hay);
        });
        return (keyed.length ? keyed : pool)[keyed.length ? keyed.length - 1 : pool.length - 1];
      };

      // Two visible password fields, or an autocomplete of `new-password`, is
      // a signup or a change-password form — the §14.5 case, where offering a
      // saved credential is wrong and offering to generate one is right.
      var looksLikeSignup = function (scope, passwords) {
        if (passwords.length > 1) { return true; }
        var auto = (passwords[0].getAttribute('autocomplete') || '').toLowerCase();
        if (auto.indexOf('new-password') >= 0) { return true; }
        var hay = (scope.action || '') + ' ' + (scope.id || '') + ' ' + (scope.className || '');
        return /signup|sign-up|register|join|create/i.test(hay);
      };

      var scan = function (focused) {
        var passwords = [].slice.call(document.querySelectorAll('input[type="password"]')).filter(visible);
        if (!passwords.length) {
          if (current) { current = null; lastSent = ''; post({ kind: 'dismissed' }); }
          return;
        }
        var passwordEl = passwords[0];
        var scope = passwordEl.form || passwordEl.closest('form') || document.body;

        // **Re-count inside the form, not across the document.** `passwords`
        // above is document-wide, which is right for "is there a login form
        // here at all" and badly wrong for "is this a signup". A page holding
        // a sign-in form *and* a change-password widget elsewhere — common on
        // an account page, and on any site with a hidden modal — would make
        // every form on it look like a signup, so Luna would offer to
        // generate a new password instead of filling the saved one.
        var scoped = [].slice.call(scope.querySelectorAll('input[type="password"]')).filter(visible);
        if (!scoped.length) { scoped = [passwordEl]; }

        if (!scope.getAttribute || !scope.getAttribute('data-luna-form')) {
          counter += 1;
          var id = 'luna-' + counter + '-' + Date.now();
          if (scope.setAttribute) { scope.setAttribute('data-luna-form', id); }
          current = id;
        } else {
          current = scope.getAttribute('data-luna-form');
        }

        var userEl = findUsername(scope, passwordEl);
        if (userEl) { userEl.setAttribute('data-luna-field', 'username'); }
        passwordEl.setAttribute('data-luna-field', 'password');

        var otp = scope.querySelector && scope.querySelector(
          'input[autocomplete~="one-time-code"], input[name*="otp" i], input[name*="code" i]');

        // The rect of whichever field the popover should point at: the one the
        // user is in, or the username field when nobody is focused yet.
        var anchorEl = (focused && (focused === userEl || focused === passwordEl))
          ? focused : (userEl || passwordEl);
        var r = anchorEl.getBoundingClientRect();

        post({
          kind: focused ? 'focused' : 'detected',
          id: current,
          rect: { x: r.left, y: r.top, width: r.width, height: r.height },
          isSignup: looksLikeSignup(scope, scoped),
          passwordRules: passwordEl.getAttribute('passwordrules'),
          hasOneTimeCode: !!otp,
          isPasswordField: anchorEl === passwordEl
        });
      };

      // §14.4's trigger. Read at submit time — *before* the navigation — because
      // afterwards the fields are gone. Nothing is persisted from this: it
      // reaches Swift, which shows a chip, and only the user pressing Save
      // writes anything (§14.8).
      var reportSubmit = function (scope) {
        if (!scope || !scope.querySelector) { return; }
        var pass = scope.querySelector('[data-luna-field="password"]')
          || scope.querySelector('input[type="password"]');
        if (!pass || !pass.value) { return; }
        // **The username needs the same fallback the password has.** The tag is
        // only there if this form was scanned, and the form that is submitted
        // is often not the one that was: the scan follows the *first* password
        // field in the document, so a page with two forms leaves the second
        // untagged until it is focused. A button-with-a-handler login — the
        // ordinary SPA shape — can therefore submit having never been scanned.
        // Without this, that saves a credential with an empty username: one
        // the user cannot tell apart in the picker, and one that will not
        // match what they type next time.
        var user = scope.querySelector('[data-luna-field="username"]') || findUsername(scope, pass);
        post({ kind: 'submitted', username: user ? user.value : '', password: pass.value });
      };

      document.addEventListener('submit', function (e) { reportSubmit(e.target); }, true);

      // Most real login forms never fire `submit`: the button is a `<button>`
      // with a click handler that calls `fetch`. A click on anything that looks
      // like a submit inside a form with a filled password is the pragmatic
      // second trigger.
      document.addEventListener('click', function (e) {
        var el = e.target;
        if (!el || !el.closest) { return; }
        var button = el.closest('button, input[type="submit"], [role="button"]');
        if (!button) { return; }
        var scope = button.closest('form') || document.querySelector('[data-luna-form]');
        if (scope) { setTimeout(function () { reportSubmit(scope); }, 0); }
      }, true);

      document.addEventListener('focusin', function (e) {
        var el = e.target;
        if (!el || !el.tagName || el.tagName !== 'INPUT') { return; }
        if (el.type === 'password' || el.getAttribute('data-luna-field') === 'username') {
          scan(el);
        }
      }, true);

      document.addEventListener('focusout', function (e) {
        var el = e.target;
        if (el && el.getAttribute && el.getAttribute('data-luna-field')) {
          lastSent = '';
          post({ kind: 'dismissed' });
        }
      }, true);

      // The anchor moves when the page scrolls, so the popover has to be told.
      // Passive, and coalesced to one report per frame: this fires continuously
      // during a flick scroll.
      var ticking = false;
      var onScroll = function () {
        if (ticking || !current) { return; }
        ticking = true;
        window.requestAnimationFrame(function () { ticking = false; lastSent = ''; scan(null); });
      };
      window.addEventListener('scroll', onScroll, { passive: true, capture: true });
      window.addEventListener('resize', onScroll, { passive: true });

      var pending = null;
      var observer = new MutationObserver(function () {
        if (pending) { return; }
        pending = setTimeout(function () { pending = null; scan(null); }, 250);
      });
      observer.observe(document.documentElement, { childList: true, subtree: true });
      scan(null);
    })();
    """
}
