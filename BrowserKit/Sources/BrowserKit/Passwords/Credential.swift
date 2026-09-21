import Foundation

/// One saved login, as the rest of Luna sees it (§14.2).
///
/// The password is not in here. A `Credential` is the row you can list,
/// sort, show in a popover and hand around the app; the secret is fetched from
/// the Keychain by `CredentialStore.password(for:)` at the moment of a fill and
/// is never held anywhere a screenshot, a log line or a crash report could
/// reach it. §14.8's "never expose credentials to page JavaScript" starts by
/// not having them in memory in the first place.
public struct Credential: Hashable, Sendable, Identifiable {

    /// eTLD+1, from ``PublicSuffix/siteKey(forHost:)``. This is the match key
    /// and the Keychain's `kSecAttrServer`, so "what site is this" has exactly
    /// one answer across the store, the matcher and the UI.
    public let site: String

    /// What the user types into the username field. May be an email, a handle
    /// or a customer number; Luna does not interpret it.
    public let username: String

    /// Where it was saved from, for the popover's subtitle and for §14.8's
    /// redirect-chain check. Not a match key — the site is.
    public let originURL: URL?

    public let createdAt: Date
    public let modifiedAt: Date

    /// True when this item lives in iCloud Keychain — it is in the Passwords
    /// app and on the user's other devices. False means local-only, which is
    /// the degraded mode `CredentialStore.Capability` explains.
    public let isSynced: Bool

    public var id: String { "\(site)\u{0}\(username)" }

    public init(
        site: String,
        username: String,
        originURL: URL? = nil,
        createdAt: Date = Date(),
        modifiedAt: Date = Date(),
        isSynced: Bool = false
    ) {
        self.site = site
        self.username = username
        self.originURL = originURL
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.isSynced = isSynced
    }
}

/// A password on its way into the Keychain — and the only type in Luna that
/// carries one.
///
/// Deliberately not `Codable`, not `CustomStringConvertible` and not
/// `Hashable`: every one of those is a way a secret ends up in a log, a
/// `UserDefaults` value or a diffable snapshot by accident. The only thing you
/// can do with it is hand it to `CredentialStore`.
public struct NewCredential: Sendable {
    public let site: String
    public let username: String
    public let password: String
    public let originURL: URL?

    public init(site: String, username: String, password: String, originURL: URL?) {
        self.site = site
        self.username = username
        self.password = password
        self.originURL = originURL
    }
}
