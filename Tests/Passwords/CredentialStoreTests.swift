//
//  CredentialStoreTests.swift
//  LunaTests
//
//  §14.2's bridge.
//
//  These tests deliberately do not write real credentials. A test suite
//  that adds and removes `kSecClassInternetPassword` items runs against the
//  developer's actual login keychain — the same one their real passwords are
//  in — and a bug in the cleanup path is then a bug that deletes someone's
//  data. What is worth testing here is the matching and the refusal paths,
//  both of which are reachable without touching the Keychain at all.
//
//  The one thing that genuinely needs a live Keychain is the capability probe,
//  and §14.1's spike covers that with a throwaway binary (`docs/PASSWORDS.md`).
//

import XCTest
import BrowserKit
@testable import Luna

final class CredentialStoreTests: XCTestCase {

    // MARK: - Lookups that never reach the Keychain

    /// A host with no registrable domain has no site to own a password, so the
    /// lookup short-circuits before any query is made.
    func testHostsWithoutASiteKeyReturnNothing() async {
        let store = CredentialStore.shared
        for host in ["localhost", "192.168.1.1", "", "[::1]"] {
            let found = await store.credentials(forHost: host)
            XCTAssertTrue(found.isEmpty, "\(host) should have no credentials")
        }
        let none = await store.credentials(forHost: nil)
        XCTAssertTrue(none.isEmpty)
    }

    // MARK: - The model

    /// `Credential` is the type that gets passed around the app, so the
    /// invariant worth pinning is that it does not carry a password at all.
    /// If a `password` property is ever added, this stops compiling — which is
    /// the point.
    func testCredentialCarriesNoSecret() {
        let credential = Credential(site: "example.com", username: "ada")
        XCTAssertEqual(credential.site, "example.com")
        XCTAssertEqual(credential.username, "ada")
        XCTAssertEqual(credential.id, "example.com\u{0}ada")
    }

    /// Two accounts on one site are two credentials; the same account twice is
    /// one. The picker de-duplicates on this.
    func testIdentityIsSitePlusUsername() {
        let a = Credential(site: "example.com", username: "ada")
        let b = Credential(site: "example.com", username: "grace")
        let c = Credential(site: "other.com", username: "ada")
        XCTAssertNotEqual(a.id, b.id)
        XCTAssertNotEqual(a.id, c.id)
    }

    // MARK: - What the settings pane says

    /// The storage line is the only place the §14.1 result is visible to a
    /// user, so each state has to say something different and true.
    @MainActor
    func testEveryCapabilityDescribesItselfDistinctly() {
        let lines = [
            PasswordsSection.describe(.synced),
            PasswordsSection.describe(.local),
            PasswordsSection.describe(.unavailable(-25300))
        ]
        XCTAssertEqual(Set(lines).count, 3, "two capabilities must not read the same")
        XCTAssertTrue(lines[0].contains("iCloud"))
        XCTAssertTrue(lines[1].contains("This Mac only"))
        XCTAssertTrue(lines[2].contains("25300"))
    }

    /// `.unknown` must not claim iCloud. Nothing has been written, so the
    /// honest reading is the conservative one.
    @MainActor
    func testUnknownCapabilityDoesNotPromiseSync() {
        XCTAssertFalse(PasswordsSection.describe(.unknown).contains("iCloud"))
    }

    // MARK: - §14.4's per-site refusal

    /// Offering is the default; only the chip's "Never for this site" ever
    /// writes a `false`. A default of `false` would mean Luna never offered to
    /// save anything until the user found a setting they had no reason to look
    /// for.
    func testSavePasswordsDefaultsToOffering() {
        XCTAssertTrue(BrowserStore.SitePermission.savePasswords.defaultsToAllowed)
    }

    /// The raw value is the SQLite column name, so renaming the case
    /// silently orphans every answer already stored.
    func testPermissionColumnNameIsStable() {
        XCTAssertEqual(BrowserStore.SitePermission.savePasswords.rawValue, "savePasswords")
    }
}
