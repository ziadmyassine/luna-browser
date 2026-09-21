import Foundation

// Luna's persisted value types (§5.2, §6.1). Plain `Codable` structs with no behaviour:
// they cross the actor boundary, the SQLite boundary and — one day — the iOS boundary,
// so nothing here may import AppKit. Colour travels as `RGBA`, never `NSColor` (§25.5).

/// An sRGB colour, 0...1 per component. The only way colour crosses into `BrowserKit`.
public struct RGBA: Sendable, Hashable, Codable {
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
}

/// The two stops of a Space gradient (§8.2).
public struct GradientPair: Sendable, Hashable, Codable {
    public var start: RGBA
    public var end: RGBA

    public init(start: RGBA, end: RGBA) {
        self.start = start
        self.end = end
    }

    /// The gradient `seedIfEmpty()` gives the first Space. Seed data, not a design token:
    /// a Space's gradient is the user's from the moment they pick one, and §8.2's curated
    /// palette lives in `Design` where the rest of the colour does.
    public static let defaultSpace = GradientPair(
        start: RGBA(r: 0.45, g: 0.38, b: 0.92, a: 1),
        end: RGBA(r: 0.24, g: 0.65, b: 0.94, a: 1)
    )
}

/// Which sidebar section a tab lives in (§7.1, §3.4b).
///
/// `.pinned` is the **saved** tier: the rows between §3.3's grid and the rule. It was
/// only ever "the run above today's tabs" and it now carries the behaviour that makes the
/// name true — closing one keeps the row and drops the page.
public enum TabKind: String, Sendable, Codable {
    case essential, pinned, today

    /// Whether a tab of this kind outlives its own page. True of §3.3's tiles and
    /// §3.4b's saved rows, false of the tabs of the day, which are the ones `⌘W` ends.
    public var keepsTabWhenPageCloses: Bool { self != .today }
}

/// A named, iconned set of tabs inside one Space (§3.4b).
///
/// It stands in §3.4's list as one row with its tabs under it, and it stands in either
/// section — `kind` is which. Never `.essential`: §3.3's grid is one tile per tab and a
/// group is a list of them, so there is no tile for a group to be. The two boundaries
/// that could write one enforce that rather than the type — ``BrowserStore/upsert(_:)-(TabGroup)``
/// repairs a stray value on the way to disk and ``sanitisedKind`` is what it repairs with.
///
/// A group owns no tabs. `Tab.groupID` points the other way, so ungrouping is one write
/// per tab and deleting a group cannot take its tabs with it (`ON DELETE SET NULL`).
public struct TabGroup: Identifiable, Sendable, Hashable, Codable {
    public var id: UUID
    public var spaceID: UUID
    public var name: String
    /// SF Symbol name — resolved to an image in `Design`, never here, exactly as
    /// `Space.symbolName` is.
    public var symbolName: String
    public var kind: TabKind
    /// Folded shut, drawn as the header alone. Persisted because it is a decision about
    /// the group rather than about this launch: a group the user folded away and found
    /// open again the next morning has lost the only thing folding it was for.
    public var isCollapsed: Bool
    /// Position among its section's top-level slots, which it shares with the loose tabs
    /// of that section — a group can sit between two of them. See `TabList`.
    public var order: Int

    public init(
        id: UUID = UUID(),
        spaceID: UUID,
        name: String,
        symbolName: String = TabGroup.defaultSymbolName,
        kind: TabKind = .today,
        isCollapsed: Bool = false,
        order: Int = 0
    ) {
        self.id = id
        self.spaceID = spaceID
        self.name = name
        self.symbolName = symbolName
        self.kind = Self.sanitised(kind)
        self.isCollapsed = isCollapsed
        self.order = order
    }
}

public extension TabGroup {

    /// What a group starts with when the user picks no icon.
    static let defaultSymbolName = "folder"

    /// Whether this group stands in §3.4b's saved tier.
    var isSaved: Bool { kind == .pinned }

    /// `kind`, with §3.3's grid ruled out. A group carried there means the ordinary
    /// section — the nearest true thing to "not a tile".
    static func sanitised(_ kind: TabKind) -> TabKind { kind == .essential ? .today : kind }

    /// This group with a `kind` the grid cannot be. The read-side repair, paired with the
    /// write-side refusal in `BrowserStore`, the way `Profile` guards its data store id.
    func sanitisingKind() -> TabGroup {
        guard kind == .essential else { return self }
        var repaired = self
        repaired.kind = .today
        return repaired
    }
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

    /// Where a pinned tile goes back to when it is closed (schema `v3`).
    ///
    /// A tile is a place you keep, not a page you happened to leave open. Set at
    /// the moment the tab is pinned and cleared when it is unpinned, so it is
    /// the address the user chose to file away — not wherever the site walked
    /// afterwards. `closeTab` on a pinned tab returns `url` to this and drops
    /// `interactionState`; a tab that has merely gone cold keeps both, so
    /// clicking the tile lands where you left off. Nil for every other kind.
    public var pinnedURL: URL?

    /// The name the user gave this tab, overriding whatever the page calls itself (schema `v4`).
    ///
    /// Nil is not the empty string: nil means "this tab has no name of its own", and the page's
    /// `title` is the answer. A rename that cleared to `""` would be indistinguishable from a page
    /// that has not reported a title yet, and the row would fall back to the domain forever.
    public var customTitle: String?

    /// The SF Symbol the user chose for this tab, drawn in place of the favicon (schema `v4`).
    ///
    /// Nil means "use the site's icon", which is every tab until somebody says otherwise. Stored as
    /// a name rather than an image for the same reason `Space.symbolName` is: an image is not a
    /// value that crosses the SQLite boundary, and `Design` is the only layer allowed to resolve one.
    public var customSymbolName: String?

    /// The §3.4b group this tab stands in, or nil for a tab loose in its section (schema `v6`).
    ///
    /// The pointer is on the tab rather than a list on the group, which is what makes
    /// `ON DELETE SET NULL` the honest rule for a deleted group: the tabs are still tabs,
    /// they are simply loose again. A grouped tab's `kind` always matches its group's, so
    /// "is this saved" has one answer wherever it is asked.
    public var groupID: UUID?

    /// A saved tab whose page has been closed (schema `v6`).
    ///
    /// The whole of §3.4b's two-press close. A saved row is a place the user kept, so the
    /// first press drops the page and leaves the row — dimmed, back at `pinnedURL`, with no
    /// session blob. The second press has nothing left to close and means the row itself.
    ///
    /// It has to be stored rather than inferred. "No live web view" is true of every tab
    /// after a relaunch and of every cold one §19.2 has reclaimed, and neither of those is a
    /// page anybody closed; a tab that came back from lunch one press from deletion would be
    /// a data-loss bug wearing a feature's clothes. Always false for `.today` rows, which
    /// are archived by the first press.
    public var isDormant: Bool

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
        pinnedURL: URL? = nil,
        customTitle: String? = nil,
        customSymbolName: String? = nil,
        groupID: UUID? = nil,
        isDormant: Bool = false
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
        self.pinnedURL = pinnedURL
        self.customTitle = customTitle
        self.customSymbolName = customSymbolName
        self.groupID = groupID
        self.isDormant = isDormant
    }
}

public extension Tab {

    /// What a list should call this tab: the name the user gave it, else the page's own (§3.4a).
    ///
    /// Still possibly empty — a page that has not reported a title yet has none to give — so the
    /// surfaces that draw it keep their own fallback to the domain. This decides which title,
    /// not whether there is one.
    var listTitle: String {
        guard let customTitle, !customTitle.isEmpty else { return title }
        return customTitle
    }
}

/// A Space (§5.2): a named, coloured set of tabs backed by exactly one profile.
public struct Space: Identifiable, Sendable, Hashable, Codable {
    public var id: UUID
    public var name: String
    /// SF Symbol name — resolved to an image in `Design`, never here.
    public var symbolName: String
    public var gradient: GradientPair
    /// This Space's cookie jar: it backs `WKWebsiteDataStore(forIdentifier:)`.
    ///
    /// One per Space, never shared. WebKit can list the identifiers it holds but cannot
    /// say which name belongs to which, so the mapping is ours to keep — losing this
    /// column orphans a jar in `~/Library/WebKit/WebsiteDataStore/`.
    ///
    /// It used to live on a row of its own that several Spaces could point at. Nothing
    /// in the product wanted the sharing and everything in it had to explain the
    /// sharing, so `v6` gave every Space its own and the row went (§9).
    public var dataStoreIdentifier: UUID
    /// The picture the user gave this Space, as PNG, or nil for none.
    ///
    /// In the row rather than beside it: a file on disk is a second thing to keep in
    /// step with what it belongs to, and every operation here already knows how to keep
    /// one row honest — deleting the Space deletes it, and nothing can leave an orphan
    /// behind. It stays small because the app that writes it crops and downsamples
    /// first; the column holds what is drawn, not what was chosen.
    public var imageData: Data?
    public var order: Int

    public init(
        id: UUID = UUID(),
        name: String,
        symbolName: String,
        gradient: GradientPair,
        dataStoreIdentifier: UUID = UUID(),
        imageData: Data? = nil,
        order: Int = 0
    ) {
        self.id = id
        self.name = name
        self.symbolName = symbolName
        self.gradient = gradient
        self.dataStoreIdentifier = dataStoreIdentifier
        self.imageData = imageData
        self.order = order
    }
}

// MARK: - The all-zero data store identifier (§3.1)

public extension UUID {
    /// `00000000-0000-0000-0000-000000000000`.
    ///
    /// `WKWebsiteDataStore.dataStoreForIdentifier:` documents *"Throws exception if
    /// identifier is 0"*. That is an Objective-C exception, which Swift cannot catch,
    /// so a zero identifier is an uncatchable crash rather than an error a call site can
    /// handle. It is therefore checked at the persistence boundary, where it can still be
    /// turned into data, not at the WebKit boundary, where it can only be turned into a
    /// stack trace.
    static let zero = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))

    /// Whether this is the identifier WebKit refuses (see ``zero``).
    var isZero: Bool { self == .zero }
}

public extension Space {
    /// False when `dataStoreIdentifier` is the all-zero UUID — the one value that must
    /// never reach `WKWebsiteDataStore(forIdentifier:)`.
    ///
    /// `spaces.dataStoreIdentifier` is `NOT NULL UNIQUE` with no value check, and SQLite
    /// cannot gain a `CHECK` constraint without rebuilding the table every `tabs.spaceID`
    /// foreign key points at. So the invariant is enforced in Swift, on both sides of the
    /// column: ``BrowserStore/upsert(_:)-(Space)`` refuses to write a zero identifier, and
    /// ``BrowserStore/spaces()`` repairs one it finds on read.
    var hasUsableDataStoreIdentifier: Bool { !dataStoreIdentifier.isZero }

    /// This Space with a freshly minted `dataStoreIdentifier` if the persisted one is
    /// unusable, and unchanged otherwise.
    ///
    /// Minting a new one loses nothing recoverable: a zero identifier addresses no store
    /// on disk, because nothing could ever have created one under it. Everything else
    /// about the Space — its `id`, which every tab references and which is the only one
    /// §10 allows to sync, its name, its colour and its picture — survives. The user gets
    /// an empty cookie jar for that Space instead of a crash.
    func repairingDataStoreIdentifier() -> Space {
        guard !hasUsableDataStoreIdentifier else { return self }
        var repaired = self
        repaired.dataStoreIdentifier = UUID()
        return repaired
    }
}
