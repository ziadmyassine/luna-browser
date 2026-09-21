//
//  BrowserSessionLaunchTests.swift
//  LunaTests
//
//  The launch sweep (spec §3.1, §3.2) — the one call that makes store deletion
//  eventually consistent.
//
//  `remove(forIdentifier:)` fails while any live `WKWebView` still uses the
//  store, and a web view goes away when ARC says so rather than when the user
//  clicks Delete. A removal that loses that race is queued in `UserDefaults`
//  and finished on the next launch, when nothing is holding anything — so if
//  the sweep is never called, the queue is written and never read, and the
//  feature is inert while looking implemented. Both halves need proving:
//
//  1. `installLifecycle()` reaches the sweep at all.
//  2. The identifier set it hands over is the live one. That set is the
//     whole decision — everything WebKit lists and the set does not name gets
//     deleted — so an empty or stale set is not a weaker sweep, it is a sweep
//     that takes the user's live cookie jars.
//
//  Neither test can reach the disk, and that is structural rather than
//  careful: `orphanSweepSink` redirects the sweep and switching the guard off
//  is the same act as pointing it somewhere harmless. There is no argument to
//  that API that lets a test call `WKWebsiteDataStore.remove(forIdentifier:)`.
//

import BrowserKit
import XCTest
@testable import Luna

@MainActor
final class BrowserSessionLaunchTests: XCTestCase {

    private let directory = URL.temporaryDirectory.appending(path: "luna-tests-\(UUID().uuidString)")
    private var session: BrowserSession?

    override func tearDown() async throws {
        if let session {
            // The sink outlives the session otherwise, and the lifecycle pass
            // holds a 60-second timer and a memory-pressure source.
            session.orphanSweepSink = nil
            TabLifecycle.uninstall(from: session)
            session.tearDown()
        }
        session = nil
        try? FileManager.default.removeItem(at: directory)
    }

    /// Goal 4. `installLifecycle()` is what `AppDelegate` calls at launch, and
    /// this asserts the whole path through it: that the sweep fires, and that
    /// what it hands over is every live `dataStoreIdentifier` and nothing else.
    func testInstallingTheLifecycleSweepsWithTheLiveIdentifierSet() async throws {
        let store = try BrowserStore(path: directory.appending(path: "luna.sqlite"))
        let session = try await BrowserSession.restored(store: store)
        self.session = session
        // A second Profile, so "the live set" is a set and not a single row that
        // several wrong answers would also satisfy.
        _ = try await session.createSpace(name: "Work")

        var handedOver: Set<UUID>?
        session.orphanSweepSink = { handedOver = $0 }
        session.installLifecycle()

        try await waitUntil("the launch sweep to run") { handedOver != nil }
        let live = try await store.liveDataStoreIdentifiers()
        XCTAssertEqual(live.count, 2, "two Profiles, two stores")
        XCTAssertEqual(handedOver, live, "the sweep keeps exactly the identifiers the database still names")
        XCTAssertFalse(handedOver?.isEmpty ?? true, "an empty set would delete every store on disk")
    }

    /// The guard, from the other side: a test that sets nothing must not sweep,
    /// because the default destination is the real disk. This is the case that
    /// was one line from deleting the owner's cookie jars and reporting it as
    /// orphan recovery.
    func testTheSweepDoesNotRunInATestThatHasNotRedirectedIt() async throws {
        let store = try BrowserStore(path: directory.appending(path: "luna.sqlite"))
        let session = try await BrowserSession.restored(store: store)
        self.session = session

        var reached = false
        // Deliberately not assigned to `session.orphanSweepSink` — this
        // records whether anything called it, and nothing should.
        let unusedSink: (Set<UUID>) async -> Void = { _ in reached = true }
        _ = unusedSink
        session.installLifecycle()

        // Long enough for the detached Task to have run had the guard let it.
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertFalse(reached, "the sweep must not run in a test that has not routed it away from the disk")
        XCTAssertFalse(
            BrowserSession.hasSweptOrphanStores,
            "and it must not consume the once-per-process flag either, or the real launch would skip its sweep"
        )
    }

    private func waitUntil(
        _ what: String,
        timeout: TimeInterval = 5,
        _ condition: () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else { return XCTFail("timed out waiting for \(what)") }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}
