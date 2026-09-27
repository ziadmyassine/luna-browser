@testable import BrowserKit
import Foundation
import Testing

/// The conflict rules, one test per row of docs/SYNC-PLAN.md §3 (S7).
@Suite("Sync merge rules (§31.4)")
struct SyncMergeTests {

    private let now = SyncSamples.now
    private var earlier: Date { now.addingTimeInterval(-60) }
    private var later: Date { now.addingTimeInterval(60) }

    // MARK: Space, TabGroup, Tab: last writer wins, delete beats edit

    @Test func aNewerLocalSpaceEditIsSavedOverTheServersRecord() throws {
        var mine = SyncSamples.space
        mine.name = "Mine"
        var theirs = SyncSamples.space
        theirs.name = "Theirs"
        var server = SyncMapping.record(for: theirs, modifiedAt: earlier, stored: nil)
        server.systemFields = Data([9])
        let local = SyncMapping.record(for: mine, modifiedAt: now, stored: nil)

        let outcome = SyncMerge.resolve(local: local, changedAt: now, server: server)

        guard case .save(let merged) = outcome else { Issue.record("expected a save, got \(outcome)"); return }
        #expect(merged.systemFields == Data([9]))
        #expect(SyncMapping.space(from: merged)?.name == "Mine")
    }

    @Test func aNewerServerSpaceEditWins() {
        let server = SyncMapping.record(for: SyncSamples.space, modifiedAt: later, stored: nil)
        let local = SyncMapping.record(for: SyncSamples.space, modifiedAt: now, stored: nil)
        #expect(SyncMerge.resolve(local: local, changedAt: now, server: server) == .takeServer)
    }

    @Test func aTabGroupIsLastWriterWinsToo() {
        let server = SyncMapping.record(for: SyncSamples.group, modifiedAt: earlier, stored: nil)
        let local = SyncMapping.record(for: SyncSamples.group, modifiedAt: now, stored: nil)
        #expect(SyncMerge.resolve(local: local, changedAt: now, server: server) != .takeServer)
        #expect(SyncMerge.resolve(local: local, changedAt: earlier.addingTimeInterval(-1), server: server) == .takeServer)
    }

    /// A delete made before the other Mac's edit still wins: the record is gone.
    @Test func aLocalDeleteBeatsANewerServerEdit() {
        for record in [
            SyncMapping.record(for: SyncSamples.space, modifiedAt: later, stored: nil),
            SyncMapping.record(for: SyncSamples.group, modifiedAt: later, stored: nil),
            SyncMapping.record(for: SyncSamples.tab, modifiedAt: later, stored: nil)
        ] {
            #expect(SyncMerge.resolve(recordType: record.recordType, local: nil, changedAt: earlier, server: record) == .deleteOnServer)
        }
    }

    @Test func aServerDeleteBeatsANewerLocalEdit() {
        let local = SyncMapping.record(for: SyncSamples.tab, modifiedAt: later, stored: nil)
        #expect(SyncMerge.resolve(local: local, changedAt: later, server: nil) == .takeServer)
    }

    // MARK: Tab: archive against activity, live web views

    /// One Mac's idle clock never archives a tab in use on another (§3, Tab).
    @Test func anIncomingArchiveLosesToLaterLocalActivityAndTheUnarchiveIsSentBack() {
        var local = SyncSamples.tab
        local.archivedAt = nil
        local.lastActiveAt = later
        var remote = SyncSamples.tab
        remote.archivedAt = now
        remote.title = "Renamed"

        let merged = SyncMerge.incoming(remote, over: local, isLive: false)

        #expect(merged.tab.archivedAt == nil)
        #expect(merged.tab.title == "Renamed")
        #expect(merged.sendBack)
    }

    @Test func anIncomingArchiveAfterTheLastLocalActivityIsApplied() {
        var local = SyncSamples.tab
        local.archivedAt = nil
        local.lastActiveAt = earlier
        var remote = SyncSamples.tab
        remote.archivedAt = now

        let merged = SyncMerge.incoming(remote, over: local, isLive: false)

        #expect(merged.tab.archivedAt == now)
        #expect(!merged.sendBack)
    }

    @Test func aLiveTabKeepsItsURLAndTitleButTakesTheStructure() {
        let local = SyncSamples.tab
        var remote = SyncSamples.tab
        remote.url = URL(string: "https://elsewhere.example/")!
        remote.title = "Elsewhere"
        remote.order = 9
        remote.kind = .today

        let merged = SyncMerge.incoming(remote, over: local, isLive: true)

        #expect(merged.tab.url == local.url)
        #expect(merged.tab.title == local.title)
        #expect(merged.tab.order == 9)
        #expect(merged.tab.kind == .today)
        #expect(!merged.sendBack)
    }

    /// The columns that only matter on this Mac never come from the record.
    @Test func anIncomingTabKeepsThisMacsLocalColumns() {
        let local = SyncSamples.tab
        let remote = SyncMapping.tab(from: SyncMapping.record(for: local, modifiedAt: now, stored: nil))!

        let merged = SyncMerge.incoming(remote, over: local, isLive: false).tab

        #expect(merged.parentTabID == local.parentTabID)
        #expect(merged.interactionState == local.interactionState)
        #expect(merged.lastActiveAt == local.lastActiveAt)
        #expect(merged.faviconKey == local.faviconKey)
        #expect(merged.isDormant == local.isDormant)
    }

    // MARK: Favorites

    @Test func favoritesPastTwelveAreDemotedToPinnedByPositionThenCreation() {
        let space = UUID()
        let base = Date(timeIntervalSince1970: 1_780_000_000)
        // Fourteen Favorites; two share position 5, so `createdAt` decides between them.
        var tabs = (0..<13).map { index in
            Tab(spaceID: space, kind: .essential, url: URL(string: "https://f\(index).example")!,
                createdAt: base.addingTimeInterval(Double(index)), order: index)
        }
        let tied = Tab(spaceID: space, kind: .essential, url: URL(string: "https://tied.example")!,
                       createdAt: base.addingTimeInterval(-1), order: 5)
        tabs.append(tied)
        let archived = Tab(spaceID: space, kind: .essential, url: URL(string: "https://gone.example")!,
                           archivedAt: base, order: 0)
        let otherSpace = Tab(spaceID: UUID(), kind: .essential, url: URL(string: "https://other.example")!, order: 99)

        let demoted = SyncMerge.demotingExtraFavorites(in: (tabs + [archived, otherSpace]).shuffled())

        #expect(demoted.map(\.url) == [tabs[11].url, tabs[12].url])
        #expect(demoted.allSatisfy { $0.kind == .pinned })
        #expect(!demoted.contains { $0.id == tied.id })
    }

    @Test func twelveFavoritesAreLeftAlone() {
        let space = UUID()
        let tabs = (0..<12).map { Tab(spaceID: space, kind: .essential, url: URL(string: "https://f\($0).example")!, order: $0) }
        #expect(SyncMerge.demotingExtraFavorites(in: tabs).isEmpty)
    }

    // MARK: SiteSetting: field by field

    @Test func aSetSiteFlagBeatsAnUnsetOneInEitherDirection() throws {
        let secret = SyncSamples.secret
        let mine = SyncSiteSetting(host: "example.com", popups: true)
        let theirs = SyncSiteSetting(host: "example.com", localNetwork: true)
        let server = SyncMapping.record(for: theirs, secret: secret, modifiedAt: later, stored: nil)
        let local = SyncMapping.record(for: mine, secret: secret, modifiedAt: now, stored: nil)

        guard case .save(let merged) = SyncMerge.resolve(local: local, changedAt: now, server: server) else {
            Issue.record("expected a save"); return
        }
        let site = try #require(SyncMapping.siteSetting(from: merged))
        #expect(site.popups == true)
        #expect(site.localNetwork == true)
    }

    @Test func whenBothMacsSetAFlagTheNewerOneWins() throws {
        let secret = SyncSamples.secret
        let server = SyncMapping.record(for: SyncSiteSetting(host: "example.com", popups: false), secret: secret, modifiedAt: earlier, stored: nil)
        let local = SyncMapping.record(for: SyncSiteSetting(host: "example.com", popups: true), secret: secret, modifiedAt: now, stored: nil)

        guard case .save(let merged) = SyncMerge.resolve(local: local, changedAt: now, server: server) else {
            Issue.record("expected a save"); return
        }
        #expect(SyncMapping.siteSetting(from: merged)?.popups == true)
        #expect(SyncMerge.resolve(local: local, changedAt: earlier.addingTimeInterval(-1), server: server) == .takeServer)
    }

    /// `blockingDisabled` and `insecureAllowed` are only written when on, so this Mac's off
    /// is unset and cannot switch another Mac's on back off.
    @Test func anOffBlockingFlagNeverOverridesAnotherMacsOn() throws {
        let secret = SyncSamples.secret
        let server = SyncMapping.record(
            for: SyncSiteSetting(host: "example.com", blockingDisabled: true, insecureAllowed: true),
            secret: secret, modifiedAt: earlier, stored: nil
        )
        let local = SyncMapping.record(
            for: SyncSiteSetting(host: "example.com", blockingDisabled: false, insecureAllowed: false),
            secret: secret, modifiedAt: later, stored: nil
        )

        #expect(SyncMerge.resolve(local: local, changedAt: later, server: server) == .takeServer)
    }

    // MARK: Setting: last writer wins per key

    @Test func aSettingIsLastWriterWinsPerKey() throws {
        let server = SyncMapping.record(for: SyncSetting(key: "search.engine", value: Data("ddg".utf8)), modifiedAt: now, stored: nil)
        let local = SyncMapping.record(for: SyncSetting(key: "search.engine", value: Data("kagi".utf8)), modifiedAt: later, stored: nil)

        guard case .save(let merged) = SyncMerge.resolve(local: local, changedAt: later, server: server) else {
            Issue.record("expected a save"); return
        }
        #expect(SyncMapping.setting(from: merged)?.value == Data("kagi".utf8))
        #expect(SyncMerge.resolve(local: local, changedAt: earlier, server: server) == .takeServer)
    }

    @Test func aRemovedSettingIsLastWriterWinsToo() {
        let server = SyncMapping.record(for: SyncSamples.setting, modifiedAt: now, stored: nil)
        #expect(SyncMerge.resolve(recordType: "Setting", local: nil, changedAt: later, server: server) == .deleteOnServer)
        #expect(SyncMerge.resolve(recordType: "Setting", local: nil, changedAt: earlier, server: server) == .takeServer)
    }

    // MARK: HistoryEntry and Device: local wins; SyncSecret: server wins

    @Test func historyAndDeviceRecordsKeepTheLocalCopy() {
        for (local, server) in [
            (SyncMapping.record(for: SyncSamples.history, modifiedAt: earlier, stored: nil),
             SyncMapping.record(for: SyncSamples.history, modifiedAt: later, stored: nil)),
            (SyncMapping.record(for: SyncSamples.device, modifiedAt: earlier, stored: nil),
             SyncMapping.record(for: SyncSamples.device, modifiedAt: later, stored: nil))
        ] {
            guard case .save(let merged) = SyncMerge.resolve(local: local, changedAt: earlier, server: server) else {
                Issue.record("expected \(local.recordType) to keep the local copy"); continue
            }
            #expect(merged["modifiedAt"] == .date(earlier))
        }
    }

    @Test func theServersSecretAlwaysWins() {
        let local = SyncSecret(bytes: Data(repeating: 1, count: 32)).record(stored: nil)
        let server = SyncSecret(bytes: Data(repeating: 2, count: 32)).record(stored: nil)
        #expect(SyncMerge.resolve(local: local, changedAt: later, server: server) == .takeServer)
    }

    // MARK: Unknown fields and newer schema versions (§31.9)

    @Test func aLocalWinKeepsTheServersUnknownFieldsAndHigherVersion() {
        var server = SyncMapping.record(for: SyncSamples.space, modifiedAt: earlier, stored: nil)
        server.schemaVersion = 3
        server.fields["accent"] = SyncField(.string("teal"), encrypted: true)
        let local = SyncMapping.record(for: SyncSamples.space, modifiedAt: now, stored: nil)

        guard case .save(let merged) = SyncMerge.resolve(local: local, changedAt: now, server: server) else {
            Issue.record("expected a save"); return
        }
        #expect(merged.schemaVersion == 3)
        #expect(merged.fields["accent"] == SyncField(.string("teal"), encrypted: true))
    }

    @Test func anUnknownRecordTypeIsLeftToTheServer() {
        let server = SyncRecord(recordType: "Boost", recordName: "b", zone: "Boosts", schemaVersion: 2)
        #expect(SyncMerge.resolve(local: server, changedAt: later, server: server) == .takeServer)
        #expect(SyncMerge.resolve(recordType: "Boost", local: nil, changedAt: later, server: server) == .takeServer)
    }

    // MARK: Turning sync on

    @Test func turningSyncOnLetsICloudWinUploadsTheNewAndDropsTheMissing() {
        let fetched = [
            SyncRecord(recordType: "Space", recordName: "both", zone: "Spaces", schemaVersion: 1),
            SyncRecord(recordType: "Space", recordName: "cloudOnly", zone: "Spaces", schemaVersion: 1)
        ]
        let local = [
            SyncMerge.LocalRow(recordName: "both", wasSynced: true),
            SyncMerge.LocalRow(recordName: "neverSynced", wasSynced: false),
            SyncMerge.LocalRow(recordName: "deletedElsewhere", wasSynced: true)
        ]

        let plan = SyncMerge.reconcile(fetched: fetched, local: local)

        #expect(plan.apply.map(\.recordName) == ["both", "cloudOnly"])
        #expect(plan.upload == ["neverSynced"])
        #expect(plan.deleteLocally == ["deletedElsewhere"])
    }

    @Test func theUntouchedSeedSpaceIsDroppedWhenICloudHasSpaces() {
        let seed = Space(name: "Personal", symbolName: "moon.stars.fill", gradient: .defaultSpace)
        let cloud = [SyncMapping.record(for: SyncSamples.space, modifiedAt: now, stored: nil)]

        #expect(SyncMerge.seedSpaceToDrop(local: [seed], spacesWithTabs: [], fetched: cloud) == seed.id)
        #expect(SyncMerge.seedSpaceToDrop(local: [seed], spacesWithTabs: [seed.id], fetched: cloud) == nil)
        #expect(SyncMerge.seedSpaceToDrop(local: [seed], spacesWithTabs: [], fetched: []) == nil)
        var renamed = seed
        renamed.name = "Home"
        #expect(SyncMerge.seedSpaceToDrop(local: [renamed], spacesWithTabs: [], fetched: cloud) == nil)
    }

    /// `seedSpaceToDrop` recognises the Space `seedIfEmpty` actually makes.
    @Test func theSeedNameMatchesWhatTheStoreSeeds() async throws {
        let store = try BrowserStore(path: temporaryDatabasePath())
        try await store.seedIfEmpty()
        #expect(try await store.spaces().map(\.name) == [BrowserStore.seedSpaceName])
    }
}
