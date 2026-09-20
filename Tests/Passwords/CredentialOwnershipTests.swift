//
//  CredentialOwnershipTests.swift
//  LunaTests
//
//  **Luna must only ever see items Luna wrote.**
//
//  This is not a hypothetical. `CredentialStore` first scoped its queries with
//  `kSecAttrService`, which is an attribute of `kSecClassGenericPassword` and
//  is silently ignored on an *internet* password — so the filter did nothing
//  and `baseQuery` matched on the host alone. On the machine this was found,
//  Luna's picker was offering a `github.com` credential written by
//  `git-credential-osxkeychain` a year before the feature existed, whose
//  secret is a personal access token rather than a password.
//
//  Three things followed from that one mistake, and all three are what these
//  tests exist to stop coming back:
//
//  · a fill would have typed another app's token into a login form;
//  · `save` reuses the query, so an update could rewrite another app's item;
//  · `delete` reuses it too, so "never for this site" could destroy one.
//
//  The tests write a deliberately foreign item — no creator code, exactly as
//  another application's would look — under an RFC 2606 `.invalid` host, and
//  assert Luna cannot see it.
//

import Security
import XCTest
@testable import BrowserKit
@testable import Luna

final class CredentialOwnershipTests: XCTestCase {

    /// Reserved by RFC 2606, so it can never collide with a real site or with
    /// anything the developer running these tests actually has saved.
    private let host = "ownership-test.luna.invalid"

    private var foreignItem: [String: Any] {
        [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: host,
            kSecAttrAccount as String: "someone-elses-account"
        ]
    }

    override func setUp() {
        super.setUp()
        SecItemDelete(foreignItem as CFDictionary)
    }

    override func tearDown() {
        SecItemDelete(foreignItem as CFDictionary)
        super.tearDown()
    }

    /// Writes an item the way another application would: no creator code.
    @discardableResult
    private func addForeignItem() -> OSStatus {
        var item = foreignItem
        item[kSecValueData as String] = Data("ghp_a_personal_access_token".utf8)
        return SecItemAdd(item as CFDictionary, nil)
    }

    private func foreignItemStillExists() -> Bool {
        var query = foreignItem
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    // MARK: - Reading

    func testAnotherApplicationsCredentialIsNotOffered() async throws {
        XCTAssertEqual(addForeignItem(), errSecSuccess, "could not stage the test item")

        let found = await CredentialStore.shared.credentials(forSite: host)

        XCTAssertTrue(found.isEmpty,
                      "Luna offered an item it did not write: \(found.map(\.username))")
    }

    // MARK: - Writing

    /// Saving under the same host must create Luna's *own* row rather than
    /// overwriting the one already there.
    func testSavingDoesNotOverwriteAnotherApplicationsCredential() async throws {
        XCTAssertEqual(addForeignItem(), errSecSuccess)

        let saved = await CredentialStore.shared.save(
            NewCredential(site: host, username: "someone-elses-account",
                          password: "luna-wrote-this", originURL: nil)
        )
        XCTAssertTrue(saved, "Luna's own save failed, so this proves nothing")

        XCTAssertTrue(foreignItemStillExists(), "Luna overwrote another application's keychain item")

        // And Luna sees exactly one credential: its own.
        let mine = await CredentialStore.shared.credentials(forSite: host)
        XCTAssertEqual(mine.count, 1)
        for credential in mine { _ = await CredentialStore.shared.delete(credential) }
    }

    /// The worst case. "Never for this site" and a delete from Settings both
    /// reach `delete`, and a delete that is not scoped to Luna's own items is
    /// data loss in somebody else's application.
    func testDeletingLunasCredentialLeavesAnotherApplicationsAlone() async throws {
        XCTAssertEqual(addForeignItem(), errSecSuccess)

        _ = await CredentialStore.shared.save(
            NewCredential(site: host, username: "someone-elses-account",
                          password: "luna-wrote-this", originURL: nil)
        )
        for credential in await CredentialStore.shared.credentials(forSite: host) {
            _ = await CredentialStore.shared.delete(credential)
        }

        XCTAssertTrue(foreignItemStillExists(), "Luna deleted another application's keychain item")
    }
}
