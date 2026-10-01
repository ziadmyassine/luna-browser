@testable import BrowserKit
import Foundation
import GRDB
import Testing
import WebKit

/// §18.2: a site keeps the zoom it was given, in every Space, on every Mac, and
/// every page of it opens at that zoom.
@Suite("Per-site zoom (§18.2)")
@MainActor
struct SiteZoomTests {

    private static let secret = SyncSecret(bytes: Data(repeating: 7, count: 32))
    private static let now = Date(timeIntervalSince1970: 1_790_000_000)

    /// Until `check` passes, or two seconds: the saves are detached.
    private func eventually(_ check: () async throws -> Bool) async throws {
        var tries = 0
        while try await !check(), tries < 200 {
            tries += 1
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    // MARK: - The store

    @Test func aZoomIsKeptAndActualSizeForgetsIt() async throws {
        let store = try makeTemporaryStore()
        try await store.setSiteZoom(1.25, host: "read.example")
        #expect(try await store.siteZooms() == ["read.example": 1.25])

        try await store.setSiteZoom(nil, host: "read.example")
        #expect(try await store.siteZooms().isEmpty)
    }

    /// The row carries other answers, so forgetting the zoom must not take them with it.
    @Test func forgettingAZoomLeavesTheSitesOtherAnswers() async throws {
        let store = try makeTemporaryStore()
        try await store.setSitePermission(.savePasswords, allowed: false, host: "bank.example")
        try await store.setSiteZoom(1.5, host: "bank.example")
        try await store.setSiteZoom(nil, host: "bank.example")

        #expect(try await store.siteZooms().isEmpty)
        #expect(try await store.sitePermissions()[.savePasswords] == ["bank.example": false])
    }

    // MARK: - In memory

    @Test func aZoomHoldsInEverySpaceAndIsSaved() async throws {
        let (store, spaceID) = try await makeTemporaryStoreWithSpace()
        let app = SitePermissions()
        app.start(browserStore: store)
        app.forSpace(spaceID).setZoom(1.75, forHost: "Read.Example.")

        #expect(app.zoom(forHost: "read.example") == 1.75)
        #expect(app.forSpace(UUID()).zoom(forHost: "read.example") == 1.75)
        try await eventually { try await store.siteZooms()["read.example"] != nil }
        #expect(try await store.siteZooms() == ["read.example": 1.75])

        app.setZoom(1, forHost: "read.example")
        #expect(app.zoom(forHost: "read.example") == nil)
        try await eventually { try await store.siteZooms().isEmpty }
        #expect(try await store.siteZooms().isEmpty)
    }

    /// §5.6: a private window reads the user's zooms and keeps its own to itself,
    /// including an Actual Size, which must not let the user's zoom show through.
    @Test func aPrivateWindowsZoomStaysInTheWindow() {
        let app = SitePermissions()
        app.setZoom(1.5, forHost: "read.example")
        let scoped = SitePermissions(fallback: app)

        #expect(scoped.zoom(forHost: "read.example") == 1.5)
        scoped.setZoom(2, forHost: "other.example")
        scoped.setZoom(nil, forHost: "read.example")

        #expect(scoped.zoom(forHost: "other.example") == 2)
        #expect(scoped.zoom(forHost: "read.example") ?? 1 == 1)
        #expect(app.zoom(forHost: "other.example") == nil)
        #expect(app.zoom(forHost: "read.example") == 1.5)
    }

    @Test func aStartedInstanceReadsTheStoredZooms() async throws {
        let store = try makeTemporaryStore()
        try await store.setSiteZoom(0.9, host: "small.example")
        let app = SitePermissions()
        app.start(browserStore: store)
        try await eventually { app.zoom(forHost: "small.example") != nil }
        #expect(app.zoom(forHost: "small.example") == 0.9)
    }

    // MARK: - The page

    /// `pageZoom` belongs to the web view, so the next site would inherit it without
    /// `applySiteZoom`.
    @Test func eachDocumentOpensAtItsSitesZoom() async throws {
        let controller = TabController(id: UUID(), dataStore: .nonPersistent())
        controller.activate()
        let webView = try #require(controller.webView)
        controller.sitePermissions.setZoom(1.5, forHost: "zoomed.example")

        webView.loadHTMLString("<p>zoomed</p>", baseURL: URL(string: "https://zoomed.example/a"))
        try await eventually { webView.url?.host() == "zoomed.example" && !webView.isLoading }
        #expect(webView.pageZoom == 1.5)

        webView.loadHTMLString("<p>plain</p>", baseURL: URL(string: "https://plain.example/"))
        try await eventually { webView.url?.host() == "plain.example" && !webView.isLoading }
        #expect(webView.pageZoom == 1)
    }

    // MARK: - Sync

    @Test func aZoomChangeQueuesTheSiteForSync() async throws {
        let store = try makeTemporaryStore()
        try await store.setSyncZone(.sites, enabled: true)
        try await store.setSiteZoom(1.25, host: "read.example")
        #expect(try await store.syncOutbox().map(\.localKey) == ["read.example"])

        let record = try #require(try await store.outgoingRecord(
            "SiteSetting", localKey: "read.example", deviceID: UUID(), secret: Self.secret
        ))
        #expect(record.fields["zoom"] == SyncField(.double(1.25), encrypted: true))
    }

    @Test func anIncomingZoomIsApplied() async throws {
        let store = try makeTemporaryStore()
        var record = SyncMapping.record(
            for: SyncSiteSetting(host: "read.example", zoom: 1.5), secret: Self.secret, modifiedAt: Self.now, stored: nil
        )
        record.systemFields = Data([1])
        try await store.applyRemote(SyncChangeSet(modifications: [record]))
        #expect(try await store.siteZooms() == ["read.example": 1.5])
    }

    /// A record only an older Luna has written has no zoom, and says nothing about it.
    @Test func aRecordWithNoZoomLeavesThisMacsAlone() async throws {
        let store = try makeTemporaryStore()
        try await store.setSiteZoom(1.5, host: "read.example")
        var record = SyncMapping.record(
            for: SyncSiteSetting(host: "read.example", savePasswords: false), secret: Self.secret, modifiedAt: Self.now, stored: nil
        )
        record.systemFields = Data([1])
        try await store.applyRemote(SyncChangeSet(modifications: [record]))

        #expect(try await store.siteZooms() == ["read.example": 1.5])
        #expect(try await store.sitePermissions()[.savePasswords] == ["read.example": false])
    }

    /// Zoom goes with the newer record, so an Actual Size on one Mac reaches the others;
    /// a newer record from a Luna that never writes zoom does not erase this Mac's.
    @Test func theNewerZoomWinsAndAMissingOneLosesToAnyZoom() throws {
        let earlier = Self.now, later = Self.now.addingTimeInterval(60)
        let local = SyncMapping.record(
            for: SyncSiteSetting(host: "read.example", zoom: 1.5), secret: Self.secret, modifiedAt: earlier, stored: nil
        )
        let newerReset = SyncMapping.record(
            for: SyncSiteSetting(host: "read.example", zoom: 1), secret: Self.secret, modifiedAt: later, stored: nil
        )
        #expect(SyncMerge.resolve(local: local, changedAt: earlier, server: newerReset) == .takeServer)

        let olderReset = SyncMapping.record(
            for: SyncSiteSetting(host: "read.example", zoom: 1), secret: Self.secret,
            modifiedAt: earlier.addingTimeInterval(-60), stored: nil
        )
        guard case .save(let kept) = SyncMerge.resolve(local: local, changedAt: earlier, server: olderReset) else {
            Issue.record("expected this Mac's newer zoom to be saved"); return
        }
        #expect(SyncMapping.siteSetting(from: kept)?.zoom == 1.5)

        let newerWithout = SyncMapping.record(
            for: SyncSiteSetting(host: "read.example", savePasswords: false), secret: Self.secret, modifiedAt: later, stored: nil
        )
        guard case .save(let merged) = SyncMerge.resolve(local: local, changedAt: earlier, server: newerWithout) else {
            Issue.record("expected this Mac's zoom to be laid over the record"); return
        }
        let site = try #require(SyncMapping.siteSetting(from: merged))
        #expect(site.zoom == 1.5)
        #expect(site.savePasswords == false)
    }
}
