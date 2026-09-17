//
//  ProfileStore.swift
//  Luna
//
//  TODO.md §5.1: one `WKWebsiteDataStore` per Profile, and the *only* place
//  Luna turns a `Profile` into one.
//
//  Two facts drive everything here:
//    · WebKit can list identifiers (`allDataStoreIdentifiers`) but cannot tell
//      us which Space owns which. The UUID ↔ profile mapping is ours to keep,
//      and it lives in SQLite (`profiles.dataStoreIdentifier`). Losing that row
//      orphans a cookie jar in `~/Library/WebKit/WebsiteDataStore/<UUID>/`.
//    · `remove(forIdentifier:)` **fails while any live `WKWebView` still uses
//      the store.** Callers must tear down and deallocate every tab in the
//      profile first; `remove` then verifies against `allDataStoreIdentifiers`
//      rather than trusting a silent success.
//

import BrowserKit
import WebKit

enum ProfileStoreError: LocalizedError {
    /// WebKit reported no error but the identifier is still listed — in
    /// practice, something still holds a web view in that profile.
    case storeSurvivedRemoval(UUID)

    var errorDescription: String? {
        switch self {
        case let .storeSurvivedRemoval(identifier):
            "The website data for profile \(identifier) could not be removed."
        }
    }
}

/// Profile → `WKWebsiteDataStore`, cached so two tabs in one profile genuinely
/// share a cookie jar and two tabs in different profiles genuinely do not.
@MainActor
final class ProfileStore {

    private var live: [UUID: WKWebsiteDataStore] = [:]

    /// The store backing `profile`. Identified (never `.default()`): the default
    /// store has no identifier and cannot be adopted into one later (§5.5).
    func dataStore(for profile: Profile) -> WKWebsiteDataStore {
        if let existing = live[profile.id] { return existing }
        let store = WKWebsiteDataStore(forIdentifier: profile.dataStoreIdentifier)
        live[profile.id] = store
        return store
    }

    /// Deletes a profile's cookies, storage and caches from disk.
    ///
    /// - Precondition: every `WKWebView` in this profile has already been torn
    ///   down and released. WebKit fails the removal otherwise, which is why
    ///   this verifies instead of assuming.
    func remove(_ profile: Profile) async throws {
        // Drop our own reference first — the cache is one of the things keeping
        // the store alive.
        live[profile.id] = nil
        try await WKWebsiteDataStore.remove(forIdentifier: profile.dataStoreIdentifier)
        let remaining = await WKWebsiteDataStore.allDataStoreIdentifiers
        guard !remaining.contains(profile.dataStoreIdentifier) else {
            throw ProfileStoreError.storeSurvivedRemoval(profile.dataStoreIdentifier)
        }
    }
}
