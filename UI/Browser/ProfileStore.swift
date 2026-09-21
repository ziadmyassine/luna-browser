//
//  ProfileStore.swift
//  Luna
//
//  TODO.md §5.1: one `WKWebsiteDataStore` per Profile, and the only place
//  Luna turns a `Profile` into one.
//
//  Two facts drive everything here:
//    · WebKit can list identifiers (`allDataStoreIdentifiers`) but cannot tell
//      us which Space owns which. The UUID ↔ profile mapping is ours to keep,
//      and it lives in SQLite (`profiles.dataStoreIdentifier`). Losing that row
//      orphans a cookie jar in `~/Library/WebKit/WebsiteDataStore/<UUID>/` —
//      which is what `sweepOrphans(keeping:)` exists to notice.
//    · `remove(forIdentifier:)` **fails while any live `WKWebView` still uses
//      the store**, and a web view goes away when ARC says so, not when the
//      user clicks Delete. So removal is a retry loop with a deferred queue
//      (spec §3.2), and the loop itself lives in `BrowserKit` —
//      `WebsiteDataStoreRemover` — where it can be tested without WebKit.
//      This type is the cache and the adapter; it is not the policy.
//

import BrowserKit
import WebKit

/// Profile → `WKWebsiteDataStore`, cached so two tabs in one profile genuinely
/// share a cookie jar and two tabs in different profiles genuinely do not.
@MainActor
final class ProfileStore {

    private var live: [UUID: WKWebsiteDataStore] = [:]
    private let remover: WebsiteDataStoreRemover

    init(remover: WebsiteDataStoreRemover = WebsiteDataStoreRemover()) {
        self.remover = remover
    }

    /// The store backing `profile`. Identified (never `.default()`): the default
    /// store has no identifier and cannot be adopted into one later (§5.5).
    ///
    /// The all-zero identifier never gets here — `BrowserStore` repairs it on read
    /// (§3.1) — but this is the call that would crash un-catchably if one ever did,
    /// so it checks anyway and answers with a non-persistent store: the safe wrong
    /// answer, because it leaks nothing into a profile the user did not mean.
    func dataStore(for profile: Profile) -> WKWebsiteDataStore {
        if let existing = live[profile.id] { return existing }
        guard profile.hasUsableDataStoreIdentifier else {
            assertionFailure("Profile \(profile.id) reached WebKit with the all-zero data store identifier.")
            return .nonPersistent()
        }
        let store = WKWebsiteDataStore(forIdentifier: profile.dataStoreIdentifier)
        live[profile.id] = store
        return store
    }

    /// Deletes a profile's cookies, storage and caches from disk (§3.2).
    ///
    /// - Precondition: every `WKWebView` in this profile has been torn down. This
    ///   call drops the cache entry, which is the one reference it owns; it
    ///   cannot release the caller's.
    ///
    /// Declared `throws` because it is a frozen API and a future failure mode
    /// belongs in the signature, but it does not currently throw — and in
    /// particular it never throws for "WebKit still holds it". That case is
    /// queued in `UserDefaults` and finished by the next launch's
    /// ``sweepOrphans(keeping:)``, because failing a Space deletion over a
    /// directory that will be gone in thirty seconds helps nobody.
    func remove(_ profile: Profile) async throws {
        // Drop our own reference FIRST — a cached store reference is itself one
        // of the things that blocks removal. Ora's `profileCache` has no eviction
        // path, so even calling `remove(forIdentifier:)` would fail there forever.
        live[profile.id] = nil
        await remover.remove(profile.dataStoreIdentifier)
    }

    /// Deletes every store on disk that no live profile names. Call at launch.
    ///
    /// Cheap, because WebKit is the registry (§3.1): a delete that failed
    /// yesterday is still listed today, so orphan recovery costs one diff.
    func sweepOrphans(keeping live: Set<UUID>) async {
        await remover.sweepOrphans(keeping: live)
    }
}
