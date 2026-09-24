//
//  CredentialPopoverTests.swift
//  LunaTests
//
//  §14.3's picker, as a view.
//
//  Safari's password panel shows the site's mark, the account, the site under
//  it, and a fingerprint saying what the click will cost. Luna cannot use
//  Safari's panel — `docs/PASSWORDS.md` §3 explains why, and it is a platform
//  limit rather than a gap — so it draws its own, and these are the parts of
//  that drawing worth keeping.
//
//  They are assertions about structure, not pixels: a snapshot test over
//  glass would fail on every macOS material tweak and teach nobody anything.
//

import AppKit
import WebKit
import XCTest
@testable import BrowserKit
@testable import Luna

@MainActor
final class CredentialPopoverTests: XCTestCase {

    private var savedPreference: Bool!

    override func setUp() async throws {
        savedPreference = PasswordSettings.requiresAuthentication
    }

    override func tearDown() async throws {
        PasswordSettings.requiresAuthentication = savedPreference
    }

    // MARK: - Helpers

    private func offer(
        usernames: [String] = ["hrmerdi@gmail.com"],
        site: String = "github.com",
        insecure: Bool = false,
        redirect: Bool = false
    ) -> PasswordOffer {
        PasswordOffer(
            credentials: usernames.map {
                Credential(site: site, username: $0,
                           originURL: URL(string: "https://\(site)/login"),
                           createdAt: .now, modifiedAt: .now, isSynced: false)
            },
            fieldRect: .zero, site: site, viaRedirect: redirect, isInsecure: insecure
        )
    }

    private func laidOut(_ content: CredentialPopover.Content) -> CredentialPopoverView {
        let view = CredentialPopoverView(content: content, onPick: { _ in }, onAcceptGenerated: { _ in })
        view.frame = NSRect(x: 0, y: 0, width: Tokens.Metric.passwordPopover.width, height: 400)
        view.layoutSubtreeIfNeeded()
        return view
    }

    private func labels(in view: NSView) -> [String] {
        var found: [String] = []
        for sub in view.subviews {
            if let field = sub as? NSTextField { found.append(field.stringValue) }
            found += labels(in: sub)
        }
        return found
    }

    private func hasIdentifier(_ id: String, in view: NSView) -> Bool {
        for sub in view.subviews {
            if sub.accessibilityIdentifier() == id { return true }
            if hasIdentifier(id, in: sub) { return true }
        }
        return false
    }

    // MARK: - The row

    /// The username and the site, on two lines. One saved account can be the
    /// right one on `github.com` and the wrong one on a page that merely looks
    /// like it, so the row says which site it is filing under.
    func testARowNamesBothTheAccountAndTheSite() {
        let view = laidOut(.saved(offer(usernames: ["hrmerdi@gmail.com"])))
        let text = labels(in: view)
        XCTAssertTrue(text.contains("hrmerdi@gmail.com"), "no username in \(text)")
        XCTAssertEqual(text.filter { $0 == "github.com" }.count, 2,
                       "expected the site in the header and under the username: \(text)")
    }

    /// A credential with no username is real — plenty of sites have only a
    /// password — and must still draw a row the pointer can find.
    func testARowWithNoUsernameStillHasAName() {
        let view = laidOut(.saved(offer(usernames: [""])))
        XCTAssertFalse(labels(in: view).contains(""), "an empty row is an unclickable row")
    }

    // MARK: - The fingerprint

    func testTheFingerprintIsDrawnWhenAuthenticationIsRequired() {
        PasswordSettings.requiresAuthentication = true
        let view = laidOut(.saved(offer()))
        XCTAssertTrue(hasIdentifier("password-row-biometric", in: view))
    }

    /// Absent, not dimmed. A symbol that no longer means anything is worse
    /// than no symbol — it says a prompt is coming that will not come.
    func testTheFingerprintIsAbsentWhenAuthenticationIsOff() {
        PasswordSettings.requiresAuthentication = false
        let view = laidOut(.saved(offer()))
        XCTAssertFalse(hasIdentifier("password-row-biometric", in: view))
    }

    // MARK: - The way out

    func testASavedOfferOffersAWayToAllPasswords() {
        let view = laidOut(.saved(offer()))
        XCTAssertTrue(labels(in: view).contains { $0.contains("All saved passwords") },
                      "the picker has no exit: \(labels(in: view))")
    }

    /// The generated-password picker is a single suggestion to accept or
    /// ignore. A list of saved logins is not what that moment is about.
    func testTheGeneratedSuggestionHasNoSavedPasswordsRow() {
        let suggestion = PasswordSuggestion(generated: "abcd-efgh-ijkl", fieldRect: .zero, site: "github.com")
        let view = laidOut(.generated(suggestion))
        XCTAssertFalse(labels(in: view).contains { $0.contains("All saved passwords") })
    }

    // MARK: - §14.8's cautions survived the redesign

    func testAnInsecurePageStillSaysSo() {
        let view = laidOut(.saved(offer(insecure: true)))
        XCTAssertTrue(labels(in: view).contains { $0.contains("not encrypted") },
                      "§14.8's insecure-origin warning went missing")
    }

    func testARedirectedPageStillSaysSo() {
        let view = laidOut(.saved(offer(redirect: true)))
        XCTAssertTrue(labels(in: view).contains { $0.contains("redirected") },
                      "§14.8's redirect warning went missing")
    }

    /// The page measures a field from its own viewport, which starts under
    /// §3.2b's bar when the bar covers the top of the web view. The picker has
    /// to add that back or it points above the field.
    func testThePickerPointsBelowWhateverCoversThePage() {
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        let field = CGRect(x: 100, y: 40, width: 200, height: 30)
        XCTAssertEqual(CredentialPopover.viewRect(for: field, in: web), CGRect(x: 100, y: 530, width: 200, height: 30))
        web.obscuredContentInsets = NSEdgeInsets(top: 52, left: 0, bottom: 0, right: 0)
        XCTAssertEqual(CredentialPopover.viewRect(for: field, in: web), CGRect(x: 100, y: 478, width: 200, height: 30))
    }
}
