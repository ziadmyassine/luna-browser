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
}
