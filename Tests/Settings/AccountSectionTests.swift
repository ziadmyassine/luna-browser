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

    private func syncSwitch(_ section: AccountSection) throws -> SystemSwitch {
        let card = try XCTUnwrap(descendants(of: section.view, ofType: AccountSyncCard.self).first)
        let all = descendants(of: card, ofType: SystemSwitch.self)
        XCTAssertEqual(all.count, 1, "the zones are checks, not more switches")
        return try XCTUnwrap(all.first)
    }

    /// The five zones in `SyncZone.switched`'s order.
    private func zones(_ section: AccountSection) -> [SyncZoneCheckRow] {
        descendants(of: section.view, ofType: SyncZoneCheckRow.self)
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

    func testSyncIsOffByDefaultAndTheZonesWaitForIt() throws {
        let section = AccountSection(sync: signedIn())
        XCTAssertFalse(try syncSwitch(section).isOn, "sync is opt-in")
        XCTAssertTrue(try syncSwitch(section).isEnabled)
        XCTAssertEqual(zones(section).count, 5)
        for zone in zones(section) {
            XCTAssertFalse(zone.isEnabled, "a zone is live while sync is off")
        }
        XCTAssertTrue(texts(in: section.view).contains("iCloud sync off"))
    }

    func testTheZonesFollowSyncAndHistoryNeedsSpaces() throws {
        let sync = signedIn(zones: [.meta, .spaces, .sites, .settings, .history, .devices])
        let section = AccountSection(sync: sync)
        XCTAssertTrue(try syncSwitch(section).isOn)
        XCTAssertEqual(zones(section).map(\.isEnabled), [true, true, true, true, true])
        XCTAssertEqual(zones(section).map(\.isOn), [true, true, true, true, true])

        sync.zones = [.meta, .sites, .settings, .history, .devices]
        XCTAssertEqual(zones(section).map(\.isEnabled), [true, true, true, false, true], "Typed history is live without Spaces")
        XCTAssertTrue(texts(in: section.view).contains("Needs Spaces"), "Typed history does not say why it is off")
    }

    func testTheSwitchAndTheChecksDriveSync() throws {
        var calls: [String] = []
        let sync = signedIn()
        sync.setEnabled = { calls.append("master \($0)") }
        sync.setZone = { calls.append("\($0.rawValue) \($1)") }
        let section = AccountSection(sync: sync)
        try syncSwitch(section).onChange?(true)
        sync.zones = [.meta, .spaces, .sites, .settings, .history, .devices]
        XCTAssertTrue(zones(section)[1].accessibilityPerformPress())
        XCTAssertEqual(calls, ["master true", "Sites false"])
    }

    /// The switch is updated, never rebuilt, while sync answers: a new switch
    /// swapped in mid-slide was the stutter. And a status that moves before
    /// the zones are written does not throw it back.
    func testFlippingTheSwitchKeepsItAndItsSlide() throws {
        let sync = signedIn()
        let section = AccountSection(sync: sync)
        let flipped = try syncSwitch(section)
        flipped.isOn = true
        flipped.onChange?(true)
        XCTAssertTrue(zones(section).allSatisfy(\.isEnabled), "the checks waited for iCloud")

        sync.status = .syncing
        XCTAssertTrue(try syncSwitch(section) === flipped, "the switch was rebuilt under the finger")
        XCTAssertTrue(flipped.isOn, "an early status threw the switch back")

        sync.zones = [.meta, .spaces, .sites, .settings, .history, .devices]
        sync.status = .synced(Date())
        XCTAssertTrue(try syncSwitch(section) === flipped)
        XCTAssertTrue(flipped.isOn)
        XCTAssertTrue(texts(in: section.view).contains(SyncStatus.synced(Date()).line()))
    }

    /// A zone that is off for a reason the user did not choose cannot be
    /// ticked: pressing it does nothing.
    func testADisabledCheckIgnoresThePress() {
        var calls = 0
        let sync = signedIn()
        sync.setZone = { _, _ in calls += 1 }
        let section = AccountSection(sync: sync)
        XCTAssertFalse(zones(section)[0].accessibilityPerformPress())
        XCTAssertEqual(calls, 0)
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
    func testTheSyncSwitchIsDisabledWithoutTheSignedBuild() throws {
        let sync = SyncSettings()
        sync.status = .needsSignedBuild
        let section = AccountSection(sync: sync)
        XCTAssertFalse(try syncSwitch(section).isEnabled)
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
        XCTAssertTrue(section.searchIndex.contains("manage icloud storage"))
    }

    /// The page opens on the user, not on a tile and a title.
    func testThePageOpensOnThePictureAndName() {
        let section = AccountSection(sync: signedIn())
        XCTAssertFalse(descendants(of: section.view, ofType: AccountHeroView.self).isEmpty, "no picture at the head of the page")
        XCTAssertTrue(texts(in: section.view).contains(NSFullUserName()))
        XCTAssertTrue(SettingsSectionRegistry.hasOwnHeader(AccountSection.id), "a second header sits over the picture")
    }
}
