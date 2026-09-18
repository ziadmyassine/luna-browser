//
//  SettingsStore.swift
//  Luna
//
//  Luna's preferences, such as they are. One setting today — which chrome
//  layout the window wears — and the shape for the rest.
//
//  It exists because `⌘S` stopped meaning "swap the layout". Hiding the sidebar
//  and choosing between the two layouts are different decisions taken at
//  different rates: one is a reflex, several times a minute; the other is a
//  preference, taken once. A keystroke that did both meant the reflex silently
//  changed the preference.
//
//  `UserDefaults`, like `SidebarResizeHandle.storedWidth` — Luna has no
//  settings file and no reason to invent one for a single enum. The
//  notification is what lets a running window follow a change made in the
//  Settings window without either of them knowing about the other.
//

import Foundation

/// Which chrome the window wears (§3 vs §4). The user's choice, not a mode the
/// app switches out from under them.
enum ChromeLayoutPreference: String, CaseIterable, Sendable {
    /// §3: the sidebar column.
    case sidebar
    /// §4: the single top bar, with the tab strip in it.
    case topBar

    var title: String {
        switch self {
        case .sidebar: String(localized: "Sidebar")
        case .topBar: String(localized: "Top bar")
        }
    }
}

/// Where §3.2's address pill lives when the window is wearing the sidebar
/// (§3.2b). Meaningless in top-bar layout, which has exactly one place to put a
/// pill and puts it there.
enum SearchBarPlacement: String, CaseIterable, Sendable {
    /// §3.2 as built: the pill at the head of the sidebar, under §3.1's row.
    case sidebar
    /// The pill — and §3.1's three circles with it — floating over the top of
    /// the page, collapsing to the domain as the page scrolls. See
    /// `PageChromeBar`.
    case page

    var title: String {
        switch self {
        case .sidebar: String(localized: "In the sidebar")
        case .page: String(localized: "On the page")
        }
    }
}

/// **Where the tabs are.** One setting, because it is one question the user is
/// asking — and the two layouts have different answers available to them.
///
/// §3's sidebar is a column, so it has two sides and no middle. §4's strip runs
/// along a bar, so it has all three. The stored value is therefore the superset,
/// and a sidebar reads `.centre` as `.left`: a preference the current layout
/// cannot honour is remembered rather than rewritten, so switching back to the
/// top bar gets the centre the user asked for instead of whatever the sidebar
/// had to fall back to.
enum TabsPosition: String, CaseIterable, Sendable {
    case left
    case centre
    case right

    /// What the layout can actually offer. The Settings row is built from this,
    /// which is why the middle segment appears and disappears with the layout
    /// rather than sitting there dimmed.
    static func cases(for layout: ChromeLayoutPreference) -> [TabsPosition] {
        switch layout {
        case .sidebar: [.left, .right]
        case .topBar: [.left, .centre, .right]
        }
    }

    var title: String {
        switch self {
        case .left: String(localized: "Left")
        case .centre: String(localized: "Centre")
        case .right: String(localized: "Right")
        }
    }
}

enum Settings {

    /// Posted after any setting changes, on the main thread.
    static let didChange = Notification.Name("luna.settings.didChange")

    private static let layoutKey = "luna.chromeLayout"
    private static let tabsKey = "luna.tabsPosition"
    private static let searchBarKey = "luna.searchBarPlacement"

    /// Defaults to the sidebar: it is the layout the reference shows and the
    /// one §3 is written against.
    static var chromeLayout: ChromeLayoutPreference {
        get {
            UserDefaults.standard.string(forKey: layoutKey)
                .flatMap(ChromeLayoutPreference.init(rawValue:)) ?? .sidebar
        }
        set {
            guard newValue != chromeLayout else { return }
            UserDefaults.standard.set(newValue.rawValue, forKey: layoutKey)
            NotificationCenter.default.post(name: didChange, object: nil)
        }
    }

    /// Defaults to the sidebar, because that is where it has always been: a
    /// setting that moves a landmark must not move it for a user who has never
    /// heard of the setting.
    static var searchBarPlacement: SearchBarPlacement {
        get {
            UserDefaults.standard.string(forKey: searchBarKey)
                .flatMap(SearchBarPlacement.init(rawValue:)) ?? .sidebar
        }
        set {
            guard newValue != searchBarPlacement else { return }
            UserDefaults.standard.set(newValue.rawValue, forKey: searchBarKey)
            NotificationCenter.default.post(name: didChange, object: nil)
        }
    }

    /// §3/§4's tab position. **Centre by default**, which is where §4's strip
    /// belongs and which a sidebar reads as the left it has always been.
    static var tabsPosition: TabsPosition {
        get {
            UserDefaults.standard.string(forKey: tabsKey)
                .flatMap(TabsPosition.init(rawValue:)) ?? .centre
        }
        set {
            guard newValue != tabsPosition else { return }
            UserDefaults.standard.set(newValue.rawValue, forKey: tabsKey)
            NotificationCenter.default.post(name: didChange, object: nil)
        }
    }

    /// The tab position as the layout on screen can honour it: a sidebar has
    /// two sides, so `.centre` reads as `.left` there.
    static func tabsPosition(in layout: ChromeLayoutPreference) -> TabsPosition {
        let stored = tabsPosition
        return TabsPosition.cases(for: layout).contains(stored) ? stored : .left
    }

    /// Which window edge §3's sidebar stands on. A column has two sides, so a
    /// stored `.centre` — which only the top bar can honour — reads as the left.
    static var sidebarEdge: SidebarEdge {
        tabsPosition(in: .sidebar) == .right ? .trailing : .leading
    }

    /// Whether §3.2b's bar is the one on screen — the single reader both the
    /// sidebar and the page bar are driven from.
    ///
    /// **Two keys, one answer.** The placement is only meaningful in sidebar
    /// layout, and asking each surface to remember that is how the sidebar ends
    /// up having dropped its pill in a layout that has no page bar to put it
    /// in.
    static var searchBarIsOnPage: Bool {
        chromeLayout == .sidebar && searchBarPlacement == .page
    }
}
