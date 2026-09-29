import Foundation
import GRDB

// Tabs on Other Macs (docs/SYNC-PLAN.md §5, S12): this Mac's one Device record going up,
// and the other Macs' records kept in `syncPresence`, because the engine delivers only
// changes and they would be gone after a relaunch otherwise.

/// What this Mac last published. In memory only: a relaunch publishes once more.
struct SyncPresenceState {
    /// The newest snapshot, which a batch builds the record from.
    var latest: SyncDevice?
    /// The snapshot last handed to the engine, and when.
    var queued: (device: SyncDevice, at: Date)?
}

enum SyncPresence {
    /// §2, `Device.tabs`.
    static let tabLimit = 50
    static let publishInterval: TimeInterval = 60
    /// A Mac not heard from in this long is hidden rather than offered.
    static let staleAfter: TimeInterval = 30 * 86_400

    /// Nothing another Mac could open: a blank tab, or one of Luna's own pages.
    static func isShareable(_ url: URL) -> Bool {
        url.scheme?.lowercased() != "luna" && url.absoluteString != "about:blank"
    }
}

extension SyncCoordinator {

    /// Publishes this Mac's open tabs under `name`, the Mac's name, which the app supplies.
    /// Call it on activation and whenever the set of tabs changes: an unchanged set is
    /// not sent again, and a change is sent at most once a minute.
    ///
    /// Private windows keep their tabs in a database of their own, so the store read
    /// here never holds them.
    public func publishPresence(name: String, now: Date = Date()) async throws {
        guard let engine, try await store.enabledSyncZones().contains(.devices) else { return }
        let tabs = try await store.presenceTabs()
        let device = SyncDevice(id: try await deviceID(), name: name, tabs: tabs)
        presence.latest = device
        if let queued = presence.queued,
           queued.device == device || now.timeIntervalSince(queued.at) < SyncPresence.publishInterval { return }
        // ponytail: a change inside the minute waits for the next call; add a trailing timer
        // if the app ever stops calling on activation.
        presence.queued = (device, now)
        let name = device.id.uuidString
        keys[name] = ("Device", name)
        await engine.add(pending: [.save(name, in: .devices)])
    }

    /// The Macs to list: every other one heard from in the last 30 days, and none while
    /// the Devices switch is off.
    public func otherMacs(now: Date = Date()) async throws -> [SyncDevice] {
        guard try await store.enabledSyncZones().contains(.devices) else { return [] }
        return try await store.presence(excluding: deviceID(), since: now.addingTimeInterval(-SyncPresence.staleAfter))
    }

    /// This Mac's Device record, or nil before anything was published this launch.
    func presenceRecord(named name: String) async throws -> SyncRecord? {
        guard let device = presence.latest, device.id.uuidString == name else { return nil }
        return SyncMapping.record(for: device, modifiedAt: Date(), stored: try await store.storedRecord(named: name))
    }
}

extension BrowserStore {

    /// The most recently used open tabs, newest first, as `Device.tabs` carries them.
    func presenceTabs() async throws -> [SyncDevice.OpenTab] {
        try await pool.read { db in
            try Tab.fetchAll(db, sql: "SELECT * FROM tabs WHERE archivedAt IS NULL ORDER BY lastActiveAt DESC")
                .filter { SyncPresence.isShareable($0.url) }
                .prefix(SyncPresence.tabLimit)
                .map { SyncDevice.OpenTab(spaceID: $0.spaceID, url: $0.url, title: $0.customTitle ?? $0.title) }
        }
    }

    /// Other Macs' records as they arrive. `modifiedAt` is when that Mac last published.
    func applyPresence(_ changes: SyncChangeSet) async throws {
        try await pool.write { db in
            for record in changes.modifications {
                guard let device = SyncMapping.device(from: record) else { continue }
                let updatedAt: Date = if case .date(let date) = record["modifiedAt"] { date } else { Date() }
                try db.execute(
                    sql: "INSERT OR REPLACE INTO syncPresence (deviceID, name, updatedAt, tabs) VALUES (?, ?, ?, ?)",
                    arguments: [device.id.uuidString, device.name, updatedAt, try JSONEncoder().encode(device.tabs)]
                )
            }
            for deletion in changes.deletions {
                try db.execute(sql: "DELETE FROM syncPresence WHERE deviceID = ?", arguments: [deletion.recordName])
            }
        }
    }

    func presence(excluding own: UUID, since: Date) async throws -> [SyncDevice] {
        try await pool.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT * FROM syncPresence WHERE deviceID != ? AND updatedAt >= ? ORDER BY name",
                arguments: [own.uuidString, since]
            ).compactMap { row in
                guard let id = UUID(uuidString: row["deviceID"]),
                      let tabs = try? JSONDecoder().decode([SyncDevice.OpenTab].self, from: row["tabs"]) else { return nil }
                return SyncDevice(id: id, name: row["name"], tabs: tabs)
            }
        }
    }
}
