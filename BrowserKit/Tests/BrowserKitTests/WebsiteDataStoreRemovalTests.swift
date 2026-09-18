@testable import BrowserKit
import Foundation
import Testing

// §3.2's retry loop, driven against a store that refuses. The whole reason the loop is
// dependency-injected: the failure it exists for — "a `WKWebView` still holds this store" —
// cannot be produced on demand against real WebKit, and a test that waits eight seconds for
// a real backoff is a test nobody runs.

/// A `WKWebsiteDataStore.allDataStoreIdentifiers` that does as it is told.
@MainActor
final class StubRegistry: WebsiteDataStoreRegistry {

    struct Refusal: Error {}

    var present: Set<UUID>
    /// WebKit's real failure mode: the call errors and the identifier stays listed.
    var removeAlwaysFails = false
    /// The other real failure mode: no error, and the identifier stays listed anyway.
    var removeSilentlyDoesNothing = false
    /// §3.2 step 5 — the store can vanish as a side effect of the fallback clear.
    var clearAlsoRemovesTheStore = false
    var clearThrows = false

    private(set) var removeAttempts: [UUID] = []
    private(set) var clearAttempts: [UUID] = []

    init(present: Set<UUID> = []) {
        self.present = present
    }

    func identifiers() async -> Set<UUID> { present }

    func removeStore(_ identifier: UUID) async throws {
        removeAttempts.append(identifier)
        if removeAlwaysFails { throw Refusal() }
        if removeSilentlyDoesNothing { return }
        present.remove(identifier)
    }

    func clearData(in identifier: UUID) async throws {
        clearAttempts.append(identifier)
        if clearThrows { throw Refusal() }
        if clearAlsoRemovesTheStore { present.remove(identifier) }
    }
}

@MainActor
final class RecordingClock: RemovalBackoffClock {
    private(set) var slept: [Duration] = []
    func sleep(for duration: Duration) async { slept.append(duration) }
}

@MainActor
final class MemoryPendingRemovals: PendingRemovalStorage {
    var stored: Set<UUID>
    private(set) var saves: [Set<UUID>] = []

    init(stored: Set<UUID> = []) { self.stored = stored }

    func load() -> Set<UUID> { stored }
    func save(_ identifiers: Set<UUID>) {
        stored = identifiers
        saves.append(identifiers)
    }
}

@Suite("Website data store removal (§3.2)")
@MainActor
struct WebsiteDataStoreRemovalTests {

    private func makeRemover(
        _ registry: StubRegistry,
        storage: MemoryPendingRemovals = MemoryPendingRemovals(),
        clock: RecordingClock = RecordingClock()
    ) -> WebsiteDataStoreRemover {
        WebsiteDataStoreRemover(registry: registry, storage: storage, clock: clock)
    }

    // MARK: - The happy paths

    @Test func removesAStoreOnTheFirstAttempt() async {
        let identifier = UUID()
        let registry = StubRegistry(present: [identifier])
        let storage = MemoryPendingRemovals()
        let clock = RecordingClock()

        let outcome = await makeRemover(registry, storage: storage, clock: clock).remove(identifier)

        #expect(outcome == .removed)
        #expect(registry.removeAttempts == [identifier])
        // No fallback clear, no backoff, nothing queued: the fast path stays fast.
        #expect(registry.clearAttempts.isEmpty)
        #expect(clock.slept.isEmpty)
        #expect(storage.stored.isEmpty)
    }

    /// WebKit is the registry (§3.1), so "it was already gone" is a real and common answer —
    /// a previous launch's sweep may have finished the job.
    @Test func reportsAStoreWebKitNeverListed() async {
        let registry = StubRegistry(present: [])
        let outcome = await makeRemover(registry).remove(UUID())

        #expect(outcome == .alreadyGone)
        #expect(registry.removeAttempts.isEmpty)
    }

    /// The all-zero identifier never reaches WebKit, from any direction (§3.1).
    @Test func neverHandsTheZeroIdentifierToWebKit() async {
        let registry = StubRegistry(present: [.zero])
        let outcome = await makeRemover(registry).remove(.zero)

        #expect(outcome == .alreadyGone)
        #expect(registry.removeAttempts.isEmpty)
        #expect(registry.clearAttempts.isEmpty)
    }

    // MARK: - The failure path (goal 3)

    /// The whole of §3.2 in one test: try, clear the data as a fallback, back off through
    /// the six documented intervals, and write the identifier down where a database wipe
    /// cannot reach it.
    @Test func clearsDataBacksOffAndQueuesWhenWebKitWillNotLetGo() async {
        let identifier = UUID()
        let registry = StubRegistry(present: [identifier])
        registry.removeAlwaysFails = true
        let storage = MemoryPendingRemovals()
        let clock = RecordingClock()
        let remover = makeRemover(registry, storage: storage, clock: clock)

        let outcome = await remover.remove(identifier)

        // Step 4: the directory survived, but the cookies and logins did not — which is
        // what the user actually asked for.
        #expect(outcome == .deferredAfterClearingData)
        #expect(registry.clearAttempts == [identifier], "the fallback clear runs exactly once, not once per retry")
        // Step 6: the documented backoff, in order, in full.
        #expect(clock.slept == WebsiteDataStoreRemover.backoff)
        #expect(registry.removeAttempts.count == WebsiteDataStoreRemover.backoff.count + 1)
        // Step 7: queued in storage that outlives the database.
        #expect(remover.pendingIdentifiers == [identifier])
        #expect(storage.stored == [identifier])
    }

    /// A silent no-op is indistinguishable from success at the call site, which is why
    /// §3.2 re-checks `allDataStoreIdentifiers` instead of trusting the return.
    @Test func doesNotTrustASilentSuccess() async {
        let identifier = UUID()
        let registry = StubRegistry(present: [identifier])
        registry.removeSilentlyDoesNothing = true
        let remover = makeRemover(registry)

        let outcome = await remover.remove(identifier)

        #expect(outcome == .deferredAfterClearingData)
        #expect(remover.pendingIdentifiers == [identifier])
    }

    /// §3.2 step 5: the identifier can disappear as a side effect of the fallback clear, so
    /// the list is re-read before concluding anything.
    @Test func noticesTheStoreVanishingDuringTheFallbackClear() async {
        let identifier = UUID()
        let registry = StubRegistry(present: [identifier])
        registry.removeAlwaysFails = true
        registry.clearAlsoRemovesTheStore = true
        let storage = MemoryPendingRemovals()
        let clock = RecordingClock()
        let remover = makeRemover(registry, storage: storage, clock: clock)

        let outcome = await remover.remove(identifier)

        #expect(outcome == .removed)
        #expect(clock.slept.isEmpty, "no backoff once the store is actually gone")
        #expect(remover.pendingIdentifiers.isEmpty)
        #expect(storage.stored.isEmpty)
    }

    /// Both fallbacks failing is still not a thrown error: the caller is deleting a Space and
    /// a directory that will be gone on the next launch must not fail that.
    @Test func queuesWithoutClearingWhenEvenTheFallbackFails() async {
        let identifier = UUID()
        let registry = StubRegistry(present: [identifier])
        registry.removeAlwaysFails = true
        registry.clearThrows = true
        let remover = makeRemover(registry)

        #expect(await remover.remove(identifier) == .deferred)
        #expect(remover.pendingIdentifiers == [identifier])
    }

    /// The queue is read back at construction — that is what makes it survive a relaunch.
    @Test func loadsTheQueueOnInit() {
        let queued = UUID()
        let remover = makeRemover(StubRegistry(), storage: MemoryPendingRemovals(stored: [queued]))
        #expect(remover.pendingIdentifiers == [queued])
    }

    /// `UserDefaults`, not GRDB (§3.2 step 7): the queue has to survive the database.
    @Test func roundTripsTheQueueThroughUserDefaults() throws {
        let suite = try #require(UserDefaults(suiteName: "luna.tests.\(UUID().uuidString)"))
        defer { suite.removePersistentDomain(forName: suite.description) }
        let storage = UserDefaultsPendingRemovals(defaults: suite)
        let identifiers: Set<UUID> = [UUID(), UUID()]

        storage.save(identifiers)
        #expect(storage.load() == identifiers)

        storage.save([])
        #expect(storage.load().isEmpty)
        #expect(suite.object(forKey: UserDefaultsPendingRemovals.key) == nil)
    }

    // MARK: - The orphan sweep (goal 4)

    /// WebKit is the registry, so the diff is the whole algorithm.
    @Test func sweepsStoresNoProfileNames() async {
        let live = UUID()
        let orphan = UUID()
        let registry = StubRegistry(present: [live, orphan])
        let remover = makeRemover(registry)

        await remover.sweepOrphans(keeping: [live])

        #expect(registry.present == [live])
        #expect(registry.removeAttempts == [orphan])
        #expect(remover.pendingIdentifiers.isEmpty)
    }

    /// The sweep is also the drain: an identifier queued by a failed `remove` is finished
    /// here, on a later launch, which is the entire reason the queue exists.
    @Test func drainsThePendingQueue() async {
        let queued = UUID()
        let registry = StubRegistry(present: [queued])
        let storage = MemoryPendingRemovals(stored: [queued])
        let remover = makeRemover(registry, storage: storage)

        await remover.sweepOrphans(keeping: [])

        #expect(registry.present.isEmpty)
        #expect(remover.pendingIdentifiers.isEmpty)
        #expect(storage.stored.isEmpty)
    }

    /// A queue that only grows is a leak. An identifier WebKit no longer lists, or one a live
    /// profile has reclaimed, leaves the queue.
    @Test func forgetsQueuedIdentifiersThatAreNoLongerOrphans() async {
        let vanished = UUID()
        let reclaimed = UUID()
        let registry = StubRegistry(present: [reclaimed])
        let storage = MemoryPendingRemovals(stored: [vanished, reclaimed])
        let remover = makeRemover(registry, storage: storage)

        await remover.sweepOrphans(keeping: [reclaimed])

        #expect(remover.pendingIdentifiers.isEmpty)
        #expect(registry.present == [reclaimed], "a store a live profile still names is never swept")
        #expect(registry.removeAttempts.isEmpty)
    }

    /// Single pass, no backoff: a stray that refuses today is still listed tomorrow, and a
    /// launch must not sit for half a minute behind four stubborn orphans.
    @Test func doesNotBackOffDuringTheSweep() async {
        let orphan = UUID()
        let registry = StubRegistry(present: [orphan])
        registry.removeAlwaysFails = true
        let storage = MemoryPendingRemovals()
        let clock = RecordingClock()
        let remover = makeRemover(registry, storage: storage, clock: clock)

        await remover.sweepOrphans(keeping: [])

        #expect(clock.slept.isEmpty)
        #expect(registry.removeAttempts == [orphan])
        #expect(registry.clearAttempts.isEmpty, "clearing an orphan would re-create the directory it is removing")
        #expect(remover.pendingIdentifiers == [orphan], "still queued, retried next launch")
    }
}
