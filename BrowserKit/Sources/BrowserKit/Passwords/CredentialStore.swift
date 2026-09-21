import Foundation
import Security

/// Luna's bridge into Apple's password store (§14.2). Luna has no vault of
/// its own, no master password and nothing to breach: every credential here is
/// a `kSecClassInternetPassword` item in the user's Keychain, and the ones that
/// can be are `kSecAttrSynchronizable` so they land in iCloud Keychain, appear
/// in the Passwords app and reach the user's iPhone through Apple rather
/// than through anything we built.
///
/// # What §14.1's spike actually found
///
/// Measured on macOS 26 with an ad-hoc signature — the signature `project.yml`
/// gives Luna today (`CODE_SIGN_IDENTITY: "-"`). See `docs/PASSWORDS.md` for
/// the full write-up and the probe.
///
/// | Operation | Result |
/// |---|---|
/// | `SecItemAdd` with `kSecAttrSynchronizable: true` | `-34018` errSecMissingEntitlement |
/// | `SecItemAdd` with `kSecUseDataProtectionKeychain: true` | `-34018` |
/// | `SecItemAdd` / `CopyMatching` / `Update` / `Delete`, local item | `errSecSuccess` |
///
/// So the iCloud half of §14.2 is gated on a real signing identity, not on
/// code: synchronizable items require the `com.apple.application-identifier`
/// entitlement, which comes from a provisioning profile, which requires the
/// Developer ID work that is M4 (§24.4). The local half works today.
///
/// This class is written so that nothing changes when the signature does.
/// Every write tries synchronizable first and falls back to local on `-34018`,
/// latching the answer in ``capability``. The day Luna is signed for real, the
/// first write succeeds as synchronizable and the same code starts populating
/// the Passwords app — no migration, no rewrite, no second code path to test.
/// ``migrateLocalItemsToSynced()`` is what carries the items already written.
///
/// # What is not reachable, at any signature
///
/// Items created by Safari and the Passwords app live in Apple's own
/// keychain access groups. Luna is not in those groups and cannot join them:
/// `keychain-access-groups` only grants groups prefixed by your own team ID.
/// So Luna can put passwords into the Passwords app but can never read the
/// ones already there. §14.1 asked whether the user sees an ACL prompt or a
/// hard denial — the answer is neither: the items are simply not in Luna's
/// search domain, so the query returns `errSecItemNotFound` and there is
/// nothing to prompt about. The honest UI consequence is in `PasswordsSection`,
/// and it is the reason Luna does not claim to "use your existing passwords".
public actor CredentialStore {

    public static let shared = CredentialStore()

    /// Which half of §14.2 is actually available, latched from the first write.
    public enum Capability: Sendable, Equatable {
        /// Not probed yet. Nothing has been written, so nothing is known —
        /// distinct from `.local`, which is a measured refusal.
        case unknown
        /// Synchronizable writes succeed: items reach iCloud Keychain and the
        /// Passwords app. This is §14.2 as written.
        case synced
        /// `-34018`. Items are saved locally on this Mac only. Everything works
        /// except sync, and the UI has to say so rather than implying an
        /// iPhone will see them.
        case local
        /// The Keychain refused for a reason that is not the entitlement —
        /// a locked keychain, a damaged one. Carries the raw `OSStatus`
        /// because the settings pane shows it: a number the user can search
        /// beats "something went wrong".
        case unavailable(OSStatus)
    }

    public private(set) var capability: Capability = .unknown

    /// Shown in Keychain Access beside the item, so it names the product and
    /// the site rather than a bundle identifier.
    private static let label = "Luna"

    /// What marks an item as Luna's own.
    ///
    /// `kSecAttrCreator` and not `kSecAttrService`, which is what this used
    /// first and is a real bug rather than a style choice: `kSecAttrService`
    /// is an attribute of `kSecClassGenericPassword`, and on an internet
    /// password the Keychain silently ignores it — in a query and in an
    /// add. Measured: the same query with `service: "Luna"` and with a random
    /// impossible service name returned the identical row, and items Luna
    /// wrote came back with no service attribute at all.
    ///
    /// So the filter was inert, and `baseQuery` matched on `kSecAttrServer`
    /// alone — every internet password for that host in the user's keychain,
    /// whoever wrote it. On this Mac that meant Luna's picker offering a
    /// `github.com` item created in 2025, a year before this feature existed;
    /// by the account name, `git-credential-osxkeychain`'s, whose "password"
    /// is a personal access token. Filling it would have typed a token into a
    /// login form, and `save`/`delete` share the same query, so an update or a
    /// "never for this site" could have rewritten or destroyed another app's
    /// credential.
    ///
    /// `kSecAttrCreator` is a four-character code valid on both classes and is
    /// honoured: verified by adding one item and querying with a different
    /// creator, which returns nothing. `'Luna'`.
    private static let creator = FourCharCode(0x4C75_6E61)

    /// The other half of the same fix, and the half that makes saving work.
    ///
    /// `kSecAttrCreator` scopes a query but is not part of the Keychain's
    /// uniqueness constraint, which for an internet password is (server,
    /// account, protocol, port, path, securityDomain, authenticationType).
    /// So with the creator alone, Luna could read its own items but could not
    /// add one for a (host, account) another application already held —
    /// `SecItemAdd` returned `errSecDuplicateItem` and the save silently
    /// failed. Exactly the case that matters: the user's own GitHub account,
    /// already in the keychain from `git`.
    ///
    /// `kSecAttrSecurityDomain` is part of that key and is honoured in
    /// queries, so it does both jobs at once. Measured: two items with the
    /// same server and account coexist when their security domains differ, a
    /// scoped query returns only Luna's, and a scoped delete leaves the other
    /// one untouched.
    private static let securityDomain = "luna"

    private init() {}

    // MARK: - Reading

    /// Every credential saved for `site`, newest first. Passwords are not
    /// fetched — see ``password(for:)``.
    ///
    /// Queries both synchronizable and local items in one pass
    /// (`kSecAttrSynchronizableAny`), so a user who was on a local-only build
    /// before their Mac was signed still sees everything they saved.
    public func credentials(forSite site: String) -> [Credential] {
        var query = baseQuery(site: site)
        query[kSecMatchLimit as String] = kSecMatchLimitAll
        query[kSecReturnAttributes as String] = true

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let rows = result as? [[String: Any]] else { return [] }
        return rows.compactMap(Self.credential(from:)).sorted { $0.modifiedAt > $1.modifiedAt }
    }

    /// Credentials whose site matches `host`'s eTLD+1 — the only lookup the
    /// fill flow is allowed to make (§14.3, §14.8).
    ///
    /// Returns empty for a host with no registrable domain (an IP address,
    /// `localhost`), because there is no site there to be the owner of a
    /// password.
    public func credentials(forHost host: String?) -> [Credential] {
        guard let site = PublicSuffix.siteKey(forHost: host) else { return [] }
        return credentials(forSite: site)
    }

    /// The secret, fetched at the moment of use and never cached.
    ///
    /// Returns nil rather than throwing on every failure path: a caller that
    /// could distinguish "no such item" from "keychain locked" would have
    /// nothing different to do, and an error type here invites logging it.
    public func password(for credential: Credential) -> String? {
        var query = baseQuery(site: credential.site)
        query[kSecAttrAccount as String] = credential.username
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true

        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Writing

    @discardableResult
    public func save(_ credential: NewCredential) -> Bool {
        // An existing item is updated rather than duplicated: the Keychain's
        // uniqueness constraint on (class, server, account) would refuse the
        // add with `errSecDuplicateItem` anyway, and "update" is what the user
        // means by saving a password they have changed.
        if updateExisting(credential) { return true }

        var attributes = baseQuery(site: credential.site)
        attributes.removeValue(forKey: kSecAttrSynchronizable as String)
        attributes[kSecAttrAccount as String] = credential.username
        attributes[kSecValueData as String] = Data(credential.password.utf8)
        // Names Luna in Keychain Access, so a user looking at two rows for one
        // site can tell which is ours. Display only — nothing queries on it.
        attributes[kSecAttrLabel as String] = "\(credential.site) (\(Self.label))"
        if let origin = credential.originURL {
            attributes[kSecAttrPath as String] = origin.path
            attributes[kSecAttrProtocol as String] = origin.scheme?.lowercased() == "http"
                ? kSecAttrProtocolHTTP
                : kSecAttrProtocolHTTPS
        }
        // Only unlocked, and only on this device unless it is synchronizable.
        // `WhenUnlocked` rather than `AfterFirstUnlock`: a password that fills
        // web forms is only ever needed while someone is at the keyboard.
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked

        return addPreferringSync(attributes)
    }

    /// Tries the §14.2 write, falls back to the local one, and latches what it
    /// learned. The fallback is the entire reason ``Capability`` exists.
    private func addPreferringSync(_ attributes: [String: Any]) -> Bool {
        if capability != .local {
            var synced = attributes
            synced[kSecAttrSynchronizable as String] = kCFBooleanTrue
            let status = SecItemAdd(synced as CFDictionary, nil)
            if status == errSecSuccess {
                capability = .synced
                return true
            }
            // `-34018` is the measured refusal: no entitlement, so no iCloud.
            // Anything else is a real failure and must not be hidden by
            // silently writing a local item instead.
            guard status == errSecMissingEntitlement else {
                capability = .unavailable(status)
                return false
            }
            capability = .local
        }

        var local = attributes
        local[kSecAttrSynchronizable as String] = kCFBooleanFalse
        let status = SecItemAdd(local as CFDictionary, nil)
        if status != errSecSuccess { capability = .unavailable(status) }
        return status == errSecSuccess
    }

    private func updateExisting(_ credential: NewCredential) -> Bool {
        var query = baseQuery(site: credential.site)
        query[kSecAttrAccount as String] = credential.username
        let changes: [String: Any] = [
            kSecValueData as String: Data(credential.password.utf8),
            kSecAttrModificationDate as String: Date()
        ]
        return SecItemUpdate(query as CFDictionary, changes as CFDictionary) == errSecSuccess
    }

    @discardableResult
    public func delete(_ credential: Credential) -> Bool {
        var query = baseQuery(site: credential.site)
        query[kSecAttrAccount as String] = credential.username
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    // MARK: - The day the signature changes

    /// Rewrites every local-only item as a synchronizable one, so the passwords
    /// saved before Luna had an entitlement appear in the Passwords app once it
    /// does. Safe to call on every launch: it no-ops unless the capability has
    /// actually changed.
    ///
    /// Each item is re-added before its local copy is deleted, so a failure
    /// half way through loses nothing — the worst case is a duplicate, which
    /// the next `save` collapses back into one.
    @discardableResult
    public func migrateLocalItemsToSynced() -> Int {
        guard capability == .synced else { return 0 }

        let query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            // Explicitly the local half — not `SynchronizableAny`, which
            // would hand back the already-migrated items and rewrite them on
            // every launch.
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
            kSecAttrCreator as String: Self.creator,
            kSecAttrSecurityDomain as String: Self.securityDomain,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true
        ]

        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let rows = result as? [[String: Any]]
        else { return 0 }

        var moved = 0
        for row in rows {
            guard let credential = Self.credential(from: row),
                  let data = row[kSecValueData as String] as? Data,
                  let password = String(data: data, encoding: .utf8)
            else { continue }

            var attributes = baseQuery(site: credential.site)
            attributes[kSecAttrAccount as String] = credential.username
            attributes[kSecValueData as String] = Data(password.utf8)
            attributes[kSecAttrSynchronizable as String] = kCFBooleanTrue
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
            guard SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess else { continue }

            var old = baseQuery(site: credential.site)
            old[kSecAttrSynchronizable as String] = kCFBooleanFalse
            old[kSecAttrAccount as String] = credential.username
            SecItemDelete(old as CFDictionary)
            moved += 1
        }
        return moved
    }

    /// Re-probes the capability without writing a real credential, so the
    /// settings pane can say what will happen before the user saves anything.
    ///
    /// Writes and immediately deletes a probe item under a reserved,
    /// unresolvable host. `.invalid` is reserved by RFC 2606 precisely so it
    /// can never collide with a site the user actually visits.
    @discardableResult
    public func refreshCapability() -> Capability {
        let probe: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrCreator as String: Self.creator,
            kSecAttrSecurityDomain as String: Self.securityDomain,
            kSecAttrServer as String: "capability-probe.luna.invalid",
            kSecAttrAccount as String: "probe",
            kSecAttrSynchronizable as String: kCFBooleanTrue as Any,
            kSecValueData as String: Data("probe".utf8)
        ]
        SecItemDelete(probe as CFDictionary)
        let wasLocal = capability == .local
        switch SecItemAdd(probe as CFDictionary, nil) {
        case errSecSuccess:
            SecItemDelete(probe as CFDictionary)
            capability = .synced
        case errSecMissingEntitlement:
            capability = .local
        case let status:
            capability = .unavailable(status)
        }
        // The probe is also the trigger for the migration, and without this
        // line `migrateLocalItemsToSynced` would be dead code: nothing else
        // notices the moment the capability changes. The day Luna is signed,
        // the first probe after launch is what carries the already-saved
        // passwords into iCloud Keychain.
        if capability == .synced, wasLocal || !hasMigrated {
            hasMigrated = true
            _ = migrateLocalItemsToSynced()
        }
        return capability
    }

    /// Whether the local→synced sweep has run in this process. The sweep is
    /// idempotent, but it is a Keychain enumeration and there is no reason to
    /// repeat it every time a settings pane opens.
    private var hasMigrated = false

    // MARK: - Plumbing

    /// The attributes that identify a Luna item, shared by every query so the
    /// read path and the write path cannot disagree about what "the same item"
    /// means.
    ///
    /// `kSecAttrSynchronizableAny` is on every query: a store that has been
    /// through the M4 signing change holds both kinds, and a query that named
    /// one kind would quietly stop finding the other half.
    private func baseQuery(site: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrCreator as String: Self.creator,
            kSecAttrSecurityDomain as String: Self.securityDomain,
            kSecAttrServer as String: site,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny
        ]
    }

    private static func credential(from row: [String: Any]) -> Credential? {
        guard let site = row[kSecAttrServer as String] as? String,
              let username = row[kSecAttrAccount as String] as? String
        else { return nil }
        let created = row[kSecAttrCreationDate as String] as? Date ?? Date.distantPast
        let modified = row[kSecAttrModificationDate as String] as? Date ?? created
        let synced = (row[kSecAttrSynchronizable as String] as? Bool) ?? false
        return Credential(
            site: site,
            username: username,
            originURL: URL(string: "https://\(site)"),
            createdAt: created,
            modifiedAt: modified,
            isSynced: synced
        )
    }
}
