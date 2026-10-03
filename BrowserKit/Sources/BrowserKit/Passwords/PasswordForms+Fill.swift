import Foundation
import WebKit

/// Filling a form the page reported, from Swift. Apart from the detection
/// script for `PasswordForms.swift`'s length limit.
extension PasswordForms {

    // MARK: - Filling, from Swift

    /// Fills `form` with `username` / `password`.
    ///
    /// `callAsyncJavaScript`, not `evaluateJavaScript`, as a security
    /// requirement: arguments are bound by WebKit as real JS values, so the
    /// password never appears in a source string, where it would need quoting
    /// a password is likely to break and could be read by the page's error
    /// handlers or a `Function.prototype.toString` hook.
    ///
    /// `in: frame` pins the fill to the frame that asked. The caller has
    /// already applied §14.8's origin check; this makes it impossible for the
    /// fill to land anywhere else even so.
    ///
    /// `.defaultClient`, not the page world: the handles the fill follows are
    /// `data-luna-*` attributes, which are shared across worlds, and in the
    /// client world the page cannot have patched `Object.getOwnPropertyDescriptor`
    /// or `Event` to observe the fill. Verified against a page installing
    /// React's swallowing value setter: the fill lands and the page's
    /// `input`/`change` listeners still fire, because events cross worlds.
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
}
