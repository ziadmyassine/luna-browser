import Foundation
import Security

/// Luna's bridge into Apple's password store (§14.2). Luna has no vault of
/// its own and no master password: every credential is a
/// `kSecClassInternetPassword` item in the user's Keychain, written
/// `kSecAttrSynchronizable` where it can be so it reaches iCloud Keychain and
/// the Passwords app.
///
/// Under the ad-hoc signature `project.yml` gives Luna today
/// (`CODE_SIGN_IDENTITY: "-"`), a synchronizable or data-protection
/// `SecItemAdd` fails with `-34018` (errSecMissingEntitlement) on macOS 26,
/// while local items add, read, update and delete normally; the entitlement
/// needs a provisioning profile (§24.4). Every write therefore tries
/// synchronizable first and falls back to local on `-34018`, latching the
/// answer in ``capability``, so once Luna is signed the same code starts
/// syncing and ``migrateLocalItemsToSynced()`` carries the items already
/// written. `docs/PASSWORDS.md` has the probe.
///
/// Items Safari and the Passwords app create live in Apple's own access
/// groups, and `keychain-access-groups` only grants groups under Luna's own
/// team ID. A query for them returns `errSecItemNotFound` (no prompt, no
/// denial), so Luna can add to the Passwords app but never read what is
/// already there, and `PasswordsSection` does not claim to "use your existing
/// passwords".
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
        /// The Keychain refused for a reason that is not the entitlement — a
        /// locked keychain, a damaged one. Carries the raw `OSStatus` because
        /// the settings pane shows it: a number the user can search beats
        /// "something went wrong".
        case unavailable(OSStatus)
    }

    public private(set) var capability: Capability = .unknown

    /// Shown in Keychain Access beside the item, so it names the product and
    /// the site rather than a bundle identifier.
    private static let label = "Luna"

    /// What marks an item as Luna's own.
    ///
    /// Not `kSecAttrService`: that belongs to `kSecClassGenericPassword`, and on
    /// an internet password the Keychain silently ignores it in both a query
    /// and an add (measured: a query with an impossible service name returned
    /// the same row). Filtering on it left `baseQuery` matching every internet
    /// password for the host, whoever wrote it, so the picker offered a
    /// `github.com` item from `git-credential-osxkeychain` whose "password" is
    /// an access token, and `save` and `delete`, which share the query, could
    /// have rewritten or destroyed it.
    ///
    /// `kSecAttrCreator` is valid on both classes and is honoured: a query with
    /// a different creator returns nothing.
    private static let creator = FourCharCode(0x4C75_6E61)

    /// The other half of scoping Luna's items, and the half that makes saving
    /// work.
    ///
    /// `kSecAttrCreator` scopes a query but is not part of the Keychain's
    /// uniqueness key for an internet password (server, account, protocol,
    /// port, path, securityDomain, authenticationType), so with the creator
    /// alone a (host, account) another application already held made
    /// `SecItemAdd` return `errSecDuplicateItem` and the save fail silently.
    /// `kSecAttrSecurityDomain` is part of that key and honoured in queries.
    /// Measured: two items differing only in security domain coexist, a scoped
    /// query returns only Luna's, and a scoped delete leaves the other alone.
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
    /// could tell "no such item" from "keychain locked" would have nothing
    /// different to do, and an error type here invites logging it.
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
        // Nothing else notices the moment the capability changes, so the probe
        // is what triggers the migration: the first probe after Luna is signed
        // carries the already-saved passwords into iCloud Keychain.
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
