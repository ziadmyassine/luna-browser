//
//  CredentialOwnershipTests.swift
//  LunaTests
//
//  Luna must only ever see items Luna wrote.
//
//  Not scoped by `kSecAttrService`: it is an attribute of
//  `kSecClassGenericPassword`, silently ignored on an internet password, so a
//  query filtered by it matches on host alone — and offered a `github.com`
//  token written by `git-credential-osxkeychain`. With that query a fill types
//  another app's token into a login form, `save` can rewrite another app's
//  item, and `delete` ("never for this site") can destroy one.
//
//  The tests write a deliberately foreign item — no creator code, as another
//  application's would look — under an RFC 2606 `.invalid` host, and assert
//  Luna cannot see it.
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

    /// Saving under the same host must create Luna's own row rather than
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
