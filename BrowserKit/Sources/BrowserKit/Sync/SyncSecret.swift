import CryptoKit
import Foundation

/// The per-account secret that site record names are keyed by (docs/SYNC-PLAN.md §1,
/// Record IDs). It lives in the `Meta` zone, so every Mac on the account derives the
/// same name for a host, and the server never sees the host in the clear: a plain hash
/// of a hostname falls to a dictionary of hostnames.
public struct SyncSecret: Sendable, Hashable {

    static let recordType = "SyncSecret"
    /// Fixed, so two Macs creating the secret at once collide as `serverRecordChanged`
    /// instead of leaving two secrets on the account.
    static let recordName = "secret"
    static let byteCount = 32

    public let bytes: Data

    public init(bytes: Data) {
        self.bytes = bytes
    }

    public static func generate() -> SyncSecret {
        SyncSecret(bytes: SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) })
    }

    /// `site-` and the first 26 characters of base32(HMAC-SHA256(secret, host)): 130 bits,
    /// within CloudKit's record-name limit.
    public func siteRecordName(forHost host: String) -> String {
        let mac = HMAC<SHA256>.authenticationCode(for: Data(host.utf8), using: SymmetricKey(data: bytes))
        return "site-" + Self.base32(Data(mac)).prefix(26)
    }

    func record(stored: SyncRecord?) -> SyncRecord {
        SyncRecord(writing: Self.recordType, name: Self.recordName, zone: .meta, over: stored, fields: [
            "secret": SyncField(.bytes(bytes), encrypted: true)
        ])
    }

    init?(record: SyncRecord) {
        guard record.recordType == Self.recordType, case .bytes(let bytes) = record["secret"],
              bytes.count == Self.byteCount else { return nil }
        self.bytes = bytes
    }

    /// RFC 4648 base32, lowercased and unpadded.
    private static func base32(_ data: Data) -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyz234567")
        var output = ""
        var buffer = 0
        var bits = 0
        for byte in data {
            buffer = (buffer << 8) | Int(byte)
            bits += 8
            while bits >= 5 {
                bits -= 5
                output.append(alphabet[(buffer >> bits) & 31])
            }
        }
        if bits > 0 { output.append(alphabet[(buffer << (5 - bits)) & 31]) }
        return output
    }
}

/// Whether the secret can key anything yet. A proposal this Mac generated is not the
/// account's secret until the server has accepted it: another Mac may have saved first,
/// and every site record named with the losing proposal would be an orphan.
public struct SyncSecretState: Sendable {

    public private(set) var settled: SyncSecret?
    private var proposed: SyncSecret?

    public init(settled: SyncSecret? = nil) {
        self.settled = settled
    }

    /// The secret to save when a fetch found none. The same one until it settles.
    public mutating func proposal() -> SyncSecret {
        if let proposed { return proposed }
        let secret = SyncSecret.generate()
        proposed = secret
        return secret
    }

    /// The proposal was saved. A secret already received from the server outranks it.
    public mutating func saved() {
        guard settled == nil, let proposed else { return }
        settled = proposed
        self.proposed = nil
    }

    /// A secret from the server, fetched or carried by a `serverRecordChanged` failure.
    /// The server always wins (docs/SYNC-PLAN.md §3).
    public mutating func received(_ record: SyncRecord) {
        guard let secret = SyncSecret(record: record) else { return }
        settled = secret
        proposed = nil
    }

    /// Nil until the secret is settled, which is what keeps site records unsent until then.
    public func siteRecordName(forHost host: String) -> String? {
        settled?.siteRecordName(forHost: host)
    }
}
