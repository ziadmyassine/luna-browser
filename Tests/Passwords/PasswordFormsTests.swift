//
//  PasswordFormsTests.swift
//  LunaTests
//
//  The page→Swift boundary (§14.3) and §14.10's passkey suppression.
//
//  Everything decoded here arrives from web content, so these are tests about
//  **untrusted input**: the question is never "does a well-formed message
//  work", it is "does a malformed one fail safely".
//

import WebKit
import XCTest
import BrowserKit
@testable import Luna

final class PasswordFormsTests: XCTestCase {

    // MARK: - Decoding

    private func detected(_ overrides: [String: Any] = [:]) -> [String: Any] {
        var body: [String: Any] = [
            "kind": "detected",
            "id": "luna-1",
            "rect": ["x": 10.0, "y": 20.0, "width": 200.0, "height": 30.0]
        ]
        for (key, value) in overrides { body[key] = value }
        return body
    }

    func testDecodesADetectedForm() {
        guard case let .formDetected(form)? = PasswordForms.event(from: detected([
            "isSignup": true, "passwordRules": "minlength: 8;", "hasOneTimeCode": true
        ])) else { return XCTFail("expected a detected form") }

        XCTAssertEqual(form.id, "luna-1")
        XCTAssertEqual(form.fieldRect, CGRect(x: 10, y: 20, width: 200, height: 30))
        XCTAssertTrue(form.isSignup)
        XCTAssertEqual(form.passwordRules, "minlength: 8;")
        XCTAssertTrue(form.hasOneTimeCode)
    }

    func testDecodesASubmit() {
        guard case let .submitted(username, password)? = PasswordForms.event(from: [
            "kind": "submitted", "username": "ada", "password": "s3cret"
        ]) else { return XCTFail("expected a submit") }
        XCTAssertEqual(username, "ada")
        XCTAssertEqual(password, "s3cret")
    }

    /// A submit with no password is not a sign-in, and offering to save an
    /// empty string would overwrite a good credential with nothing.
    func testSubmitWithoutAPasswordIsRejected() {
        XCTAssertNil(PasswordForms.event(from: ["kind": "submitted", "username": "ada"]))
        XCTAssertNil(PasswordForms.event(from: ["kind": "submitted", "password": ""]))
    }

    /// A username is genuinely optional — plenty of sites have only a PIN.
    func testSubmitWithoutAUsernameIsStillASubmit() {
        guard case let .submitted(username, _)? = PasswordForms.event(from: [
            "kind": "submitted", "password": "1234"
        ]) else { return XCTFail("expected a submit") }
        XCTAssertEqual(username, "")
    }

    func testMalformedBodiesAreRejectedRatherThanGuessed() {
        XCTAssertNil(PasswordForms.event(from: "not a dictionary"))
        XCTAssertNil(PasswordForms.event(from: [:]))
        XCTAssertNil(PasswordForms.event(from: ["kind": "nonsense"]))
        XCTAssertNil(PasswordForms.event(from: ["kind": "detected"]))
        // A rect missing a component cannot be positioned against.
        XCTAssertNil(PasswordForms.event(from: [
            "kind": "detected", "id": "x", "rect": ["x": 1.0, "y": 2.0]
        ]))
        // A form with no id cannot be filled: the fill names it by id.
        XCTAssertNil(PasswordForms.event(from: [
            "kind": "detected", "rect": ["x": 1.0, "y": 2.0, "width": 3.0, "height": 4.0]
        ]))
    }

    func testDismissNeedsNothingElse() {
        guard case .dismissed? = PasswordForms.event(from: ["kind": "dismissed"]) else {
            return XCTFail("expected a dismissal")
        }
    }

    // MARK: - The injected script

    /// The script talks to the handler `TabController` registers. If the two
    /// names drift apart the feature silently stops working — no crash, no
    /// error, just a browser that never offers to fill anything.
    func testScriptPostsToTheRegisteredHandlerName() {
        XCTAssertTrue(PasswordForms.script.contains("messageHandlers.\(PasswordForms.messageName)"))
    }

    /// §14.3: the picker is native. A script that built its own DOM list would
    /// be a page-readable list of the user's usernames.
    func testScriptNeverBuildsAnOverlay() {
        for forbidden in ["createElement", "innerHTML", "appendChild", "attachShadow"] {
            XCTAssertFalse(
                PasswordForms.script.contains(forbidden),
                "§14.3 forbids an injected overlay; the script uses \(forbidden)"
            )
        }
    }

    // MARK: - §14.10

    func testSuppressionScriptRemovesTheInterface() {
        let source = PasskeySupport.suppressionScript
        XCTAssertTrue(source.contains("delete window.PublicKeyCredential"))
        // A site that skipped feature detection must get the error the spec
        // defines, not a hang.
        XCTAssertTrue(source.contains("NotSupportedError"))
        // Non-passkey credential requests must still work.
        XCTAssertTrue(source.contains("options.publicKey"))
    }

    /// Ad-hoc signing carries no entitlements, so this build cannot do
    /// WebAuthn and must be suppressing it. The assertion is written as an
    /// equivalence rather than a constant so it stays true — and meaningful —
    /// on the day a signed build carries the entitlement.
    @MainActor
    func testPasskeyScriptIsInjectedExactlyWhenTheEntitlementIsMissing() {
        XCTAssertEqual(PasskeySupport.userScript() == nil, PasskeySupport.isAvailable)
    }

    func testEntitlementNameIsTheOneAppleDocuments() {
        XCTAssertEqual(PasskeySupport.entitlement, "com.apple.developer.web-browser.public-key-credential")
    }
}
