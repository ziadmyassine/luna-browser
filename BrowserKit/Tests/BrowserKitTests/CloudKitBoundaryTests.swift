@testable import BrowserKit
import CloudKit
import Foundation
import Testing

/// The CloudKit values the sync core leans on, checked without a container (§31.2, S1).
///
/// Nothing here constructs `CKContainer`, `CKDatabase` or `CKSyncEngine`: without the
/// iCloud entitlement, which no test host and no CI runner has, constructing one crashes.
/// `CKRecord`, its IDs and `CKError` are plain values and need no daemon.
@Suite("CloudKit boundary (§31.2)")
struct CloudKitBoundaryTests {

    private static let zone = CKRecordZone.ID(zoneName: SyncZone.spaces.rawValue, ownerName: CKCurrentUserDefaultName)

    private static func record(_ name: String = "0F6A3C2E-5B1D-4E0A-9F7B-2C8D1E4A6B90") -> CKRecord {
        CKRecord(recordType: "Space", recordID: CKRecord.ID(recordName: name, zoneID: zone))
    }

    /// A record the server has seen carries a change tag, and a local one cannot be given
    /// one through public API. `setEtag:` is what CloudKit itself calls when a save
    /// returns; the test uses it only to stand in for that reply.
    private static func stampChangeTag(_ tag: String, on record: CKRecord) throws {
        let selector = NSSelectorFromString("setEtag:")
        try #require(record.responds(to: selector), "CKRecord no longer answers setEtag:")
        _ = record.perform(selector, with: tag)
    }

    @Test func encryptedValuesRoundTripOnARecordWithNoContainer() {
        let record = Self.record()
        record.encryptedValues["name"] = "Work" as NSString

        #expect(record.encryptedValues["name"] as? String == "Work")
        #expect(record.encryptedValues.allKeys() == ["name"])
        #expect(record["name"] == nil, "an encrypted value is not also a plain one")
        #expect(record.allKeys().contains("name"), "allKeys() lists encrypted keys as well")
    }

    @Test func systemFieldsRoundTripAndKeepTheChangeTag() throws {
        let record = Self.record()
        record["position"] = 3 as NSNumber
        try Self.stampChangeTag("tag-7", on: record)

        let data = SyncCloudKit.systemFields(of: record)
        let back = try #require(SyncCloudKit.record(fromSystemFields: data))

        #expect(back.recordID == record.recordID)
        #expect(back.recordType == "Space")
        #expect(back.recordChangeTag == "tag-7")
        #expect(back.allKeys().isEmpty, "system fields carry no values")
    }

    @Test func aRecordRebuiltFromSystemFieldsReportsOnlyTheKeysSetOnIt() throws {
        let record = Self.record()
        record["position"] = 3 as NSNumber
        record["future"] = "a field a newer Luna added" as NSString
        record.encryptedValues["name"] = "Work" as NSString

        let back = try #require(SyncCloudKit.record(fromSystemFields: SyncCloudKit.systemFields(of: record)))
        back["position"] = 4 as NSNumber
        back.encryptedValues["name"] = "Home" as NSString

        #expect(Set(back.changedKeys()) == ["position", "name"], "only these go to the server; `future` is left alone")
    }

    @Test func aServerRecordChangedErrorCarriesTheServerRecord() throws {
        let server = Self.record()
        server.encryptedValues["name"] = "Theirs" as NSString
        try Self.stampChangeTag("tag-9", on: server)
        let error: Error = CKError(.serverRecordChanged, userInfo: [CKRecordChangedErrorServerRecordKey: server])

        let record = try #require(SyncCloudKit.serverRecord(in: error))

        #expect(record["name"] == .string("Theirs"))
        let systemFields = try #require(record.systemFields)
        let rebuilt = try #require(SyncCloudKit.record(fromSystemFields: systemFields))
        #expect(rebuilt.recordChangeTag == "tag-9", "a merge saves against the server's tag")
    }

    @Test func otherErrorsCarryNoServerRecord() {
        #expect(SyncCloudKit.serverRecord(in: CKError(.networkUnavailable)) == nil)
        #expect(SyncCloudKit.serverRecord(in: CocoaError(.fileNoSuchFile)) == nil)
    }

    @Test func syncRecordToCKRecordKeepsEveryFieldAndItsEncryption() throws {
        let when = Date(timeIntervalSince1970: 1_790_000_000)
        let original = SyncRecord(
            recordType: "Tab",
            recordName: "5E2B7A10-3C4D-4F6E-8A9B-0C1D2E3F4A5B",
            zone: SyncZone.spaces.rawValue,
            schemaVersion: 2,
            fields: [
                "position": SyncField(.int(4)),
                "modifiedAt": SyncField(.date(when)),
                "ratio": SyncField(.double(1.5)),
                "kind": SyncField(.string("pinned")),
                "url": SyncField(.string("https://example.com/"), encrypted: true),
                "zoom": SyncField(.double(1.25), encrypted: true),
                "flag": SyncField(.int(1), encrypted: true),
                "image": SyncField(.bytes(Data([1, 2, 3])), encrypted: true),
                "seenAt": SyncField(.date(when), encrypted: true)
            ]
        )

        let ckRecord = SyncCloudKit.record(from: original)

        #expect(ckRecord.recordType == "Tab")
        #expect(ckRecord.recordID.recordName == original.recordName)
        #expect(ckRecord.recordID.zoneID.zoneName == "Spaces")
        #expect(Set(ckRecord.encryptedValues.allKeys()) == ["url", "zoom", "flag", "image", "seenAt"])
        #expect(ckRecord["url"] == nil)
        #expect(ckRecord["schemaVersion"] as? Int64 == 2, "schemaVersion is a plain field on the wire")

        var back = SyncRecord(ckRecord)
        back.systemFields = nil
        #expect(back == original)
    }

    @Test func aFieldWithNoValueIsClearedOnTheCKRecord() throws {
        var stored = SyncRecord(recordType: "Tab", recordName: "t", zone: SyncZone.spaces.rawValue, schemaVersion: 1, fields: [
            "customTitle": SyncField(.string("Mine"), encrypted: true),
            "groupID": SyncField(.string("g"))
        ])
        stored = SyncRecord(SyncCloudKit.record(from: stored))

        var cleared = stored
        cleared.fields = ["customTitle": SyncField(nil, encrypted: true), "groupID": SyncField(nil)]
        let ckRecord = SyncCloudKit.record(from: cleared)

        #expect(Set(ckRecord.changedKeys()).isSuperset(of: ["customTitle", "groupID"]), "a known field set to nothing is sent as a removal")
        #expect(ckRecord.encryptedValues["customTitle"] == nil)
        #expect(ckRecord["groupID"] == nil)
    }

    @Test func aWriteStartsFromTheStoredSystemFields() throws {
        let server = Self.record()
        try Self.stampChangeTag("tag-3", on: server)
        var record = SyncRecord(server)
        record.fields = ["position": SyncField(.int(9))]

        let ckRecord = SyncCloudKit.record(from: record)

        #expect(ckRecord.recordChangeTag == "tag-3")
        #expect(ckRecord.changedKeys().contains("position"))
    }
}
