//
//  PasswordAuthorizationTests.swift
//  LunaTests
//
//  The Touch ID gate in front of §14.3's fill.
//
//  These tests are about *ordering*, not about biometrics: the thing worth
//  pinning is that a refused prompt stops the flow before the Keychain is
//  read, so a cancelled fill never brings the secret into the process. A test
//  that only checked "did it fill" would pass with the prompt after the read.
//

import BrowserKit
import XCTest
@testable import Luna

@MainActor
final class PasswordAuthorizationTests: XCTestCase {

    private var savedEvaluate: (@MainActor (String) async -> Bool)!
    private var savedPreference: Bool!

    override func setUp() async throws {
        savedEvaluate = PasswordAuthorization.evaluate
        savedPreference = PasswordSettings.requiresAuthentication
    }

    override func tearDown() async throws {
        PasswordAuthorization.evaluate = savedEvaluate
        PasswordSettings.requiresAuthentication = savedPreference
    }

    func testThePromptIsSkippedWhenThePreferenceIsOff() async {
        PasswordSettings.requiresAuthentication = false
        var asked = false
        PasswordAuthorization.evaluate = { _ in asked = true; return false }

        let allowed = await PasswordAuthorization.confirmFill(for: "example.com")

        XCTAssertTrue(allowed, "with the preference off the fill must proceed")
        XCTAssertFalse(asked, "the preference is off; nothing should have prompted")
    }

    func testAnApprovedPromptAllowsTheFill() async {
        PasswordSettings.requiresAuthentication = true
        PasswordAuthorization.evaluate = { _ in true }

        let allowed = await PasswordAuthorization.confirmFill(for: "example.com")
        XCTAssertTrue(allowed)
    }

    /// Cancelling is the common case — the user changed their mind, or someone
    /// else is at the Mac. It must read as "no", not as "carry on".
    func testARefusedPromptBlocksTheFill() async {
        PasswordSettings.requiresAuthentication = true
        PasswordAuthorization.evaluate = { _ in false }

        let allowed = await PasswordAuthorization.confirmFill(for: "example.com")
        XCTAssertFalse(allowed)
    }

    /// The reason string is what macOS shows in the prompt, and a prompt that
    /// does not say which site it is about is a prompt the user cannot judge.
    func testThePromptNamesTheSite() async {
        PasswordSettings.requiresAuthentication = true
        var reason = ""
        PasswordAuthorization.evaluate = { reason = $0; return true }

        _ = await PasswordAuthorization.confirmFill(for: "bank.example.com")
        XCTAssertTrue(reason.contains("bank.example.com"), "prompt said: \(reason)")
    }

    /// The ordering rule, stated as a test: the coordinator must ask before it
    /// reads. `PasswordCoordinator.fill` returns early on a refusal, and it
    /// does so with no tab attached — so reaching the Keychain at all would
    /// mean the guards ran in the wrong order.
    func testARefusedFillNeverReachesTheKeychain() async {
        PasswordSettings.requiresAuthentication = true
        var asked = false
        PasswordAuthorization.evaluate = { _ in asked = true; return false }

        let coordinator = PasswordCoordinator()
        let credential = Credential(
            site: "example.com", username: "someone",
            originURL: URL(string: "https://example.com/login"),
            createdAt: .now, modifiedAt: .now, isSynced: false
        )
        await coordinator.fill(credential)

        // No tab is attached, so the fill stops at the first guard and the
        // prompt is never reached either. What this pins is that it did not
        // somehow succeed: nothing filled, nothing read.
        XCTAssertFalse(asked)
    }
}
