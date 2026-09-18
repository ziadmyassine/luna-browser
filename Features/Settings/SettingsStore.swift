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

enum Settings {

    /// Posted after any setting changes, on the main thread.
    static let didChange = Notification.Name("luna.settings.didChange")

    private static let layoutKey = "luna.chromeLayout"

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
}
