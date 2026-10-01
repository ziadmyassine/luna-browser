@testable import BrowserKit
import Foundation
import GRDB
import Testing
import WebKit

/// A site's camera, microphone, location, local-network and pop-up answers belong to one
/// Space; Picture in Picture, the password offer and the blocking exemptions hold in all
/// of them (`BrowserStore.SitePermission.isPerSpace`, `v14`).
@Suite("Per-Space site answers")
@MainActor
struct SpaceSitePermissionsTests {

    private static func space(_ name: String) -> Space {
        Space(name: name, symbolName: "circle", gradient: .defaultSpace)
    }

    private struct Fixture {
        var store: BrowserStore
        var app: SitePermissions
        var work: UUID
        var personal: UUID
    }

    /// Two Spaces in one store, and an app instance reading and writing it.
    private func twoSpaces() async throws -> Fixture {
        let store = try makeTemporaryStore()
        let work = Self.space("Work"), personal = Self.space("Personal")
        try await store.upsert(work)
        try await store.upsert(personal)
        let app = SitePermissions()
        app.start(browserStore: store)
        return Fixture(store: store, app: app, work: work.id, personal: personal.id)
    }

    /// Until `check` passes, or two seconds: the saves are detached.
    private func eventually(_ check: () async throws -> Bool) async throws {
        var tries = 0
        while try await !check(), tries < 200 {
            tries += 1
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func anAnswerInOneSpaceIsNotGivenInAnother() async throws {
        let fixture = try await twoSpaces()
        let (store, app, work, personal) = (fixture.store, fixture.app, fixture.work, fixture.personal)
        app.forSpace(work).setAllowed(true, .camera, forHost: "meet.example")
        app.forSpace(work).setAllowed(true, .popups, forHost: "meet.example")

        #expect(app.forSpace(work).answer(.camera, forHost: "meet.example") == true)
        #expect(app.forSpace(personal).answer(.camera, forHost: "meet.example") == nil, "Personal is still asked")
        #expect(!app.forSpace(personal).isAllowed(.popups, forHost: "meet.example"))
        #expect(app.answer(.camera, forHost: "meet.example") == nil)

        try await eventually { try await store.spaceSitePermissions()[work]?[.popups] != nil }
        let saved = try await store.spaceSitePermissions()
        #expect(saved[work]?[.camera] == ["meet.example": true])
        #expect(saved[work]?[.popups] == ["meet.example": true])
        #expect(saved[personal] == nil)

        // Read back at the next launch, still only in Work.
        let relaunched = SitePermissions()
        relaunched.start(browserStore: store)
        try await eventually { relaunched.forSpace(work).answer(.camera, forHost: "meet.example") != nil }
        #expect(relaunched.forSpace(work).answer(.camera, forHost: "meet.example") == true)
        #expect(relaunched.forSpace(personal).answer(.camera, forHost: "meet.example") == nil)
    }

    @Test func theSharedAnswersHoldInEverySpace() async throws {
        let fixture = try await twoSpaces()
        let (store, app, work, personal) = (fixture.store, fixture.app, fixture.work, fixture.personal)
        app.forSpace(work).setAllowed(false, .savePasswords, forHost: "bank.example")
        app.forSpace(personal).setAllowed(false, .automaticPictureInPicture, forHost: "video.example")

        for scope in [app, app.forSpace(work), app.forSpace(personal)] {
            #expect(!scope.isAllowed(.savePasswords, forHost: "bank.example"))
            #expect(!scope.isAllowed(.automaticPictureInPicture, forHost: "video.example"))
        }
        try await eventually { try await store.sitePermissions()[.automaticPictureInPicture] != nil }
        let saved = try await store.sitePermissions()
        #expect(saved[.savePasswords] == ["bank.example": false])
        #expect(saved[.automaticPictureInPicture] == ["video.example": false])
        #expect(try await store.spaceSitePermissions().isEmpty)
    }

    /// The blocking exemption is `ContentBlocker`'s, and a Space's instance is not a
    /// private one, so turning blocking off in one Space turns it off in all of them.
    @Test func theBlockingExemptionHoldsInEverySpace() {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "luna-rules/\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let blocker = ContentBlocker(store: WKContentRuleListStore(url: directory)!, defaults: scratchDefaults())
        let app = SitePermissions()
        let work = app.forSpace(UUID()), personal = app.forSpace(UUID())

        blocker.setDisabled(true, forHost: "news.example", in: work)
        #expect(blocker.isDisabled(forHost: "news.example", in: personal))
        #expect(blocker.isDisabled(forHost: "news.example"))
    }

    @Test func aSpacesDataStoreAnswersWithThatSpace() {
        let id = UUID()
        let dataStore = WKWebsiteDataStore.nonPersistent()
        SitePermissions.bind(dataStore, toSpace: id)
        let scope = SitePermissions.scope(for: dataStore)
        #expect(scope === SitePermissions.shared.forSpace(id))
        #expect(scope.spaceID == id)
        #expect(!scope.isPrivate)
        #expect(SitePermissions.scope(for: .default()) === SitePermissions.shared)
    }

    /// A private window is no Space's jar: it keeps its own answers and reads only the
    /// ones that hold everywhere.
    @Test func aPrivateWindowReadsNoSpacesAnswers() {
        let app = SitePermissions()
        let work = app.forSpace(UUID())
        work.setAllowed(true, .camera, forHost: "meet.example")
        work.setAllowed(false, .savePasswords, forHost: "bank.example")
        let scoped = SitePermissions(fallback: app)

        #expect(scoped.answer(.camera, forHost: "meet.example") == nil)
        #expect(!scoped.isAllowed(.savePasswords, forHost: "bank.example"))

        scoped.setAllowed(false, .camera, forHost: "meet.example")
        #expect(scoped.answer(.camera, forHost: "meet.example") == false)
        #expect(work.answer(.camera, forHost: "meet.example") == true)
        #expect(scoped.forSpace(UUID()) === scoped)
    }

    @Test func deletingASpaceDeletesItsAnswers() async throws {
        let fixture = try await twoSpaces()
        let (store, work, personal) = (fixture.store, fixture.work, fixture.personal)
        try await store.setSitePermission(.camera, allowed: true, host: "meet.example", inSpace: work)
        try await store.setSitePermission(.camera, allowed: false, host: "meet.example", inSpace: personal)

        try await store.delete(spaceID: work)

        #expect(try await store.spaceSitePermissions() == [personal: [.camera: ["meet.example": false]]])
        await #expect(throws: (any Error).self) {
            try await store.setSitePermission(.camera, allowed: true, host: "meet.example", inSpace: work)
        }
    }

    // MARK: - v14

    /// Every answer given before the upgrade holds in every Space after it, and the
    /// columns leave `siteSettings` without taking the shared answers or sync's trigger.
    @Test func v14CopiesEveryAnswerIntoEverySpace() async throws {
        let path = temporaryDatabasePath()
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        let work = Self.space("Work"), personal = Self.space("Personal")
        do {
            let pool = try DatabasePool(path: path.path)
            try Schema.migrator().migrate(pool, upTo: "v13")
            try await pool.write { db in
                try work.insert(db)
                try personal.insert(db)
                try db.execute(
                    sql: """
                    INSERT INTO siteSettings (host, updatedAt, camera, microphone, popups, localNetwork, savePasswords)
                    VALUES ('meet.example', ?, 1, 0, NULL, NULL, NULL),
                           ('printer.example', ?, NULL, NULL, 1, 1, 0),
                           ('zoomed.example', ?, NULL, NULL, NULL, NULL, NULL)
                    """,
                    arguments: [Date(), Date(), Date()]
                )
            }
            try pool.close()
        }

        let store = try BrowserStore(path: path)
        let expected: [BrowserStore.SitePermission: [String: Bool]] = [
            .camera: ["meet.example": true],
            .microphone: ["meet.example": false],
            .popups: ["printer.example": true],
            .localNetwork: ["printer.example": true]
        ]
        #expect(try await store.spaceSitePermissions() == [work.id: expected, personal.id: expected])
        #expect(try await store.sitePermissions() == [.savePasswords: ["printer.example": false]])

        let (columns, trigger) = try await store.pool.read { db in
            (
                Set(try db.columns(in: "siteSettings").map(\.name)),
                try String.fetchOne(db, sql: "SELECT sql FROM sqlite_master WHERE name = 'sync_siteSettings_update'")
            )
        }
        // `userAgent` is `v15`'s.
        #expect(columns == [
            "host", "zoom", "updatedAt", "automaticPictureInPicture", "savePasswords", "blockingDisabled", "insecureAllowed",
            "userAgent"
        ])
        let update = try #require(trigger, "sync's update trigger is back")
        #expect(update.contains("savePasswords"))
        #expect(!update.contains("popups"))
        // Moving answers between tables is not a change another Mac has to hear about.
        #expect(try await store.syncOutbox().isEmpty)
    }

    @Test func v14CreatesThePerSpaceTable() async throws {
        let store = try makeTemporaryStore()
        let (columns, foreignKeys) = try await store.pool.read { db in
            (
                Dictionary(uniqueKeysWithValues: try db.columns(in: "spaceSitePermissions").map { ($0.name, $0) }),
                try db.foreignKeys(on: "spaceSitePermissions")
            )
        }
        #expect(Set(columns.keys) == ["spaceID", "host", "camera", "microphone", "location", "localNetwork", "popups"])
        // Nullable: absent is "nobody has answered", which is not a refusal.
        for permission in BrowserStore.SitePermission.allCases where permission.isPerSpace {
            let column = try #require(columns[permission.rawValue], "no column for \(permission)")
            #expect(column.type == "BOOLEAN")
            #expect(!column.isNotNull)
        }
        #expect(foreignKeys.map(\.destinationTable) == ["spaces"])
    }
}
