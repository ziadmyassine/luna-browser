//
//  CloudKitProbe.swift
//  Luna
//
//  `Luna --cloudkit-probe` asks `cloudd` for the account, round-trips one
//  custom zone, reports the default-browser state, and exits without showing
//  a window. `--cloudkit-probe-records` then saves, fetches and deletes one
//  record of each of Luna's types in a throwaway zone: the check that the
//  Production schema takes everything sync sends (docs/SYNC-PLAN.md S11).
//  Only meaningful in a `make signed` build; the ad-hoc build has no iCloud
//  entitlements. §31.1's results and verdict: docs/SYNC.md.
//

import AppKit
import BrowserKit
import CloudKit

@MainActor
enum CloudKitProbe {
    static let argument = "--cloudkit-probe"
    /// Writes records to the Production database, so only once the schema is
    /// deployed there.
    static let recordsArgument = "--cloudkit-probe-records"

    static var isRequested: Bool {
        CommandLine.arguments.contains(argument) || CommandLine.arguments.contains(recordsArgument)
    }

    static func run() -> Never {
        Task {
            let database = await probe()
            let passed = CommandLine.arguments.contains(recordsArgument) ? await probeRecords(in: database) : true
            exit(passed ? 0 : 1)
        }
        dispatchMain()
    }

    private static func log(_ line: String) {
        print("[probe] \(line)")
        fflush(stdout)
    }

    private static func describe(_ error: any Error) -> String {
        if let error = error as? CKError {
            return "CKError \(error.code.rawValue) (\(error.code)): \(error.localizedDescription)"
        }
        return "\(type(of: error)): \(error.localizedDescription)"
    }

    private static func probe() async -> CKDatabase {
        log("bundle \(Bundle.main.bundleIdentifier ?? "nil")")
        defaultBrowser()

        let container = CKContainer(identifier: "iCloud.dev.novapps.luna")
        log("container \(container.containerIdentifier ?? "nil")")
        do {
            let status = try await container.accountStatus()
            log("accountStatus \(status.rawValue) (\(status))")
        } catch {
            log("accountStatus failed: \(describe(error))")
        }
        do {
            let user = try await container.userRecordID()
            log("userRecordID ok (\(user.recordName.prefix(8))…)")
        } catch {
            log("userRecordID failed: \(describe(error))")
        }

        let database = container.privateCloudDatabase
        let zoneID = CKRecordZone.ID(zoneName: "spike")
        do {
            let saved = try await database.modifyRecordZones(saving: [CKRecordZone(zoneID: zoneID)], deleting: [])
            for (id, result) in saved.saveResults {
                switch result {
                case .success: log("save zone \(id.zoneName) ok")
                case .failure(let error): log("save zone \(id.zoneName) failed: \(describe(error))")
                }
            }
            let zones = try await database.allRecordZones()
            log("allRecordZones \(zones.map(\.zoneID.zoneName).sorted())")
            let deleted = try await database.modifyRecordZones(saving: [], deleting: [zoneID])
            for (id, result) in deleted.deleteResults {
                switch result {
                case .success: log("delete zone \(id.zoneName) ok")
                case .failure(let error): log("delete zone \(id.zoneName) failed: \(describe(error))")
                }
            }
        } catch {
            log("zone round-trip failed: \(describe(error))")
        }
        return database
    }

    /// Each type on its own, so a failure names its type. A record fetched
    /// back without a field it was saved with means the schema lacks it.
    private static func probeRecords(in database: CKDatabase) async -> Bool {
        let zoneID = CKRecordZone.ID(zoneName: "probe-\(UUID().uuidString.prefix(8))")
        do {
            _ = try await database.modifyRecordZones(saving: [CKRecordZone(zoneID: zoneID)], deleting: [])
        } catch {
            log("save zone \(zoneID.zoneName) failed: \(describe(error))")
            return false
        }
        let records = SyncProbe.records(inZone: zoneID.zoneName)
        var passed = 0
        for record in records {
            do {
                let saved = try await database.modifyRecords(saving: [record], deleting: [])
                if case .failure(let error)? = saved.saveResults[record.recordID] { throw error }
                let fetched = try await database.record(for: record.recordID)
                let missing = Set(keys(of: record)).subtracting(keys(of: fetched))
                let deleted = try await database.modifyRecords(saving: [], deleting: [record.recordID])
                if case .failure(let error)? = deleted.deleteResults[record.recordID] { throw error }
                guard missing.isEmpty else {
                    log("\(record.recordType) came back without \(missing.sorted())")
                    continue
                }
                log("\(record.recordType) save, fetch, delete ok")
                passed += 1
            } catch {
                log("\(record.recordType) failed: \(describe(error))")
            }
        }
        do {
            _ = try await database.modifyRecordZones(saving: [], deleting: [zoneID])
            log("delete zone \(zoneID.zoneName) ok")
        } catch {
            log("delete zone \(zoneID.zoneName) failed: \(describe(error))")
        }
        log("records \(passed)/\(records.count) ok")
        return passed == records.count
    }

    private static func keys(of record: CKRecord) -> [String] {
        record.allKeys() + record.encryptedValues.allKeys()
    }

    /// Reads, never sets: setting the default shows macOS's confirmation sheet.
    private static func defaultBrowser() {
        let entitlement = "com.apple.security.app-sandbox"
        var code: SecCode?
        var info: CFDictionary?
        if SecCodeCopySelf([], &code) == errSecSuccess, let code {
            var staticCode: SecStaticCode?
            SecCodeCopyStaticCode(code, [], &staticCode)
            if let staticCode {
                SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info)
            }
        }
        let entitlements = (info as? [String: Any])?[kSecCodeInfoEntitlementsDict as String] as? [String: Any]
        log("sandboxed \(entitlements?[entitlement] as? Bool ?? false)")
        log("entitlements \(entitlements?.keys.sorted() ?? [])")

        guard let web = URL(string: "https://example.com") else { return }
        let current = NSWorkspace.shared.urlForApplication(toOpen: web)
        log("default https handler \(current?.path ?? "nil")")
        let candidates = NSWorkspace.shared.urlsForApplications(toOpen: web)
        let luna = candidates.contains { Bundle(url: $0)?.bundleIdentifier == Bundle.main.bundleIdentifier }
        log("https handlers include \(Bundle.main.bundleIdentifier ?? "nil"): \(luna) (\(candidates.count) apps)")
    }
}
