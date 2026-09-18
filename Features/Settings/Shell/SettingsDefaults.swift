//
//  SettingsDefaults.swift
//  Luna
//
//  §6's key table, in **one** place, so §3.9's "Restore all settings" is a loop
//  rather than a list someone forgets to extend. Two rules:
//
//  1. **A key with no row here does not exist** — `keys`, `register()` and
//     `restoreAll()` all read `table`.
//  2. **The registered value must equal the reader's own fallback.** A
//     registration domain *satisfies* a `?? default` read, so a disagreement
//     here does not produce a second opinion — it silently overrides the first.
//     Each row names the reader it was copied from.
//
//  Existing keys keep their spellings (§6), and `luna.activeSpaceID` is
//  deliberately absent: it is session state, and resetting it would move the
//  user's Space out from under them.
//

import AppKit
import BrowserKit

@MainActor
enum SettingsDefaults {

    /// Every key §6 declares, with the default the app behaves as if it had.
    /// An array rather than a dictionary so `keys` has §6's order, which is
    /// what makes a failing test name the key that drifted.
    private static let table: [(key: String, value: Any)] = [
        // §3.1 General — `GeneralSettings.onLaunch` / `.confirmClose`
        ("general.onLaunch", "restoreSession"),
        ("general.confirmClose", true),
        // §3.2 Appearance — `AppearanceSection.theme`, `Glass.optimisation`
        ("appearance.theme", "auto"),
        ("appearance.glassOptimisation", GlassOptimisation.auto.rawValue),
        // §3.4 Search — `SearchSettings.stored()`
        ("search.engine", SearchEngine.fallback.rawValue),
        ("search.customEngineURL", ""),
        ("search.suggestions", true),
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

    /// Publishes the declared defaults into the registration domain, once, from
    /// `applicationWillFinishLaunching`. That domain is not persisted, so this
    /// runs every launch by design: the table says what a default is, not disk.
    static func register() {
        UserDefaults.standard.register(defaults: Dictionary(uniqueKeysWithValues: table.map { ($0.key, $0.value) }))
    }

    /// §3.9's "Restore all settings to defaults".
    ///
    /// **Removes rather than re-writes**, so a default is written in exactly one
    /// place. Removing the stored value is only half of it for a setting cached
    /// in memory: `SearchSettings` reads `search.engine` once at first touch
    /// (§9.7's keystroke budget has no room for a defaults lookup), so without
    /// the re-reads below the Command Bar would keep the old engine until the
    /// next launch. Three explicit ones rather than a notification — add one
    /// when there is a fourth cache, not before.
    static func restoreAll() {
        // Before the sweep: the setter persists the key as well as re-skinning
        // every live glass view, and the loop below clears what it wrote.
        Glass.optimisation = .auto
        let defaults = UserDefaults.standard
        for key in keys { defaults.removeObject(forKey: key) }
        SearchSettings.reload()
        AppearanceSection.applyStoredTheme()
    }

    // MARK: - §2's persisted selection

    private static let lastSectionKey = "settings.lastSection"

    /// The section `⌘,` reopens on, read through the table's default so a first
    /// launch lands on the first section rather than on nothing.
    static var lastSection: String? {
        get { UserDefaults.standard.string(forKey: lastSectionKey) }
        set { UserDefaults.standard.set(newValue, forKey: lastSectionKey) }
    }
}
