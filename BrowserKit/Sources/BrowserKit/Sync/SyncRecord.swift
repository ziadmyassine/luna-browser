import Foundation

// The record the sync core works on (docs/plans/SYNC-PLAN.md §1). `CKRecord` is not `Sendable`
// under Swift 6, so it never leaves `SyncCloudKit.swift`; everything else — mapping,
// merging, the coordinator — sees this value instead.

/// One field value, in the five types `Config/CloudKit/Schema.ckdb` uses.
public enum SyncValue: Sendable, Hashable, Codable {
    case string(String)
    case int(Int64)
    case double(Double)
    case date(Date)
    case bytes(Data)
}

/// A field as it is written: its value, or nil to remove it from the server's record, and
/// whether it travels in `encryptedValues`.
public struct SyncField: Sendable, Hashable, Codable {
    public var value: SyncValue?
    public var isEncrypted: Bool

    public init(_ value: SyncValue?, encrypted: Bool = false) {
        self.value = value
        self.isEncrypted = encrypted
    }
}

/// The CloudKit zones, one per switch on the account page (docs/plans/SYNC-PLAN.md §1, Zones).
public enum SyncZone: String, Sendable, CaseIterable {
    case spaces = "Spaces"
    case sites = "Sites"
    case settings = "Settings"
    case history = "History"
    case devices = "Devices"
    case meta = "Meta"
}

public struct SyncRecord: Sendable, Hashable, Codable {
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

extension SyncRecord {

    /// The version this Luna writes (the §31.9 rules: docs/plans/SYNC-PLAN.md §2, Schema versioning).
    static let currentSchemaVersion: Int64 = 1

    /// A write of `fields` over `stored`, the last record known for this name. It keeps
    /// the stored system fields, never lowers `schemaVersion`, and carries only the
    /// fields given, so a field this version does not know is never touched.
    init(writing recordType: String, name: String, zone: SyncZone, over stored: SyncRecord?, fields: [String: SyncField]) {
        self.init(
            recordType: recordType,
            recordName: name,
            zone: zone.rawValue,
            schemaVersion: max(Self.currentSchemaVersion, stored?.schemaVersion ?? 0),
            fields: fields,
            systemFields: stored?.systemFields
        )
    }
}
