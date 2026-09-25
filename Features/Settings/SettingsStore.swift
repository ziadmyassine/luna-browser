//
//  SettingsStore.swift
//  Luna
//
//  Luna's preferences, such as they are. One setting today — which chrome
//  layout the window wears — and the shape for the rest.
//
//  It exists because `⌘S` stopped meaning "swap the layout". Hiding the sidebar
//  and choosing between the layouts are decisions taken at different rates —
//  one a reflex several times a minute, the other a preference taken once — and
//  a keystroke that did both meant the reflex silently changed the preference.
//
//  `UserDefaults`, like `SidebarResizeHandle.storedWidth`: Luna has no settings
//  file and no reason to invent one for a single enum. The notification lets a
//  running window follow a change made in the Settings window without either
//  knowing about the other.
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

/// Which side of the window the sidebar stands on. Only the sidebar has a
/// choice: the top bar's tabs always start at its leading edge.
///
/// A stored `centre` from before the top bar lost its choice does not decode,
/// and reads as the left the sidebar always gave it.
enum TabsPosition: String, CaseIterable, Sendable {
    case left
    case right

    var title: String {
        switch self {
        case .left: String(localized: "Left")
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
    private static let macCornersKey = "luna.macWindowCorners"
    private static let tabHintKey = "luna.pinHint.tabDismissed"
    private static let folderHintKey = "luna.pinHint.folderDismissed"

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

    /// §3's sidebar side. Left by default, where it has always been.
    static var tabsPosition: TabsPosition {
        get {
            UserDefaults.standard.string(forKey: tabsKey)
                .flatMap(TabsPosition.init(rawValue:)) ?? .left
        }
        set {
            guard newValue != tabsPosition else { return }
            UserDefaults.standard.set(newValue.rawValue, forKey: tabsKey)
            NotificationCenter.default.post(name: didChange, object: nil)
        }
    }

    /// The corner macOS gives its own windows instead of Luna's rounder one.
    /// Off by default: Luna's corner is the reference's.
    static var macWindowCorners: Bool {
        get { UserDefaults.standard.bool(forKey: macCornersKey) }
        set {
            guard newValue != macWindowCorners else { return }
            UserDefaults.standard.set(newValue, forKey: macCornersKey)
            NotificationCenter.default.post(name: didChange, object: nil)
        }
    }

    /// Which window edge §3's sidebar stands on.
    static var sidebarEdge: SidebarEdge {
        tabsPosition == .right ? .trailing : .leading
    }

    /// §1's width span as the layout on screen can honour it: the same
    /// `default` and `max`, and the minimum the column standing there actually
    /// needs.
    ///
    /// `Metric.sidebarWidth.min` is §3.1's arithmetic, and §3.1 is only in the
    /// column at full width in one of the four combinations these two settings
    /// make. §3.2b takes the pill and the three circles with it onto the page
    /// (`SidebarControlRow.showsButtons`), leaving a row that holds nothing but
    /// the traffic lights' corner. A trailing column has no lights to clear at
    /// all — macOS keeps them at the window's top-left, so a column on the
    /// other edge does not contain them — and its toggle starts at `rowInset`
    /// rather than 78 pt in, which is 86 pt off the head's 243. Either one puts
    /// the head under §3.5's foot, and then the foot is the answer.
    ///
    /// Read, never written back: a width dragged to 190 with the pill on the
    /// page is remembered as 190, reads as 250 while the pill is in the column,
    /// and is 190 again when it leaves. Rewriting it on the way past would make
    /// moving a setting twice a way of losing a width the user chose, which is
    /// the rule `SidebarResizeHandle.storedWidth` already keeps for `⌘S`.
    static var sidebarWidth: SpanMetric {
        sidebarWidth(searchBarOnPage: searchBarIsOnPage, edge: sidebarEdge)
    }

    /// The same answer, told rather than read. Both floors are arithmetic, so
    /// they can be checked without a `UserDefaults` to write into — and writing
    /// into one to ask a question posts `didChange` to every window listening.
    static func sidebarWidth(searchBarOnPage: Bool, edge: SidebarEdge) -> SpanMetric {
        var span = Tokens.Metric.sidebarWidth
        if searchBarOnPage || edge == .trailing {
            span.min = Tokens.Metric.sidebarFootFloor
        }
        return span
    }

    /// Whether §3.3a's two wells are still worth drawing — the advice a Space
    /// with nothing pinned shows where its tiles and its folders would be.
    ///
    /// Stored as the dismissal rather than as the showing, so the default is
    /// the advice: a key that has never been written reads as `false` here and
    /// as "show it" there, which is what a user who has never heard of either
    /// setting should get.
    ///
    /// One answer for the whole app, not one per Space. It is a piece of advice
    /// and advice already taken does not need repeating in the Space next door
    /// — where, by definition, the user is now doing the thing it describes.
    static var showsPinnedTabHint: Bool {
        get { !UserDefaults.standard.bool(forKey: tabHintKey) }
        set { setHint(tabHintKey, shows: newValue, was: showsPinnedTabHint) }
    }

    /// §3.3a's other well: the §3.4b tier, which holds folders.
    static var showsPinnedFolderHint: Bool {
        get { !UserDefaults.standard.bool(forKey: folderHintKey) }
        set { setHint(folderHintKey, shows: newValue, was: showsPinnedFolderHint) }
    }

    private static func setHint(_ key: String, shows: Bool, was: Bool) {
        guard shows != was else { return }
        UserDefaults.standard.set(!shows, forKey: key)
        NotificationCenter.default.post(name: didChange, object: nil)
    }

    /// Whether §3.2b's bar is the one on screen — the single reader both the
    /// sidebar and the page bar are driven from.
    ///
    /// Two keys, one answer. The placement is only a question in sidebar
    /// layout; §4's top bar has no page bar at all — its address is edited from
    /// the tab on screen (`TopBarTabStrip`) or `⌘L`, in the Command Bar.
    static var searchBarIsOnPage: Bool {
        chromeLayout == .sidebar && searchBarPlacement == .page
    }
}
