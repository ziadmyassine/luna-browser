//
//  SyncedDefaults.swift
//  Luna
//
//  Which settings sync (docs/SYNC-PLAN.md §5), recording them into the
//  store's mirror, and applying the ones that arrive from another Mac.
//

import AppKit
import BrowserKit

@MainActor
enum SyncedDefaults {

    /// `advanced.allowControl` and `passwords.requireAuthentication` are left
    /// out on purpose: turning either off on one Mac must not weaken another.
    static let keys = Set([
        AppearanceSection.themeKey, "luna.chromeLayout", "luna.tabsPosition", "luna.searchBarPlacement", "luna.macWindowCorners",
        SearchSettings.engineKey, SearchSettings.customEngineKey, SearchSettings.suggestionsKey,
        SearchSettings.settingsResultsKey, SearchSettings.shortcutResultsKey,
        "luna.autoArchiveHours", GeneralSection.confirmQuitKey, DownloadDestination.autoOpenKey,
        "blocking.httpsOnly", WebViewFactory.Key.userAgent, WebViewFactory.Key.customUserAgent,
        PasswordSettings.Key.enabled, PasswordSettings.Key.offerToSave, PasswordSettings.Key.generate,
        PopupPolicy.Key.mode, PopupPolicy.Key.showsAddress, PopupNoticeSettings.notifiesKey,
        ReadingPreferences.Key.typeface, ReadingPreferences.Key.size, ReadingPreferences.Key.width,
        ReadingPreferences.Key.page, ReadingPreferences.Key.outline, ReadingPreferences.Key.wrap
    ]).union(
        // `ContentBlocker.Key.enabled`, which BrowserKit keeps internal.
        ContentBlocker.Category.allCases.map { "blocking.enabled.\($0.rawValue)" }
    )

    /// `KeyBindings`' remaps, one key per command.
    private static let shortcutPrefix = "luna.shortcut."

    static func syncs(_ key: String) -> Bool {
        keys.contains(key) || key.hasPrefix(shortcutPrefix)
    }

    /// Mirrors what this Mac has set into the store. Only the persistent domain:
    /// `SettingsDefaults.register()` puts every default in the registration one,
    /// and a Mac turning sync on must not send defaults it never chose.
    static func record(
        _ defaults: UserDefaults = .standard, domain: String = Bundle.main.bundleIdentifier ?? "", to store: BrowserStore
    ) async throws {
        var values: [String: Data] = [:]
        for (key, value) in defaults.persistentDomain(forName: domain) ?? [:] where syncs(key) {
            values[key] = try? PropertyListSerialization.data(fromPropertyList: value, format: .binary, options: 0)
        }
        try await store.recordSyncedDefaults(values)
    }

    /// The handler for `SyncCoordinator`'s `applySettings`. The store takes the
    /// value first, so the defaults change it causes finds the mirror already
    /// matching and records nothing. A key outside the allowlist is dropped
    /// here, whatever another Mac sent.
    static func apply(_ changes: SyncChangeSet, to defaults: UserDefaults = .standard, store: BrowserStore) async throws {
        let allowed = SyncChangeSet(
            modifications: changes.modifications.filter { syncs($0.recordName) },
            deletions: changes.deletions.filter { syncs($0.recordName) }
        )
        guard !allowed.modifications.isEmpty || !allowed.deletions.isEmpty else { return }
        for (key, data) in try await store.applyRemoteSettings(allowed) {
            if let value = data.flatMap({ try? PropertyListSerialization.propertyList(from: $0, format: nil) }) {
                defaults.set(value, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
        // The same refresh `SettingsDefaults.restoreAll()` gives its caches.
        SearchSettings.reload()
        AppearanceSection.applyStoredTheme()
        NotificationCenter.default.post(name: Settings.didChange, object: nil)
        NotificationCenter.default.post(name: KeyBindings.didChange, object: nil)
    }

    private static var pending: Task<Void, Never>?

    /// Records a second after the last defaults change, then `recorded` hands
    /// the outbox to the engine (`SyncCoordinator.pushOutbox`).
    static func observe(_ store: BrowserStore, recorded: @escaping @Sendable () async -> Void) -> NSObjectProtocol {
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                pending?.cancel()
                pending = Task {
                    try? await Task.sleep(for: .seconds(1))
                    guard !Task.isCancelled else { return }
                    try? await record(to: store)
                    await recorded()
                }
            }
        }
    }
}
