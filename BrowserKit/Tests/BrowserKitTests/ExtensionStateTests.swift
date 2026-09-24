import Foundation
import Testing
@testable import BrowserKit

/// §16.3 and §16.6's model: what survives a relaunch, and what a Space's
/// extensions are told when its tabs and windows change.
@Suite("Extension state (§16.3, §16.6)")
struct ExtensionStateTests {

    // MARK: - Persistence

    @Test func remembersGrantsAndDenialsPerSpaceAcrossAReopen() async throws {
        let path = temporaryDatabasePath()
        let (spaceA, spaceB): (UUID, UUID)
        let grants = ExtensionGrants(
            grantedPermissions: ["storage"], deniedPermissions: ["tabs"],
            grantedPatterns: ["https://example.com/*"], deniedPatterns: ["<all_urls>"]
        )
        do {
            let store = try BrowserStore(path: path)
            try await store.seedIfEmpty()
            spaceA = try await store.spaces()[0].id
            spaceB = try await store.insertSpace(named: "Work")
            try await store.saveExtension(
                ExtensionRecord(id: "abcdefghijklmnopabcdefghijklmnop", source: .webStore),
                in: ExtensionSpaceRecord(extensionID: "abcdefghijklmnopabcdefghijklmnop", spaceID: spaceA, isEnabled: true, grants: grants)
            )
            try await store.saveExtensionSpace(ExtensionSpaceRecord(
                extensionID: "abcdefghijklmnopabcdefghijklmnop", spaceID: spaceB, isEnabled: false, grants: ExtensionGrants()
            ))
        }

        let reopened = try BrowserStore(path: path)
        let all = try await reopened.installedExtensions()
        #expect(all.count == 1)
        let (record, rows) = try #require(all.first)
        #expect(record.source == .webStore)
        let byspace = Dictionary(uniqueKeysWithValues: rows.map { ($0.spaceID, $0) })
        #expect(byspace[spaceA]?.grants == grants)
        #expect(byspace[spaceA]?.isEnabled == true)
        #expect(byspace[spaceB]?.isEnabled == false)
    }

    @Test func forgetsEverythingOnUninstallAndASpacesRowsWithTheSpace() async throws {
        let (store, spaceA) = try await makeTemporaryStoreWithSpace()
        let spaceB = try await store.insertSpace(named: "Work")
        for id in ["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"] {
            try await store.saveExtension(
                ExtensionRecord(id: id, source: .local),
                in: ExtensionSpaceRecord(extensionID: id, spaceID: spaceA, isEnabled: true, grants: ExtensionGrants())
            )
            try await store.saveExtensionSpace(
                ExtensionSpaceRecord(extensionID: id, spaceID: spaceB, isEnabled: true, grants: ExtensionGrants())
            )
        }

        try await store.deleteExtension(id: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
        try await store.delete(spaceID: spaceB)

        let all = try await store.installedExtensions()
        #expect(all.map(\.0.id) == ["bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"])
        #expect(all.first?.1.map(\.spaceID) == [spaceA])
    }

    // MARK: - Identity

    /// Extension pages present as the Chrome the rest of Luna claims to be,
    /// and the version cannot drift from `chromeUserAgent`.
    @Test func extensionPagesClaimTheSameChromeAsTheChromeUserAgent() {
        let major = WebViewFactory.chromeMajorVersion
        #expect(!major.isEmpty && major.allSatisfy(\.isNumber))
        #expect(WebViewFactory.chromeUserAgent.contains("Chrome/\(major).0.0.0 Safari/537.36"))
        #expect(WebViewFactory.extensionApplicationNameForUserAgent == "Chrome/\(major).0.0.0 Safari/537.36")
        #expect(!WebViewFactory.extensionApplicationNameForUserAgent.contains("Luna"))
    }

    /// Derived, so it needs no column; distinct, so a wipe of it never touches
    /// the sites' own store.
    @Test func derivesAStableSeparateBackgroundStorePerSpace() {
        let space = UUID()
        let background = ExtensionHost.backgroundStoreIdentifier(forSpaceStore: space)
        #expect(background == ExtensionHost.backgroundStoreIdentifier(forSpaceStore: space))
        #expect(background != space)
        #expect(background != ExtensionHost.backgroundStoreIdentifier(forSpaceStore: UUID()))
    }

    // MARK: - What extensions are told

    private let windowA = UUID(), windowB = UUID()
    private let tab1 = UUID(), tab2 = UUID(), tab3 = UUID()

    @Test func announcesWindowsAndTabsOnFirstSight() {
        let events = ExtensionSnapshot.events(
            from: ExtensionSnapshot(),
            to: ExtensionSnapshot(windows: [windowA], focused: windowA, tabs: [tab1, tab2], activeTab: tab2)
        )
        #expect(events == [
            .openWindow(windowA), .openTab(tab1), .openTab(tab2),
            .activateTab(tab2, previous: nil), .focusWindow(windowA)
        ])
    }

    /// §3.6: hibernation changes nothing an extension can see, so it says nothing.
    @Test func saysNothingWhenNothingItCanSeeChanged() {
        let snapshot = ExtensionSnapshot(windows: [windowA], focused: windowA, tabs: [tab1, tab2], activeTab: tab1)
        #expect(ExtensionSnapshot.events(from: snapshot, to: snapshot).isEmpty)
    }

    @Test func closingATabIsNotAMoveForTheOthers() {
        let old = ExtensionSnapshot(windows: [windowA], tabs: [tab1, tab2, tab3], activeTab: tab1)
        let new = ExtensionSnapshot(windows: [windowA], tabs: [tab1, tab3], activeTab: tab1)
        #expect(ExtensionSnapshot.events(from: old, to: new) == [.closeTab(tab2)])
    }

    @Test func reportsAReorderAsMoves() {
        let old = ExtensionSnapshot(windows: [windowA], tabs: [tab1, tab2, tab3])
        let new = ExtensionSnapshot(windows: [windowA], tabs: [tab2, tab1, tab3])
        #expect(ExtensionSnapshot.events(from: old, to: new) == [
            .moveTab(tab2, from: 1, oldWindow: windowA), .moveTab(tab1, from: 0, oldWindow: windowA)
        ])
    }

    /// The Space's tabs live in its first window; when that window leaves the
    /// Space they move to the next one, and the old window closes last.
    @Test func movesTheTabsWhenTheirWindowLeavesTheSpace() {
        let old = ExtensionSnapshot(windows: [windowA, windowB], focused: windowA, tabs: [tab1], activeTab: tab1)
        let new = ExtensionSnapshot(windows: [windowB], focused: nil, tabs: [tab1], activeTab: tab1)
        #expect(ExtensionSnapshot.events(from: old, to: new) == [
            .moveTab(tab1, from: 0, oldWindow: windowA), .focusWindow(nil), .closeWindow(windowA)
        ])
    }

    @Test func tellsTheNewActiveTabWhichOneItReplaced() {
        let old = ExtensionSnapshot(windows: [windowA], tabs: [tab1, tab2], activeTab: tab1)
        let new = ExtensionSnapshot(windows: [windowA], tabs: [tab1, tab2], activeTab: tab2)
        #expect(ExtensionSnapshot.events(from: old, to: new) == [.activateTab(tab2, previous: tab1)])
    }
}

extension BrowserStore {
    /// A second Space, for a test that needs rows in two.
    func insertSpace(named name: String) async throws -> UUID {
        let space = Space(name: name, symbolName: "circle", gradient: .defaultSpace, order: 1)
        try await upsert(space)
        return space.id
    }
}
