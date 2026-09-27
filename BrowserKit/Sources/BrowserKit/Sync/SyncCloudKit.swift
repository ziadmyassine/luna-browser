import CloudKit
import Foundation

// The only file that touches `CKRecord` (docs/SYNC-PLAN.md §1). This half converts
// between it and `SyncRecord`; the `CKSyncEngine` adapter joins it in S11.
//
// Nothing here constructs a `CKContainer`: `CKRecord`, its IDs and `CKError` are plain
// values, which is what lets `CloudKitBoundaryTests` run in an unsigned test host.

enum SyncCloudKit {

    static let schemaVersionKey = "schemaVersion"

    /// The `CKRecord` to save. It starts from the stored system fields when there are any,
    /// so it carries the server's change tag, and it sets only the fields in `record`:
    /// a field a newer Luna added stays on the server untouched.
    static func record(from record: SyncRecord) -> CKRecord {
        let zoneID = CKRecordZone.ID(zoneName: record.zone, ownerName: CKCurrentUserDefaultName)
        let ckRecord = record.systemFields.flatMap(Self.record(fromSystemFields:))
            ?? CKRecord(recordType: record.recordType, recordID: CKRecord.ID(recordName: record.recordName, zoneID: zoneID))
        ckRecord[schemaVersionKey] = NSNumber(value: record.schemaVersion)
        for (key, field) in record.fields {
            let object = field.value.map(objectValue)
            if field.isEncrypted {
                ckRecord.encryptedValues[key] = object
            } else {
                ckRecord[key] = object
            }
        }
        return ckRecord
    }

    /// Fields of a type outside `SyncValue` (assets, locations, lists) are dropped: the
    /// schema uses none, and a reader ignores what it does not know.
    static func syncRecord(from ckRecord: CKRecord) -> SyncRecord {
        var fields: [String: SyncField] = [:]
        var schemaVersion: Int64 = 0
        let encrypted = Set(ckRecord.encryptedValues.allKeys())
        for key in encrypted {
            if let value = ckRecord.encryptedValues[key].flatMap(syncValue) {
                fields[key] = SyncField(value, encrypted: true)
            }
        }
        for key in ckRecord.allKeys() where !encrypted.contains(key) {
            guard let value = ckRecord[key].flatMap(syncValue) else { continue }
            if key == schemaVersionKey, case .int(let version) = value {
                schemaVersion = version
            } else {
                fields[key] = SyncField(value)
            }
        }
        return SyncRecord(
            recordType: ckRecord.recordType,
            recordName: ckRecord.recordID.recordName,
            zone: ckRecord.recordID.zoneID.zoneName,
            schemaVersion: schemaVersion,
            fields: fields,
            systemFields: systemFields(of: ckRecord)
        )
    }

    static func systemFields(of record: CKRecord) -> Data {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        coder.finishEncoding()
        return coder.encodedData
    }

    static func record(fromSystemFields data: Data) -> CKRecord? {
        guard let coder = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        coder.requiresSecureCoding = true
        defer { coder.finishDecoding() }
        return CKRecord(coder: coder)
    }

    /// The server's copy from a `serverRecordChanged` failure: the one a merge goes into,
    /// because only it carries the current change tag.
    static func serverRecord(in error: Error) -> SyncRecord? {
        guard let error = error as? CKError, error.code == .serverRecordChanged,
              let server = error.serverRecord else { return nil }
        return syncRecord(from: server)
    }

    private static func objectValue(_ value: SyncValue) -> any CKRecordValue {
        switch value {
        case .string(let string): string as NSString
        case .int(let int): NSNumber(value: int)
        case .double(let double): NSNumber(value: double)
        case .date(let date): date as NSDate
        case .bytes(let data): data as NSData
        }
    }

    private static func syncValue(_ object: any __CKRecordObjCValue) -> SyncValue? {
        switch object {
        case let string as String: return .string(string)
        case let date as Date: return .date(date)
        case let data as Data: return .bytes(data)
        case let number as NSNumber:
            // `objCType` is the only thing that tells an INT64 field from a DOUBLE one.
            let type = String(cString: number.objCType)
            return type == "d" || type == "f" ? .double(number.doubleValue) : .int(number.int64Value)
        default: return nil
        }
    }
}

extension SyncRecord {
    init(_ record: CKRecord) {
        self = SyncCloudKit.syncRecord(from: record)
    }
}
