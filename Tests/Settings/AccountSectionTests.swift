//
//  AccountSectionTests.swift
//  LunaTests
//
//  The iCloud page (docs/SYNC-PLAN.md §5): what is on, what is disabled and
//  why, and that the one destructive button asks first. Driven through
//  `SyncSettings`, so nothing here needs CloudKit.
//

import BrowserKit
import XCTest
@testable import Luna

@MainActor
final class AccountSectionTests: XCTestCase {

    private func descendants<T: NSView>(of root: NSView, ofType type: T.Type) -> [T] {
        root.subviews.flatMap { child -> [T] in
            ((child as? T).map { [$0] } ?? []) + descendants(of: child, ofType: type)
        }
    }

    private func texts(in view: NSView) -> [String] {
        descendants(of: view, ofType: NSTextField.self).map(\.stringValue)
    }

    /// The master switch first, then the five zones in `SyncZone`'s order.
    private func switches(_ section: AccountSection) -> [SystemSwitch] {
        descendants(of: section.view, ofType: SystemSwitch.self)
    }

    private func button(_ title: String, in section: AccountSection) throws -> SettingsPushButton {
        try XCTUnwrap(descendants(of: section.view, ofType: SettingsPushButton.self).first { $0.title == title })
    }

    private func signedIn(zones: Set<SyncZone> = []) -> SyncSettings {
        let sync = SyncSettings()
        sync.status = .off
        sync.zones = zones
        return sync
    }

    func testSyncIsOffByDefaultAndTheZonesWaitForIt() {
        let section = AccountSection(sync: signedIn())
        let all = switches(section)
        XCTAssertEqual(all.count, 6, "the master switch and five zones")
        XCTAssertFalse(all[0].isOn, "sync is opt-in")
        XCTAssertTrue(all[0].isEnabled)
        for zone in all.dropFirst() {
            XCTAssertFalse(zone.isEnabled, "a zone switch is live while sync is off")
        }
        XCTAssertTrue(texts(in: section.view).contains("iCloud sync off"))
    }

    func testTheZonesFollowSyncAndHistoryNeedsSpaces() {
        let sync = signedIn(zones: [.meta, .spaces, .sites, .settings, .history, .devices])
        let section = AccountSection(sync: sync)
        XCTAssertTrue(switches(section)[0].isOn)
        XCTAssertEqual(switches(section).dropFirst().map(\.isEnabled), [true, true, true, true, true])
        XCTAssertEqual(switches(section).dropFirst().map(\.isOn), [true, true, true, true, true])

        sync.zones = [.meta, .sites, .settings, .history, .devices]
        let zones = switches(section).dropFirst().map(\.isEnabled)
        XCTAssertEqual(zones, [true, true, true, false, true], "Typed history is live without Spaces")
    }

    func testTheSwitchesDriveSync() {
        var calls: [String] = []
        let sync = signedIn()
        sync.setEnabled = { calls.append("master \($0)") }
        sync.setZone = { calls.append("\($0.rawValue) \($1)") }
        let section = AccountSection(sync: sync)
        switches(section)[0].onChange?(true)
        sync.zones = [.meta, .spaces, .sites, .settings, .history, .devices]
        switches(section)[2].onChange?(false)
        XCTAssertEqual(calls, ["master true", "Sites false"])
    }

    func testTheCookieLineIsOnThePage() {
        let section = AccountSection(sync: signedIn())
        XCTAssertTrue(texts(in: section.view).contains(AccountSection.cookieLine))
        XCTAssertEqual(AccountSection.cookieLine, "Cookies, logins and website data stay on this Mac.")
    }

    func testSyncNowRunsASync() throws {
        var ran = 0
        let sync = signedIn(zones: [.meta, .spaces])
        sync.syncNow = { ran += 1 }
        let section = AccountSection(sync: sync)
        try button("Sync Now", in: section).onActivate?()
        XCTAssertEqual(ran, 1)
    }

    func testRemoveAsksFirst() throws {
        var asked: [String] = []
        var answer = false
        var removed = 0
        let sync = signedIn(zones: [.meta, .spaces])
        sync.removeAll = { removed += 1 }
        let section = AccountSection(sync: sync) { message, _, _ in
            asked.append(message)
            return answer
        }
        let remove = try button("Remove Luna Data from iCloud…", in: section)

        remove.onActivate?()
        XCTAssertEqual(asked.count, 1, "Remove did not go through the confirmation")
        XCTAssertEqual(removed, 0, "cancelling removed the data anyway")

        answer = true
        try button("Remove Luna Data from iCloud…", in: section).onActivate?()
        XCTAssertEqual(removed, 1)
    }

    /// The unsigned build has no iCloud entitlement, and the switch says so
    /// rather than doing nothing.
    func testTheSyncSwitchIsDisabledWithoutTheSignedBuild() {
        let sync = SyncSettings()
        sync.status = .needsSignedBuild
        let section = AccountSection(sync: sync)
        XCTAssertFalse(switches(section)[0].isEnabled)
        XCTAssertTrue(texts(in: section.view).contains(SyncStatus.needsSignedBuild.line()))
    }

    func testTheStatusLineFollowsSync() {
        let sync = signedIn(zones: [.meta, .spaces])
        let section = AccountSection(sync: sync)
        sync.status = .storageFull
        XCTAssertTrue(texts(in: section.view).contains(SyncStatus.storageFull.line()))
    }

    /// §2's search finds the page's rows.
    func testTheSearchFindsTheZones() {
        let section = AccountSection(sync: signedIn())
        XCTAssertTrue(section.searchIndex.contains("typed history"))
        XCTAssertTrue(section.searchIndex.contains("sync now"))
    }
}
