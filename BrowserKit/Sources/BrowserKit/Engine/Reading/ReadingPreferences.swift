import Foundation

/// How Reader and the Markdown reader set their text. Global rather than per
/// site, and synced (`SyncedDefaults`), so a reading page looks the same on
/// every Mac the user reads on.
public struct ReadingPreferences: Equatable, Sendable {

    public enum Key {
        public static let typeface = "reading.typeface"
        public static let size = "reading.size"
        public static let width = "reading.width"
        public static let page = "reading.page"
        public static let outline = "reading.outline"
        public static let wrap = "reading.wrap"
    }

    public enum Typeface: String, CaseIterable, Sendable {
        case serif, sans, mono

        /// The stacks the reading sheet already used for body, headings and code.
        var stack: String {
            switch self {
            case .serif: #"ui-serif,"New York",Georgia,serif"#
            case .sans: "-apple-system,BlinkMacSystemFont,sans-serif"
            case .mono: "ui-monospace,Menlo,monospace"
            }
        }
    }

    public enum Width: String, CaseIterable, Sendable {
        case narrow, medium, wide

        /// The text column's maximum width. Medium is the 680 Reader had
        /// before it had preferences, so the default page did not move.
        public var points: Int {
            switch self {
            case .narrow: 580
            case .medium: 680
            case .wide: 820
            }
        }
    }

    /// Stored and handed to the page; the colours behind the last three come
    /// with the reading tokens.
    public enum Page: String, CaseIterable, Sendable {
        case match, paper, sepia, night
    }

    public static let sizes = 14 ... 28

    public var typeface = Typeface.serif
    public var size = 19 {
        didSet { size = min(max(size, Self.sizes.lowerBound), Self.sizes.upperBound) }
    }
    public var width = Width.medium
    public var page = Page.match
    public var outline = true
    /// Whether long code lines wrap rather than scroll.
    public var wrap = true

    public init() {}

    public static func stored(in defaults: UserDefaults = .standard) -> ReadingPreferences {
        var preferences = ReadingPreferences()
        if let typeface = defaults.string(forKey: Key.typeface).flatMap(Typeface.init(rawValue:)) {
            preferences.typeface = typeface
        }
        if let size = defaults.object(forKey: Key.size) as? Int { preferences.size = size }
        if let width = defaults.string(forKey: Key.width).flatMap(Width.init(rawValue:)) { preferences.width = width }
        if let page = defaults.string(forKey: Key.page).flatMap(Page.init(rawValue:)) { preferences.page = page }
        if let outline = defaults.object(forKey: Key.outline) as? Bool { preferences.outline = outline }
        if let wrap = defaults.object(forKey: Key.wrap) as? Bool { preferences.wrap = wrap }
        return preferences
    }

    public func store(in defaults: UserDefaults = .standard) {
        defaults.set(typeface.rawValue, forKey: Key.typeface)
        defaults.set(size, forKey: Key.size)
        defaults.set(width.rawValue, forKey: Key.width)
        defaults.set(page.rawValue, forKey: Key.page)
        defaults.set(outline, forKey: Key.outline)
        defaults.set(wrap, forKey: Key.wrap)
    }

    /// What the page script reads: the enums by name, as the root's data attributes.
    var script: [String: Any] {
        [
            "typeface": typeface.rawValue, "size": size, "width": width.rawValue,
            "page": page.rawValue, "outline": outline, "wrap": wrap
        ]
    }
}
