import Foundation

// The record the sync core works on (docs/SYNC-PLAN.md §1). `CKRecord` is not `Sendable`
// under Swift 6, so it never leaves `SyncCloudKit.swift`; everything else — mapping,
// merging, the coordinator — sees this value instead.

/// One field value, in the five types `CloudKit/Schema.ckdb` uses.
public enum SyncValue: Sendable, Hashable {
    case string(String)
    case int(Int64)
    case double(Double)
    case date(Date)
    case bytes(Data)
}

/// A field as it is written: its value, or nil to remove it from the server's record, and
/// whether it travels in `encryptedValues`.
public struct SyncField: Sendable, Hashable {
    public var value: SyncValue?
    public var isEncrypted: Bool

    public init(_ value: SyncValue?, encrypted: Bool = false) {
        self.value = value
        self.isEncrypted = encrypted
    }
}

/// The CloudKit zones, one per switch on the account page (docs/SYNC-PLAN.md §1, Zones).
public enum SyncZone: String, Sendable, CaseIterable {
    case spaces = "Spaces"
    case sites = "Sites"
    case settings = "Settings"
    case history = "History"
    case devices = "Devices"
    case meta = "Meta"
}

public struct SyncRecord: Sendable, Hashable {
    /// A string, not an enum: a record type a newer Luna added still has to be carried
    /// and ignored rather than failing to decode.
    public var recordType: String
    public var recordName: String
    public var zone: String
    /// Kept apart from `fields` so a mapper cannot forget it. On the wire it is the plain
    /// `schemaVersion` field; 0 means the record had none.
    public var schemaVersion: Int64
    public var fields: [String: SyncField]
    /// `encodeSystemFields` of the last record the server returned, or nil for a record
    /// it has never seen. A write starts from these so it carries the server's change tag.
    public var systemFields: Data?

    public init(
        recordType: String,
        recordName: String,
        zone: String,
        schemaVersion: Int64,
        fields: [String: SyncField] = [:],
        systemFields: Data? = nil
    ) {
        self.recordType = recordType
        self.recordName = recordName
        self.zone = zone
        self.schemaVersion = schemaVersion
        self.fields = fields
        self.systemFields = systemFields
    }

    public subscript(key: String) -> SyncValue? { fields[key]?.value }
}
