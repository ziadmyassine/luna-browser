@testable import BrowserKit
import Foundation
import Testing

/// Row ↔ `SyncRecord`, one mapper per record type (docs/SYNC-PLAN.md §1–§2, S4).
@Suite("Sync record mapping (§31.2)")
struct SyncMappingTests {

    private let now = SyncSamples.now

    @Test func aSpaceRoundTrips() throws {
        let space = SyncSamples.space
        let record = SyncMapping.record(for: space, modifiedAt: now, stored: nil)

        #expect(record.recordType == "Space")
        #expect(record.recordName == space.id.uuidString)
        #expect(record.zone == "Spaces")
        let back = try #require(SyncMapping.space(from: record))
        #expect(back.id == space.id)
        #expect(back.name == space.name)
        #expect(back.symbolName == space.symbolName)
        #expect(back.gradient == space.gradient)
        #expect(back.imageData == space.imageData)
        #expect(back.order == space.order)
    }

    /// `dataStoreIdentifier` names this Mac's cookie jar and never syncs (§3).
    @Test func anIncomingSpaceGetsItsOwnCookieJar() throws {
        let record = SyncMapping.record(for: SyncSamples.space, modifiedAt: now, stored: nil)
        #expect(record.fields.keys.contains { $0.localizedCaseInsensitiveContains("dataStore") } == false)
        let back = try #require(SyncMapping.space(from: record))
        #expect(back.dataStoreIdentifier != SyncSamples.space.dataStoreIdentifier)
        #expect(back.hasUsableDataStoreIdentifier)
    }

    @Test func aTabGroupRoundTrips() throws {
        let group = SyncSamples.group
        let record = SyncMapping.record(for: group, modifiedAt: now, stored: nil)

        #expect(record.recordType == "TabGroup")
        #expect(record.recordName == group.id.uuidString)
        #expect(record.fields["isCollapsed"] == nil, "folding is this Mac's")
        var back = try #require(SyncMapping.tabGroup(from: record))
        back.isCollapsed = group.isCollapsed
        #expect(back == group)
    }

    @Test func aTabRoundTripsItsSyncedFields() throws {
        let tab = SyncSamples.tab
        let record = SyncMapping.record(for: tab, modifiedAt: now, stored: nil)

        #expect(record.recordType == "Tab")
        #expect(record.recordName == tab.id.uuidString)
        #expect(Set(record.fields.keys) == [
            "modifiedAt", "spaceID", "groupID", "kind", "position", "createdAt", "archivedAt",
            "url", "title", "customTitle", "customSymbolName", "pinnedURL"
        ], "interactionState, lastActiveAt, hasUnread, faviconKey, themeColor, isDormant and parentTabID stay on this Mac")
        let back = try #require(SyncMapping.tab(from: record))
        #expect(back.id == tab.id)
        #expect(back.spaceID == tab.spaceID)
        #expect(back.groupID == tab.groupID)
        #expect(back.kind == tab.kind)
        #expect(back.order == tab.order)
        #expect(back.createdAt == tab.createdAt)
        #expect(back.archivedAt == tab.archivedAt)
        #expect(back.url == tab.url)
        #expect(back.title == tab.title)
        #expect(back.customTitle == tab.customTitle)
        #expect(back.customSymbolName == tab.customSymbolName)
        #expect(back.pinnedURL == tab.pinnedURL)
    }

    /// A rename cleared on one Mac has to clear on the others, so a known field with no
    /// value is written as a removal rather than left out.
    @Test func aTabsEmptyOptionalFieldsAreWrittenAsRemovals() throws {
        var tab = SyncSamples.tab
        tab.customTitle = nil
        tab.groupID = nil
        tab.archivedAt = nil
        let record = SyncMapping.record(for: tab, modifiedAt: now, stored: nil)

        #expect(record.fields["customTitle"] == SyncField(nil, encrypted: true))
        #expect(record.fields["groupID"] == SyncField(nil))
        #expect(record.fields["archivedAt"] == SyncField(nil))
        let back = try #require(SyncMapping.tab(from: record))
        #expect(back.customTitle == nil)
        #expect(back.groupID == nil)
        #expect(back.archivedAt == nil)
    }

    @Test func aSiteSettingRoundTripsUnderItsHMACName() throws {
        let site = SyncSamples.site
        let record = SyncMapping.record(for: site, secret: SyncSamples.secret, modifiedAt: now, stored: nil)

        #expect(record.recordType == "SiteSetting")
        #expect(record.zone == "Sites")
        #expect(record.recordName == SyncSamples.secret.siteRecordName(forHost: site.host))
        #expect(try #require(SyncMapping.siteSetting(from: record)) == site)
    }

    /// Tri-state: absent is unset, and an unset flag is left out rather than cleared, so
    /// it never erases an answer another Mac gave (§3, SiteSetting).
    @Test func anUnsetSiteFlagIsLeftOut() throws {
        let site = SyncSiteSetting(host: "example.com", localNetwork: false)
        let record = SyncMapping.record(for: site, secret: SyncSamples.secret, modifiedAt: now, stored: nil)

        #expect(record.fields["localNetwork"] == SyncField(.int(0), encrypted: true))
        #expect(record.fields["popups"] == nil)
        #expect(record.fields["zoom"] == nil, "reserved until per-site zoom is persisted")
        #expect(try #require(SyncMapping.siteSetting(from: record)) == site)
    }

    /// `blockingDisabled` and `insecureAllowed` follow the newer record (§3), so off is
    /// written as 0 like on is written as 1: an off that is left out could never switch
    /// another Mac's on back off.
    @Test func theTwoBlockingFlagsAreAlwaysWritten() throws {
        let off = SyncSiteSetting(host: "example.com", blockingDisabled: false, insecureAllowed: false)
        let offRecord = SyncMapping.record(for: off, secret: SyncSamples.secret, modifiedAt: now, stored: nil)
        #expect(offRecord.fields["blockingDisabled"] == SyncField(.int(0), encrypted: true))
        #expect(offRecord.fields["insecureAllowed"] == SyncField(.int(0), encrypted: true))
        #expect(try #require(SyncMapping.siteSetting(from: offRecord)) == off)

        let on = SyncSiteSetting(host: "example.com", blockingDisabled: true, insecureAllowed: true)
        let onRecord = SyncMapping.record(for: on, secret: SyncSamples.secret, modifiedAt: now, stored: nil)
        #expect(onRecord.fields["blockingDisabled"] == SyncField(.int(1), encrypted: true))
        #expect(try #require(SyncMapping.siteSetting(from: onRecord)) == on)
    }

    @Test func aSettingRoundTripsUnderItsKey() throws {
        let setting = SyncSamples.setting
        let record = SyncMapping.record(for: setting, modifiedAt: now, stored: nil)

        #expect(record.recordType == "Setting")
        #expect(record.zone == "Settings")
        #expect(record.recordName == "luna.shortcut.newTab")
        #expect(try #require(SyncMapping.setting(from: record)) == setting)
    }

    @Test func aHistoryEntryRoundTrips() throws {
        let entry = SyncSamples.history
        let record = SyncMapping.record(for: entry, modifiedAt: now, stored: nil)

        #expect(record.recordType == "HistoryEntry")
        #expect(record.zone == "History")
        #expect(record.recordName == "\(entry.deviceID.uuidString)-42")
        #expect(try #require(SyncMapping.historyEntry(from: record)) == entry)
    }

    @Test func aDeviceRoundTrips() throws {
        let device = SyncSamples.device
        let record = SyncMapping.record(for: device, modifiedAt: now, stored: nil)

        #expect(record.recordType == "Device")
        #expect(record.zone == "Devices")
        #expect(record.recordName == device.id.uuidString)
        #expect(try #require(SyncMapping.device(from: record)) == device)
    }

    /// User content is encrypted; only structure travels plain (§2's encryption rule).
    @Test func userContentTravelsOnlyInEncryptedFields() {
        let structural: Set = ["modifiedAt", "position", "spaceID", "groupID", "kind", "createdAt", "archivedAt"]
        let sensitive: Set = ["url", "title", "host", "name", "value", "tabs", "visits", "secret"]
        for record in SyncSamples.allRecords {
            for (key, field) in record.fields {
                if sensitive.contains(key) {
                    #expect(field.isEncrypted, "\(record.recordType).\(key) must be encrypted")
                }
                if !field.isEncrypted {
                    #expect(structural.contains(key), "\(record.recordType).\(key) travels plain but is not structure")
                }
            }
        }
    }

    @Test func aNewerSchemaVersionIsKept() {
        var stored = SyncMapping.record(for: SyncSamples.space, modifiedAt: now, stored: nil)
        stored.schemaVersion = 3
        stored.systemFields = Data([9, 9])

        let record = SyncMapping.record(for: SyncSamples.space, modifiedAt: now, stored: stored)

        #expect(record.schemaVersion == 3)
        #expect(record.systemFields == Data([9, 9]), "the write starts from the stored system fields")
        #expect(SyncMapping.record(for: SyncSamples.space, modifiedAt: now, stored: nil).schemaVersion == 1)
    }

    @Test func anUnknownFieldIsNeverSet() {
        var stored = SyncMapping.record(for: SyncSamples.tab, modifiedAt: now, stored: nil)
        stored.fields["future"] = SyncField(.string("a newer Luna's"), encrypted: true)

        let record = SyncMapping.record(for: SyncSamples.tab, modifiedAt: now, stored: stored)

        #expect(record.fields["future"] == nil, "neither set nor cleared: the server keeps it")
    }

    @Test func aRecordOfAnotherTypeDoesNotDecode() {
        let tabRecord = SyncMapping.record(for: SyncSamples.tab, modifiedAt: now, stored: nil)
        #expect(SyncMapping.space(from: tabRecord) == nil)
        #expect(SyncMapping.siteSetting(from: tabRecord) == nil)
    }
}

/// One fully populated value of every synced type, so each mapper writes every field it
/// knows. `SyncSchemaFileTests` checks the same records against `Config/CloudKit/Schema.ckdb`.
enum SyncSamples {

    static let now = Date(timeIntervalSince1970: 1_790_000_000)
    static let secret = SyncSecret(bytes: Data(repeating: 7, count: 32))
    static let spaceID = UUID()

    static let space = Space(
        id: spaceID, name: "Work", symbolName: "briefcase", gradient: .defaultSpace,
        imageData: Data([0x89, 0x50, 0x4E, 0x47]), order: 2
    )

    static let group = TabGroup(spaceID: spaceID, name: "Reading", symbolName: "book", kind: .pinned, isCollapsed: true, order: 1)

    static let tab = Tab(
        spaceID: spaceID, kind: .pinned, url: URL(string: "https://example.com/a")!, title: "Example",
        faviconKey: "fav", themeColor: RGBA(r: 1, g: 0, b: 0, a: 1),
        createdAt: Date(timeIntervalSince1970: 1_780_000_000), lastActiveAt: now,
        archivedAt: Date(timeIntervalSince1970: 1_785_000_000), parentTabID: UUID(),
        interactionState: Data([1]), hasUnread: true, order: 3,
        pinnedURL: URL(string: "https://example.com/")!, customTitle: "Mine", customSymbolName: "star",
        groupID: group.id, isDormant: true
    )

    static let site = SyncSiteSetting(
        host: "example.com", automaticPictureInPicture: true, localNetwork: false, savePasswords: false,
        popups: true, blockingDisabled: true, insecureAllowed: true
    )

    static let setting = SyncSetting(key: "luna.shortcut.newTab", value: Data("<plist/>".utf8))

    static let history = SyncHistoryEntry(
        deviceID: UUID(), placeID: 42, url: URL(string: "https://example.com/b")!, title: "B",
        visits: [SyncHistoryEntry.Visit(spaceID: spaceID, at: now, kind: "typed")]
    )

    static let device = SyncDevice(
        id: UUID(), name: "Studio",
        tabs: [SyncDevice.OpenTab(spaceID: spaceID, url: URL(string: "https://example.com/c")!, title: "C")]
    )

    static var allRecords: [SyncRecord] {
        [
            SyncMapping.record(for: space, modifiedAt: now, stored: nil),
            SyncMapping.record(for: group, modifiedAt: now, stored: nil),
            SyncMapping.record(for: tab, modifiedAt: now, stored: nil),
            SyncMapping.record(for: site, secret: secret, modifiedAt: now, stored: nil),
            SyncMapping.record(for: setting, modifiedAt: now, stored: nil),
            SyncMapping.record(for: history, modifiedAt: now, stored: nil),
            SyncMapping.record(for: device, modifiedAt: now, stored: nil),
            secret.record(stored: nil)
        ]
    }
}
