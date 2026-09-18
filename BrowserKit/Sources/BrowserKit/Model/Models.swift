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
    /// The Profile a Favorite belongs to — set for `.essential` rows, `nil` for every other
    /// kind (§2, schema `v2`).
    ///
    /// Favorites are scoped **per Profile**, not per Space: a Favorite is a logged-in app
    /// tile, and a tile that opens in a Space whose cookie jar never saw that login is a
    /// broken tile. Arc keys its Favorites container the same way — `topAppsContainerIDs` is
    /// a flat profile → container pair, not something a Space owns.
    ///
    /// The row keeps its home `spaceID` as well. That is deliberate: the session re-homes a
    /// shared Favorite onto a surviving Space of the same Profile before a Space row is
    /// deleted, so `tabs.spaceID`'s `ON DELETE CASCADE` never eats one.
    public var profileID: UUID?

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
        order: Int = 0,
        profileID: UUID? = nil
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
        self.profileID = profileID
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

// MARK: - The all-zero data store identifier (§3.1)

public extension UUID {
    /// `00000000-0000-0000-0000-000000000000`.
    ///
    /// `WKWebsiteDataStore.dataStoreForIdentifier:` documents *"Throws exception if
    /// identifier is 0"*. That is an **Objective-C exception, which Swift cannot catch**,
    /// so a zero identifier is an uncatchable crash rather than an error a call site can
    /// handle. It is therefore checked at the persistence boundary, where it can still be
    /// turned into data, not at the WebKit boundary, where it can only be turned into a
    /// stack trace.
    static let zero = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))

    /// Whether this is the identifier WebKit refuses (see ``zero``).
    var isZero: Bool { self == .zero }
}

public extension Profile {
    /// False when `dataStoreIdentifier` is the all-zero UUID — the one value that must
    /// never reach `WKWebsiteDataStore(forIdentifier:)`.
    ///
    /// `profiles.dataStoreIdentifier` is `NOT NULL UNIQUE` with no value check, and SQLite
    /// cannot gain a `CHECK` constraint without rebuilding the table every `spaces.profileID`
    /// foreign key points at. So the invariant is enforced in Swift, on both sides of the
    /// column: ``BrowserStore/upsert(_:)-(Profile)`` refuses to write a zero identifier, and
    /// ``BrowserStore/profiles()`` repairs one it finds on read.
    var hasUsableDataStoreIdentifier: Bool { !dataStoreIdentifier.isZero }

    /// This profile with a freshly minted `dataStoreIdentifier` if the persisted one is
    /// unusable, and unchanged otherwise.
    ///
    /// Minting a new one loses nothing recoverable: a zero identifier addresses no store
    /// on disk, because nothing could ever have created one under it. The profile's *name*
    /// and its `id` — the identity every `Space` references, and the only one §10 allows to
    /// sync — survive. The user gets an empty cookie jar for that profile instead of a crash.
    func repairingDataStoreIdentifier() -> Profile {
        guard !hasUsableDataStoreIdentifier else { return self }
        return Profile(id: id, name: name, dataStoreIdentifier: UUID())
    }
}
