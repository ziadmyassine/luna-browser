import Foundation

// Luna's persisted value types (§5.2, §6.1). Plain `Codable` structs with no behaviour:
// they cross the actor boundary, the SQLite boundary and — one day — the iOS boundary,
// so nothing here may import AppKit. Colour travels as `RGBA`, never `NSColor` (§25.5).

/// An sRGB colour, 0...1 per component. The only way colour crosses into `BrowserKit`.
public struct RGBA: Sendable, Hashable, Codable {
    // swiftlint:disable identifier_name
    public var r: Double
    public var g: Double
    public var b: Double
    public var a: Double

    public init(r: Double, g: Double, b: Double, a: Double) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }
    // swiftlint:enable identifier_name
}

/// The two stops of a Space gradient (§8.2).
public struct GradientPair: Sendable, Hashable, Codable {
    public var start: RGBA
    public var end: RGBA

    public init(start: RGBA, end: RGBA) {
        self.start = start
        self.end = end
    }

    /// The gradient `seedIfEmpty()` gives the first Space. Seed *data*, not a design token:
    /// a Space's gradient is the user's from the moment they pick one, and §8.2's curated
    /// palette lives in `Design` where the rest of the colour does.
    public static let defaultSpace = GradientPair(
        start: RGBA(r: 0.45, g: 0.38, b: 0.92, a: 1),
        end: RGBA(r: 0.24, g: 0.65, b: 0.94, a: 1)
    )
}

/// Which sidebar section a tab lives in (§7.1).
public enum TabKind: String, Sendable, Codable {
    case essential, pinned, today
}

/// A tab (§6.1). `interactionState` is WebKit's opaque session blob — back/forward
/// history and scroll position — captured on hibernate and fed back on wake (§6.2).
public struct Tab: Identifiable, Sendable, Hashable, Codable {
    public var id: UUID
    public var spaceID: UUID
    public var kind: TabKind
    public var url: URL
    public var title: String
    public var faviconKey: String?
    public var themeColor: RGBA?
    public var createdAt: Date
    public var lastActiveAt: Date
    public var archivedAt: Date?
    public var parentTabID: UUID?
    public var interactionState: Data?
    public var hasUnread: Bool
    public var order: Int

    public init(
        id: UUID = UUID(),
        spaceID: UUID,
        kind: TabKind = .today,
        url: URL,
        title: String = "",
        faviconKey: String? = nil,
        themeColor: RGBA? = nil,
        createdAt: Date = Date(),
        lastActiveAt: Date = Date(),
        archivedAt: Date? = nil,
        parentTabID: UUID? = nil,
        interactionState: Data? = nil,
        hasUnread: Bool = false,
        order: Int = 0
    ) {
        self.id = id
        self.spaceID = spaceID
        self.kind = kind
        self.url = url
        self.title = title
        self.faviconKey = faviconKey
        self.themeColor = themeColor
        self.createdAt = createdAt
        self.lastActiveAt = lastActiveAt
        self.archivedAt = archivedAt
        self.parentTabID = parentTabID
        self.interactionState = interactionState
        self.hasUnread = hasUnread
        self.order = order
    }
}

/// A Space (§5.2): a named, coloured set of tabs backed by exactly one profile.
public struct Space: Identifiable, Sendable, Hashable, Codable {
    public var id: UUID
    public var name: String
    /// SF Symbol name — resolved to an image in `Design`, never here.
    public var symbolName: String
    public var gradient: GradientPair
    public var profileID: UUID
    public var order: Int

    public init(
        id: UUID = UUID(),
        name: String,
        symbolName: String,
        gradient: GradientPair,
        profileID: UUID,
        order: Int = 0
    ) {
        self.id = id
        self.name = name
        self.symbolName = symbolName
        self.gradient = gradient
        self.profileID = profileID
        self.order = order
    }
}

/// A storage-isolated profile (§5.1).
///
/// `dataStoreIdentifier` backs `WKWebsiteDataStore(forIdentifier:)`. WebKit can list
/// identifiers but cannot tell us which name belongs to which, so the mapping is ours
/// to keep — losing this row orphans a cookie jar in `~/Library/WebKit/WebsiteDataStore/`.
public struct Profile: Identifiable, Sendable, Hashable, Codable {
    public var id: UUID
    public var name: String
    public var dataStoreIdentifier: UUID

    public init(id: UUID = UUID(), name: String, dataStoreIdentifier: UUID = UUID()) {
        self.id = id
        self.name = name
        self.dataStoreIdentifier = dataStoreIdentifier
    }
}
