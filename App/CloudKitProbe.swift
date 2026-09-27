//
//  CloudKitProbe.swift
//  Luna
//
//  §31.1's spike: `Luna --cloudkit-probe` asks `cloudd` for the account and
//  round-trips one custom zone, reports the default-browser state, and exits
//  without showing a window. Only meaningful in a `make signed` build; the
//  ad-hoc build has no iCloud entitlements. Results and verdict: docs/SYNC.md.
//  Delete this file and its one line in `AppDelegate.main()` once §31.2 has
//  real sync code to prove the same thing.
//

import AppKit
import CloudKit

@MainActor
enum CloudKitProbe {
    static let argument = "--cloudkit-probe"

    static func run() -> Never {
        Task {
            await probe()
            exit(0)
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

    private static func probe() async {
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
