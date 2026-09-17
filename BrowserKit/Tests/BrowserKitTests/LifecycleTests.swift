import Foundation
import Testing
@testable import BrowserKit

// The four things in §19.2 / §6.3 / §6.8 that break silently: a tab that should
// have stayed awake, a tab that never goes to sleep, a snapshot cache that eats
// the disk, and a pinned tab that archives itself overnight.

@Suite("Hibernation policy (§19.2)")
struct HibernationPolicyTests {

    private let now = Date()
    private let policy = HibernationPolicy(liveBudget: 4, idleThreshold: 300)

    /// ids[0] is active and most recently used; ids[5] is the coldest.
    private func scenario(
        count: Int = 6,
        idle: TimeInterval = 600,
        audible: Set<Int> = [],
        dirty: Set<Int> = []
    ) -> (ids: [UUID], live: [TabActivity]) {
        let ids = (0..<count).map { _ in UUID() }
        let live = ids.enumerated().map { index, id in
            TabActivity(
                id: id,
                lastActiveAt: now.addingTimeInterval(-idle),
                isAudible: audible.contains(index),
                hasUnsavedInput: dirty.contains(index)
            )
        }
        return (ids, live)
    }

    @Test("the active tab and the last three stay awake; the rest go")
    func keepsActivePlusThree() {
        let (ids, live) = scenario()
        let doomed = policy.tabsToHibernate(live: live, mru: ids, activeID: ids[0], now: now)
        #expect(Set(doomed) == Set(ids[4...]))
    }

    /// The budget is not a countdown: a tab inside it never hibernates on age.
    @Test("a tab inside the budget is never hibernated for being idle")
    func budgetBeatsIdle() {
        let (ids, live) = scenario(count: 4, idle: 60 * 60 * 24)
        #expect(policy.tabsToHibernate(live: live, mru: ids, activeID: ids[0], now: now).isEmpty)
    }

    @Test("a tab outside the budget survives until the idle threshold")
    func waitsOutTheIdleThreshold() {
        let (ids, live) = scenario(idle: 299)
        #expect(policy.tabsToHibernate(live: live, mru: ids, activeID: ids[0], now: now).isEmpty)

        let (lateIDs, lateLive) = scenario(idle: 301)
        #expect(policy.tabsToHibernate(live: lateLive, mru: lateIDs, activeID: lateIDs[0], now: now).count == 2)
    }

    @Test("audible tabs and tabs with unsaved input are exempt")
    func exemptions() {
        let (ids, live) = scenario(audible: [5], dirty: [4])
        #expect(policy.tabsToHibernate(live: live, mru: ids, activeID: ids[0], now: now).isEmpty)
    }

    /// Pressure collapses the budget to the active tab — but never takes the
    /// music or a half-typed reply with it.
    @Test("memory pressure keeps only the active tab, audio and unsaved input")
    func memoryPressure() {
        let (ids, live) = scenario(audible: [5], dirty: [4])
        let doomed = policy.tabsToHibernate(
            live: live, mru: ids, activeID: ids[0], now: now, underMemoryPressure: true
        )
        #expect(Set(doomed) == Set(ids[1...3]))
    }

    /// Pressure ignores the 5-minute grace period; that is the whole point of it.
    @Test("memory pressure ignores the idle threshold")
    func memoryPressureIgnoresIdle() {
        let (ids, live) = scenario(idle: 0)
        let doomed = policy.tabsToHibernate(
            live: live, mru: ids, activeID: ids[0], now: now, underMemoryPressure: true
        )
        #expect(doomed.count == 5)
    }

    /// A popup adopted mid-session is live without ever reaching the MRU list.
    @Test("a live tab missing from the MRU list is still a candidate")
    func unknownTabIsHibernated() {
        let (ids, live) = scenario(count: 2)
        let doomed = policy.tabsToHibernate(live: live, mru: [ids[0]], activeID: ids[0], now: now)
        #expect(doomed == [ids[1]])
    }
}

@Suite("Auto-archive (§6.3)")
struct AutoArchiveTests {

    private let now = Date()
    private let space = UUID()

    private func tab(_ kind: TabKind, hoursIdle: Double, archivedAt: Date? = nil) -> Tab {
        Tab(
            spaceID: space,
            kind: kind,
            url: URL(string: "https://example.com")!,
            lastActiveAt: now.addingTimeInterval(-hoursIdle * 3600),
            archivedAt: archivedAt
        )
    }

    @Test("Today tabs idle past the threshold are archived")
    func archivesIdleTodayTabs() {
        let old = tab(.today, hoursIdle: 13)
        let fresh = tab(.today, hoursIdle: 11)
        #expect(AutoArchive.idleTabs([old, fresh], now: now, hours: 12) == [old.id])
    }

    /// The exemption that matters: a pinned tab archiving itself is the user's
    /// bookmark bar emptying overnight.
    @Test("pinned and Essentials are exempt however long they sit")
    func pinnedAndEssentialsAreExempt() {
        let tabs = [tab(.pinned, hoursIdle: 500), tab(.essential, hoursIdle: 500)]
        #expect(AutoArchive.idleTabs(tabs, now: now, hours: 12).isEmpty)
    }

    @Test("the active tab is exempt, and an archived tab is not archived twice")
    func activeAndAlreadyArchivedAreSkipped() {
        let active = tab(.today, hoursIdle: 99)
        let gone = tab(.today, hoursIdle: 99, archivedAt: now)
        #expect(AutoArchive.idleTabs([active, gone], now: now, hours: 12, excluding: active.id).isEmpty)
    }

    @Test("never (0 hours) archives nothing")
    func neverMeansNever() {
        #expect(AutoArchive.idleTabs([tab(.today, hoursIdle: 10_000)], now: now, hours: 0).isEmpty)
    }

    @Test("archived tabs expire after 30 days, not before")
    func retention() {
        let old = tab(.today, hoursIdle: 0, archivedAt: now.addingTimeInterval(-31 * 24 * 3600))
        let recent = tab(.today, hoursIdle: 0, archivedAt: now.addingTimeInterval(-29 * 24 * 3600))
        #expect(AutoArchive.expired([old, recent], now: now) == [old.id])
    }
}

@Suite("Snapshot LRU (§6.8)")
struct SnapshotStoreTests {

    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "luna-snapshots-\(UUID().uuidString)")
    }

    @Test("the cache stays inside its budget and evicts least-recently-used first")
    func evictsLeastRecentlyUsed() async throws {
        let blob = Data(repeating: 0xAB, count: 1000)
        // Room for three blobs, not four.
        let store = SnapshotStore(directory: directory(), budget: 3500)
        let ids = (0..<4).map { _ in UUID() }
        for id in ids {
            await store.store(blob, for: id)
            // The LRU stamp is a `Date`; two writes in the same instant are not
            // ordered, so the test states the order it is asserting.
            try await Task.sleep(for: .milliseconds(10))
        }
        // Touching the oldest survivor makes it the newest.
        _ = await store.snapshot(for: ids[1])
        try await Task.sleep(for: .milliseconds(10))
        await store.store(blob, for: UUID())

        #expect(await store.usage <= 3500)
        #expect(await store.snapshot(for: ids[0]) == nil, "the first blob should have gone first")
        #expect(await store.snapshot(for: ids[1]) != nil, "a blob that was read is not the coldest")
    }

    @Test("a removed file does not stay in the index")
    func forgetsMissingFiles() async {
        let store = SnapshotStore(directory: directory())
        let id = UUID()
        await store.store(Data(repeating: 1, count: 10), for: id)
        await store.remove(id)
        #expect(await store.snapshot(for: id) == nil)
        #expect(await store.count == 0)
    }
}
