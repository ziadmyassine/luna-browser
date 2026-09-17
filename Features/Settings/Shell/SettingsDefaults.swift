//
//  SettingsDefaults.swift
//  Luna
//
//  §6's key table, in **one** place, so "Restore all settings to defaults"
//  (§3.9) is a loop rather than a list someone forgets to extend.
//
//  Two rules this file exists to enforce:
//
//  1. **A key with no row here does not exist.** Adding a setting means adding
//     a line to `table`; `keys`, `register()` and `restoreAll()` all read it.
//  2. **The registered value must equal the reader's own fallback.** Every
//     section reads its key with a `?? default` of its own, and a registration
//     domain *satisfies* that read — `string(forKey:)` stops returning nil the
//     moment a value is registered. So a disagreement here does not produce a
//     second opinion, it silently overrides the first one. Each row below names
//     the reader it was copied from.
//
//  **Existing keys are not renamed** (§6): `blocking.httpsOnly` and
//  `luna.autoArchiveHours` are listed under the spellings they already have,
//  because they are settings the window shows and "restore all" must reach
//  them. `luna.activeSpaceID` is deliberately absent — it is session state, not
//  a setting, and resetting it would move the user's Space out from under them.
//

import AppKit
import BrowserKit

@MainActor
enum SettingsDefaults {

    /// Every key §6 declares, with the default the app behaves as if it had.
    ///
    /// An array rather than a dictionary so `keys` has a stable order — §6's —
    /// which is what makes a failing test name the key that drifted.
    private static let table: [(key: String, value: Any)] = [
        // §3.1 General — `GeneralSettings.onLaunch` / `.confirmClose`
        ("general.onLaunch", "restoreSession"),
        ("general.confirmClose", true),
        // §3.2 Appearance — `AppearanceSettings.theme` / `.showFavicons`, `Glass.optimisation`
        ("appearance.theme", "auto"),
        ("appearance.glassOptimisation", GlassOptimisation.auto.rawValue),
        ("appearance.showFavicons", true),
        // §3.4 Search — `SearchSettings.stored()`
        ("search.engine", SearchEngine.fallback.rawValue),
        ("search.customEngineURL", ""),
        // §3.5 Downloads — `DownloadDestination.folder` / `.autoOpenKey`
        ("downloads.directory", ""),
        ("downloads.askEachTime", false),
        ("downloads.autoOpen", false),
        ("downloads.clearPolicy", "onQuit"),
        // §3.9 Advanced — `WebViewFactory.Key`
        ("advanced.userAgent", WebViewFactory.UserAgentMode.default.rawValue),
        ("advanced.userAgentCustom", ""),
        ("advanced.showDevelopMenu", false),
        ("advanced.webInspector", true),
        // §2's persisted selection
        ("settings.lastSection", SettingsSectionRegistry.ids.first ?? ""),
        // §6's "existing keys are not renamed"
        ("blocking.httpsOnly", false),
        ("luna.autoArchiveHours", AutoArchive.defaultHours)
    ]

    /// Every key in `table`, in §6's order.
    static var keys: [String] { table.map(\.key) }

    /// Publishes the declared defaults into `UserDefaults`' registration
    /// domain. Called once, from `applicationWillFinishLaunching`.
    ///
    /// The registration domain is not persisted, so this runs on every launch
    /// by design: it is the table, not the disk, that says what a default is.
    static func register() {
        UserDefaults.standard.register(defaults: Dictionary(uniqueKeysWithValues: table.map { ($0.key, $0.value) }))
    }

    /// §3.9's "Restore all settings to defaults".
    ///
    /// **Removes rather than re-writes.** Removing a key drops back to the
    /// registration domain above, so there is exactly one place a default is
    /// written and no chance of the two drifting apart.
    ///
    /// **Removing the stored value is only half of it for a setting that is
    /// cached in memory.** `SearchSettings` reads `search.engine` once, at
    /// first touch, because §9.7's keystroke budget has no room for a defaults
    /// lookup — so without the reload below, "Restore all settings" would reset
    /// the engine on disk while the Command Bar kept using the old one until the
    /// next launch. `Glass.optimisation` and `AppearanceSection` are re-applied
    /// for the same reason.
    ///
    /// ponytail: three explicit re-reads rather than a notification. Add one
    /// when there is a fourth cache, not before.
    static func restoreAll() {
        // Assigned *before* the sweep because agent D's setter persists the key
        // as well as re-skinning every live glass view; the loop below is what
        // clears what it wrote.
        Glass.optimisation = .auto
        let defaults = UserDefaults.standard
        for key in keys { defaults.removeObject(forKey: key) }
        SearchSettings.reload()
        AppearanceSection.applyStoredTheme()
    }

    // MARK: - §2's persisted selection

    private static let lastSectionKey = "settings.lastSection"

    /// The section `⌘,` reopens on. Read through the table's default, so a
    /// first launch lands on the first section rather than on nothing.
    static var lastSection: String? {
        get { UserDefaults.standard.string(forKey: lastSectionKey) }
        set { UserDefaults.standard.set(newValue, forKey: lastSectionKey) }
    }
}
