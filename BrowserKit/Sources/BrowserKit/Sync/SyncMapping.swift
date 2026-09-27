import Foundation

// Row ↔ `SyncRecord`, one mapper per record type (docs/SYNC-PLAN.md §1–§2). Pure.
//
// Every writer takes `stored`, the last record known under that name, and goes through
// `SyncRecord(writing:…)`, which is where the §31.9 versioning rules live. User content
// goes in encrypted fields; only structure (ids, kind, position, dates) travels plain.
// `CloudKit/Schema.ckdb` must declare every field written here, which
// `SyncSchemaFileTests` checks.

/// A `siteSettings` row as it syncs. Each flag is tri-state: nil means nobody answered.
public struct SyncSiteSetting: Sendable, Hashable {
    public var host: String
    public var automaticPictureInPicture: Bool?
    public var localNetwork: Bool?
    public var savePasswords: Bool?
    public var popups: Bool?
    public var blockingDisabled: Bool?
    public var insecureAllowed: Bool?

    public init(
        host: String,
        automaticPictureInPicture: Bool? = nil,
        localNetwork: Bool? = nil,
        savePasswords: Bool? = nil,
        popups: Bool? = nil,
        blockingDisabled: Bool? = nil,
        insecureAllowed: Bool? = nil
    ) {
        self.host = host
        self.automaticPictureInPicture = automaticPictureInPicture
        self.localNetwork = localNetwork
        self.savePasswords = savePasswords
        self.popups = popups
        self.blockingDisabled = blockingDisabled
        self.insecureAllowed = insecureAllowed
    }

    /// The column names, which are also the field names.
    static var flags: [(String, WritableKeyPath<SyncSiteSetting, Bool?>)] { [
        ("automaticPictureInPicture", \.automaticPictureInPicture),
        ("localNetwork", \.localNetwork),
        ("savePasswords", \.savePasswords),
        ("popups", \.popups),
        ("blockingDisabled", \.blockingDisabled),
        ("insecureAllowed", \.insecureAllowed)
    ] }
}

/// One allowlisted `UserDefaults` key and its value as a property list.
public struct SyncSetting: Sendable, Hashable {
    public var key: String
    public var value: Data

    public init(key: String, value: Data) {
        self.key = key
        self.value = value
    }
}

/// One place's typed and bookmarked visits from one Mac.
public struct SyncHistoryEntry: Sendable, Hashable {
    public struct Visit: Sendable, Hashable, Codable {
        public var spaceID: UUID
        public var at: Date
        /// `visits.type`: `typed` or `bookmarked`.
        public var kind: String

        public init(spaceID: UUID, at: Date, kind: String) {
            self.spaceID = spaceID
            self.at = at
            self.kind = kind
        }
    }

    public var deviceID: UUID
    /// `places.id` on the Mac that wrote it; see Record IDs in docs/SYNC-PLAN.md §1.
    public var placeID: Int64
    public var url: URL
    public var title: String
    public var visits: [Visit]

    public init(deviceID: UUID, placeID: Int64, url: URL, title: String, visits: [Visit]) {
        self.deviceID = deviceID
        self.placeID = placeID
        self.url = url
        self.title = title
        self.visits = visits
    }
}

/// A Mac and its open tabs, for Tabs on Other Macs.
public struct SyncDevice: Sendable, Hashable {
    public struct OpenTab: Sendable, Hashable, Codable {
        public var spaceID: UUID
        public var url: URL
        public var title: String

        public init(spaceID: UUID, url: URL, title: String) {
            self.spaceID = spaceID
            self.url = url
            self.title = title
        }
    }

    public var id: UUID
    public var name: String
    public var tabs: [OpenTab]

    public init(id: UUID, name: String, tabs: [OpenTab]) {
        self.id = id
        self.name = name
        self.tabs = tabs
    }
}

public enum SyncMapping {

    // MARK: Space

    public static func record(for space: Space, modifiedAt: Date, stored: SyncRecord?) -> SyncRecord {
        SyncRecord(writing: "Space", name: space.id.uuidString, zone: .spaces, over: stored, fields: [
            "modifiedAt": plain(.date(modifiedAt)),
            "position": plain(.int(Int64(space.order))),
            "name": secret(.string(space.name)),
            "symbolName": secret(.string(space.symbolName)),
            "gradient": secret(json(space.gradient).flatMap { String(bytes: $0, encoding: .utf8) }.map { .string($0) }),
            "image": secret(space.imageData.map { .bytes($0) })
        ])
    }

    /// With a fresh `dataStoreIdentifier`: that names this Mac's cookie jar and never syncs.
    public static func space(from record: SyncRecord) -> Space? {
        guard record.recordType == "Space", let id = UUID(uuidString: record.recordName),
              let name = string(record["name"]), let symbolName = string(record["symbolName"]),
              let gradient = string(record["gradient"]).flatMap({ decode(GradientPair.self, Data($0.utf8)) })
        else { return nil }
        return Space(
            id: id, name: name, symbolName: symbolName, gradient: gradient,
            imageData: bytes(record["image"]), order: int(record["position"]) ?? 0
        )
    }

    // MARK: TabGroup

    public static func record(for group: TabGroup, modifiedAt: Date, stored: SyncRecord?) -> SyncRecord {
        SyncRecord(writing: "TabGroup", name: group.id.uuidString, zone: .spaces, over: stored, fields: [
            "modifiedAt": plain(.date(modifiedAt)),
            "spaceID": plain(.string(group.spaceID.uuidString)),
            "kind": plain(.string(group.kind.rawValue)),
            "position": plain(.int(Int64(group.order))),
            "name": secret(.string(group.name)),
            "symbolName": secret(.string(group.symbolName))
        ])
    }

    /// `isCollapsed` is this Mac's and comes back false; the apply step keeps the local one.
    public static func tabGroup(from record: SyncRecord) -> TabGroup? {
        guard record.recordType == "TabGroup", let id = UUID(uuidString: record.recordName),
              let spaceID = uuid(record["spaceID"]), let name = string(record["name"]) else { return nil }
        return TabGroup(
            id: id, spaceID: spaceID, name: name,
            symbolName: string(record["symbolName"]) ?? TabGroup.defaultSymbolName,
            kind: kind(record["kind"]), order: int(record["position"]) ?? 0
        )
    }

    // MARK: Tab

    public static func record(for tab: Tab, modifiedAt: Date, stored: SyncRecord?) -> SyncRecord {
        SyncRecord(writing: "Tab", name: tab.id.uuidString, zone: .spaces, over: stored, fields: [
            "modifiedAt": plain(.date(modifiedAt)),
            "spaceID": plain(.string(tab.spaceID.uuidString)),
            "groupID": plain(tab.groupID.map { .string($0.uuidString) }),
            "kind": plain(.string(tab.kind.rawValue)),
            "position": plain(.int(Int64(tab.order))),
            "createdAt": plain(.date(tab.createdAt)),
            "archivedAt": plain(tab.archivedAt.map { .date($0) }),
            "url": secret(.string(tab.url.absoluteString)),
            "title": secret(.string(tab.title)),
            "customTitle": secret(tab.customTitle.map { .string($0) }),
            "customSymbolName": secret(tab.customSymbolName.map { .string($0) }),
            "pinnedURL": secret(tab.pinnedURL.map { .string($0.absoluteString) })
        ])
    }

    /// The local-only columns come back at their defaults; the apply step keeps this Mac's.
    public static func tab(from record: SyncRecord) -> Tab? {
        guard record.recordType == "Tab", let id = UUID(uuidString: record.recordName),
              let spaceID = uuid(record["spaceID"]), let url = string(record["url"]).flatMap(URL.init(string:))
        else { return nil }
        return Tab(
            id: id, spaceID: spaceID, kind: kind(record["kind"]), url: url,
            title: string(record["title"]) ?? "",
            createdAt: date(record["createdAt"]) ?? Date(),
            archivedAt: date(record["archivedAt"]),
            order: int(record["position"]) ?? 0,
            pinnedURL: string(record["pinnedURL"]).flatMap(URL.init(string:)),
            customTitle: string(record["customTitle"]),
            customSymbolName: string(record["customSymbolName"]),
            groupID: uuid(record["groupID"])
        )
    }

    // MARK: SiteSetting

    /// An unset flag is left out rather than cleared, so it never erases an answer
    /// another Mac gave (§3: a set value beats an unset one). `zoom` is reserved.
    public static func record(
        for site: SyncSiteSetting, secret key: SyncSecret, modifiedAt: Date, stored: SyncRecord?
    ) -> SyncRecord {
        var fields = ["modifiedAt": plain(.date(modifiedAt)), "host": secret(.string(site.host))]
        for (name, path) in SyncSiteSetting.flags {
            if let flag = site[keyPath: path] { fields[name] = secret(.int(flag ? 1 : 0)) }
        }
        return SyncRecord(writing: "SiteSetting", name: key.siteRecordName(forHost: site.host), zone: .sites, over: stored, fields: fields)
    }

    public static func siteSetting(from record: SyncRecord) -> SyncSiteSetting? {
        guard record.recordType == "SiteSetting", let host = string(record["host"]) else { return nil }
        var site = SyncSiteSetting(host: host)
        for (name, path) in SyncSiteSetting.flags {
            site[keyPath: path] = int(record[name]).map { $0 != 0 }
        }
        return site
    }

    // MARK: Setting

    public static func record(for setting: SyncSetting, modifiedAt: Date, stored: SyncRecord?) -> SyncRecord {
        SyncRecord(writing: "Setting", name: setting.key, zone: .settings, over: stored, fields: [
            "modifiedAt": plain(.date(modifiedAt)),
            "value": secret(.bytes(setting.value))
        ])
    }

    public static func setting(from record: SyncRecord) -> SyncSetting? {
        guard record.recordType == "Setting", let value = bytes(record["value"]) else { return nil }
        return SyncSetting(key: record.recordName, value: value)
    }

    // MARK: HistoryEntry

    public static func record(for entry: SyncHistoryEntry, modifiedAt: Date, stored: SyncRecord?) -> SyncRecord {
        SyncRecord(writing: "HistoryEntry", name: "\(entry.deviceID.uuidString)-\(entry.placeID)", zone: .history, over: stored, fields: [
            "modifiedAt": plain(.date(modifiedAt)),
            "url": secret(.string(entry.url.absoluteString)),
            "title": secret(.string(entry.title)),
            "visits": secret(json(entry.visits).map { .bytes($0) })
        ])
    }

    public static func historyEntry(from record: SyncRecord) -> SyncHistoryEntry? {
        // The device id is a UUID, hyphens and all, so the place id is after the last one.
        guard record.recordType == "HistoryEntry", let dash = record.recordName.lastIndex(of: "-"),
              let deviceID = UUID(uuidString: String(record.recordName[..<dash])),
              let placeID = Int64(record.recordName[record.recordName.index(after: dash)...]),
              let url = string(record["url"]).flatMap(URL.init(string:)) else { return nil }
        let visits = bytes(record["visits"]).flatMap { decode([SyncHistoryEntry.Visit].self, $0) } ?? []
        return SyncHistoryEntry(deviceID: deviceID, placeID: placeID, url: url, title: string(record["title"]) ?? "", visits: visits)
    }

    // MARK: Device

    public static func record(for device: SyncDevice, modifiedAt: Date, stored: SyncRecord?) -> SyncRecord {
        SyncRecord(writing: "Device", name: device.id.uuidString, zone: .devices, over: stored, fields: [
            "modifiedAt": plain(.date(modifiedAt)),
            "name": secret(.string(device.name)),
            "tabs": secret(json(device.tabs).map { .bytes($0) })
        ])
    }

    public static func device(from record: SyncRecord) -> SyncDevice? {
        guard record.recordType == "Device", let id = UUID(uuidString: record.recordName) else { return nil }
        let tabs = bytes(record["tabs"]).flatMap { decode([SyncDevice.OpenTab].self, $0) } ?? []
        return SyncDevice(id: id, name: string(record["name"]) ?? "", tabs: tabs)
    }

    // MARK: Helpers

    private static func plain(_ value: SyncValue?) -> SyncField { SyncField(value) }
    private static func secret(_ value: SyncValue?) -> SyncField { SyncField(value, encrypted: true) }

    /// A kind this Luna does not know lands in the ordinary section rather than dropping the row.
    private static func kind(_ value: SyncValue?) -> TabKind {
        string(value).flatMap(TabKind.init(rawValue:)) ?? .today
    }

    private static func string(_ value: SyncValue?) -> String? {
        if case .string(let string) = value { string } else { nil }
    }

    private static func int(_ value: SyncValue?) -> Int? {
        if case .int(let int) = value { Int(int) } else { nil }
    }

    private static func date(_ value: SyncValue?) -> Date? {
        if case .date(let date) = value { date } else { nil }
    }

    private static func bytes(_ value: SyncValue?) -> Data? {
        if case .bytes(let data) = value { data } else { nil }
    }

    private static func uuid(_ value: SyncValue?) -> UUID? {
        string(value).flatMap(UUID.init(uuidString:))
    }

    /// Seconds since 1970 and sorted keys: the bytes are read by other Macs and other
    /// versions, so they must not depend on Foundation's defaults.
    private static func json<T: Encodable>(_ value: T) -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = .sortedKeys
        return try? encoder.encode(value)
    }

    private static func decode<T: Decodable>(_ type: T.Type, _ data: Data) -> T? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(type, from: data)
    }
}
