import Foundation

// The conflict rules of docs/SYNC-PLAN.md §3. Pure: the coordinator decides when to ask,
// the store and the session carry the answer out.

public enum SyncMerge {

    /// What to do with a pending local change once the server's copy is known.
    public enum Outcome: Sendable, Equatable {
        /// Drop the pending change and take the server's state: its record, or the
        /// deletion when there is none.
        case takeServer
        /// Save this record. It is also the new local state, since a field merge can
        /// bring values in from the server.
        case save(SyncRecord)
        /// Send the delete again.
        case deleteOnServer
    }

    /// A deleted Space or group takes its tabs with it, so an edit elsewhere is never
    /// allowed to bring one back half-populated.
    private static let deleteBeatsEdit: Set = ["Space", "TabGroup", "Tab"]
    private static let lastWriterWins: Set = ["Space", "TabGroup", "Tab", "Setting"]
    /// One writer per record, so a conflict can only be this Mac's own earlier write.
    private static let localWins: Set = ["HistoryEntry", "Device"]

    /// Resolves a pending save (`local`) or delete (`local` nil) against `server`, the
    /// record `serverRecordChanged` returned or nil when it is gone. `changedAt` is the
    /// outbox row's, which is the local time the §3 rules compare.
    public static func resolve(recordType: String? = nil, local: SyncRecord?, changedAt: Date, server: SyncRecord?) -> Outcome {
        let type = recordType ?? local?.recordType ?? server?.recordType ?? ""
        guard let server else {
            // Gone on the server. A structural row goes with it; anything else that is
            // set beats unset, so this Mac's value goes back up.
            guard let local, !deleteBeatsEdit.contains(type) else { return .takeServer }
            return .save(local)
        }
        let serverIsNewer = (date(server["modifiedAt"]) ?? .distantPast) >= changedAt
        guard let local else {
            if deleteBeatsEdit.contains(type) || localWins.contains(type) { return .deleteOnServer }
            // A removed setting or site is one more write, and the newer write wins.
            guard lastWriterWins.contains(type) || type == "SiteSetting" else { return .takeServer }
            return serverIsNewer ? .takeServer : .deleteOnServer
        }
        switch type {
        case _ where lastWriterWins.contains(type):
            return serverIsNewer ? .takeServer : .save(write(local.fields, over: server))
        case _ where localWins.contains(type):
            return .save(write(local.fields, over: server))
        case "SiteSetting":
            return siteSetting(local, over: server, serverIsNewer: serverIsNewer)
        default:
            // SyncSecret, where the server always wins, and any type this Luna does not know.
            return .takeServer
        }
    }

    /// Field by field: a flag the local record leaves out is unset and never clears the
    /// server's. `SyncMapping` leaves out `blockingDisabled` and `insecureAllowed` when off,
    /// so this Mac's off never switches another Mac's on back off.
    private static func siteSetting(_ local: SyncRecord, over server: SyncRecord, serverIsNewer: Bool) -> Outcome {
        let flags = Set(SyncSiteSetting.flags.map(\.0))
        let taken = local.fields.filter { name, _ in
            !(flags.contains(name) && serverIsNewer && server.fields[name]?.value != nil)
        }
        let changed = taken.contains { name, field in name != "modifiedAt" && server.fields[name] != field }
        guard changed else { return .takeServer }
        var fields = taken
        if serverIsNewer { fields["modifiedAt"] = server.fields["modifiedAt"] }
        return .save(write(fields, over: server))
    }

    /// `fields` laid over the server's record: its system fields, its fields this Luna does
    /// not know, and never a lower `schemaVersion` (§31.9).
    private static func write(_ fields: [String: SyncField], over server: SyncRecord) -> SyncRecord {
        var record = server
        record.fields.merge(fields) { _, mine in mine }
        record.schemaVersion = max(server.schemaVersion, SyncRecord.currentSchemaVersion)
        return record
    }

    // MARK: Incoming tabs

    /// An incoming tab laid over this Mac's copy. `sendBack` is true when the result
    /// differs from what arrived and has to go back up.
    ///
    /// - Parameter isLive: whether the tab has a web view on this Mac. Its `url` and `title`
    ///   are then whatever the page is showing, and the incoming ones would navigate it.
    public static func incoming(_ remote: Tab, over local: Tab?, isLive: Bool) -> (tab: Tab, sendBack: Bool) {
        guard let local else { return (remote, false) }
        var tab = remote
        tab.lastActiveAt = local.lastActiveAt
        tab.interactionState = local.interactionState
        tab.hasUnread = local.hasUnread
        tab.faviconKey = local.faviconKey
        tab.themeColor = local.themeColor
        tab.isDormant = local.isDormant
        tab.parentTabID = local.parentTabID
        if isLive {
            tab.url = local.url
            tab.title = local.title
        }
        // One Mac's idle clock never archives a tab in use on another.
        if let archivedAt = remote.archivedAt, local.archivedAt == nil, local.lastActiveAt > archivedAt {
            tab.archivedAt = nil
            return (tab, true)
        }
        return (tab, false)
    }

    /// The Favorites past `BrowserStore.favoritesCap` in each Space, demoted to pinned. The
    /// order is (`order`, `createdAt`, `id`), the same on every Mac, so each demotes the same
    /// tabs and the demotion need not be sent back.
    public static func demotingExtraFavorites(in tabs: [Tab]) -> [Tab] {
        let favorites = tabs.filter { $0.kind == .essential && $0.archivedAt == nil }
        return Dictionary(grouping: favorites, by: \.spaceID).values.flatMap { inSpace in
            inSpace
                .sorted { ($0.order, $0.createdAt, $0.id.uuidString) < ($1.order, $1.createdAt, $1.id.uuidString) }
                .dropFirst(BrowserStore.favoritesCap)
                .map { tab in
                    var tab = tab
                    tab.kind = .pinned
                    return tab
                }
        }
        .sorted { ($0.order, $0.createdAt) < ($1.order, $1.createdAt) }
    }

    // MARK: Turning sync on

    /// A local row as the turn-on fetch sees it.
    public struct LocalRow: Sendable, Hashable {
        public var recordName: String
        /// Whether it has stored `systemFields`, which prove the server once had it.
        public var wasSynced: Bool

        public init(recordName: String, wasSynced: Bool) {
            self.recordName = recordName
            self.wasSynced = wasSynced
        }
    }

    public struct Reconciliation: Sendable, Equatable {
        public var apply: [SyncRecord]
        public var upload: [String]
        public var deleteLocally: [String]
    }

    /// After a full fetch on turning sync on: iCloud wins for every record it has, rows it
    /// never saw go up, and rows it once had but no longer sent were deleted elsewhere.
    public static func reconcile(fetched: [SyncRecord], local: [LocalRow]) -> Reconciliation {
        let names = Set(fetched.map(\.recordName))
        let missing = local.filter { !names.contains($0.recordName) }
        return Reconciliation(
            apply: fetched,
            upload: missing.filter { !$0.wasSynced }.map(\.recordName),
            deleteLocally: missing.filter(\.wasSynced).map(\.recordName)
        )
    }

    /// This Mac's seed Space, when iCloud already has Spaces and the seed was never renamed
    /// and holds no tabs; otherwise nil, and both Macs' Spaces are kept.
    public static func seedSpaceToDrop(local: [Space], spacesWithTabs: Set<UUID>, fetched: [SyncRecord]) -> UUID? {
        let cloudSpaces = Set(fetched.filter { $0.recordType == "Space" }.map(\.recordName))
        guard !cloudSpaces.isEmpty else { return nil }
        return local.first {
            $0.name == BrowserStore.seedSpaceName && !spacesWithTabs.contains($0.id) && !cloudSpaces.contains($0.id.uuidString)
        }?.id
    }

    private static func date(_ value: SyncValue?) -> Date? {
        if case .date(let date) = value { date } else { nil }
    }
}
