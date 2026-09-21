import Foundation
import os
import WebKit

// Deleting a profile's cookie jar (§3.2).
//
// This lives beside the `profiles` table rather than in `Engine/` because it is the disk
// half of the same fact: the `dataStoreIdentifier` column says which stores should exist,
// `WKWebsiteDataStore.allDataStoreIdentifiers` says which ones do, and the only correct
// thing to do with the difference is reconcile it.
//
// Deletion is a retry loop, not a call. `removeDataStoreForIdentifier:` fails while any
// `WKWebView` still holds the store, and a web view is released when ARC gets round to it,
// not when the user clicks Delete. Crest (MPL-2.0) and DuckDuckGo arrived at the same shape
// independently, which is the strongest signal in the research: try, clear the data as a
// fallback so the data goes even if the directory survives, back off, and if it still will
// not go, write the identifier down somewhere that outlives both the process and the database
// and finish the job on a later launch.
//
// Everything WebKit-shaped is behind ``WebsiteDataStoreRegistry`` so the loop can be driven
// against a store that refuses forever without needing a real one.

private let log = Logger(subsystem: "dk.trego.Luna", category: "store.websiteData")

// MARK: - Seams

/// The four things the removal loop needs from WebKit.
///
/// `@MainActor` because `WKWebsiteDataStore` is: the class carries `WK_SWIFT_UI_ACTOR` in
/// `WKWebsiteDataStore.h`, so every one of these calls is main-actor work anyway.
@MainActor
public protocol WebsiteDataStoreRegistry: Sendable {
    /// `allDataStoreIdentifiers`. WebKit is the registry (§3.1) — this, not SQLite, is the
    /// truth about what exists on disk.
    func identifiers() async -> Set<UUID>

    /// `removeDataStoreForIdentifier:`. Fails while a `WKWebView` still uses the store.
    func removeStore(_ identifier: UUID) async throws

    /// `removeData(ofTypes: allWebsiteDataTypes(), modifiedSince: .distantPast)` — §3.2's
    /// step 4. The directory may survive this; the cookies, logins and site data do not.
    func clearData(in identifier: UUID) async throws
}

/// Where the not-yet-removed identifiers are written down.
///
/// `UserDefaults`, not GRDB, and that is deliberate (§3.2 step 7). The whole point of
/// the queue is to survive things that go wrong, and "the user reset their data" or "the
/// database was wiped" is exactly the situation that strands a cookie jar with no row left
/// to name it. A queue stored in the database it is meant to outlive is not a queue.
///
/// `@MainActor` to match the rest of the loop; the loop is main-actor work because
/// `WKWebsiteDataStore` is.
@MainActor
public protocol PendingRemovalStorage: Sendable {
    func load() -> Set<UUID>
    func save(_ identifiers: Set<UUID>)
}

/// The backoff sleep, injected so a test of a six-step backoff does not take eight seconds.
@MainActor
public protocol RemovalBackoffClock: Sendable {
    func sleep(for duration: Duration) async
}

// MARK: - The real implementations

public struct SystemWebsiteDataStoreRegistry: WebsiteDataStoreRegistry {

    public init() {}

    public func identifiers() async -> Set<UUID> {
        Set(await WKWebsiteDataStore.allDataStoreIdentifiers)
    }

    public func removeStore(_ identifier: UUID) async throws {
        guard !identifier.isZero else { return }
        try await WKWebsiteDataStore.remove(forIdentifier: identifier)
    }

    public func clearData(in identifier: UUID) async throws {
        // The zero check is not defensive tidiness: `dataStoreForIdentifier:` throws an
        // Objective-C exception on zero, and Swift cannot catch it (§3.1).
        guard !identifier.isZero else { return }
        let store = WKWebsiteDataStore(forIdentifier: identifier)
        await store.removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
            modifiedSince: .distantPast
        )
    }
}

/// `@unchecked` because `UserDefaults` is not `Sendable` in the macOS 26.2 SDK even
/// though it is documented thread-safe ("NSUserDefaults is thread-safe"). Nothing here
/// mutates the reference, and every access is a single `UserDefaults` call, so the unchecked
/// claim is about the SDK's missing annotation rather than about this type's behaviour.
public struct UserDefaultsPendingRemovals: PendingRemovalStorage, @unchecked Sendable {

    /// Deliberately a plain key in the app's own domain: it has to be readable on the next
    /// launch by a build that may have nothing else left.
    public static let key = "luna.pendingStoreRemovals"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> Set<UUID> {
        let strings = defaults.stringArray(forKey: Self.key) ?? []
        return Set(strings.compactMap(UUID.init(uuidString:)))
    }

    public func save(_ identifiers: Set<UUID>) {
        guard !identifiers.isEmpty else {
            defaults.removeObject(forKey: Self.key)
            return
        }
        // Sorted so the stored value is stable and diffable by a human reading `defaults read`.
        defaults.set(identifiers.map(\.uuidString).sorted(), forKey: Self.key)
    }
}

public struct SystemBackoffClock: RemovalBackoffClock {
    public init() {}
    public func sleep(for duration: Duration) async {
        try? await Task.sleep(for: duration)
    }
}

// MARK: - The loop

/// §3.2's retry loop, the fallback data clear, the deferred queue and the orphan sweep.
@MainActor
public final class WebsiteDataStoreRemover {

    /// §3.2 step 6, exactly. Six retries after the first attempt: ~8 seconds in total, which
    /// is long enough for a web view that is on its way out and short enough that a user who
    /// deleted a Space does not sit watching a spinner. Anything slower than this is not
    /// slow, it is stuck, and step 7 is the answer to stuck.
    public static let backoff: [Duration] = [
        .milliseconds(125), .milliseconds(250), .milliseconds(500),
        .seconds(1), .seconds(2), .seconds(4)
    ]

    public enum Outcome: Equatable, Sendable {
        /// WebKit never listed it. Nothing on disk; nothing to do.
        case alreadyGone
        /// Confirmed absent from `allDataStoreIdentifiers` afterwards.
        case removed
        /// The directory outlived every attempt, but the site data in it was cleared, and
        /// the identifier is queued for a later launch. This is a success for the user —
        /// the cookies and logins are gone — and a to-do for the next sweep.
        case deferredAfterClearingData
        /// Queued, and even the fallback clear failed. The next launch tries again.
        case deferred
    }

    private let registry: WebsiteDataStoreRegistry
    private let storage: PendingRemovalStorage
    private let clock: RemovalBackoffClock

    /// Identifiers WebKit would not let go of, surviving both the process and the database.
    public private(set) var pendingIdentifiers: Set<UUID>

    public init(
        registry: WebsiteDataStoreRegistry = SystemWebsiteDataStoreRegistry(),
        storage: PendingRemovalStorage = UserDefaultsPendingRemovals(),
        clock: RemovalBackoffClock = SystemBackoffClock()
    ) {
        self.registry = registry
        self.storage = storage
        self.clock = clock
        pendingIdentifiers = storage.load()
    }

    /// Removes one store, following §3.2 end to end.
    ///
    /// Never throws and never reports failure for "WebKit still holds it": that case is
    /// queued and is the caller's cue to carry on deleting rows. The caller's only
    /// obligation is to have dropped its own cached `WKWebsiteDataStore` first — a cached
    /// reference is itself one of the things that blocks removal, which is why Ora's
    /// eviction-free `profileCache` would fail this call forever.
    @discardableResult
    public func remove(_ identifier: UUID) async -> Outcome {
        guard !identifier.isZero else { return .alreadyGone }

        var clearedData = false
        for attempt in 0...Self.backoff.count {
            // Step 2 / step 5. The re-check is not paranoia: the removal can complete as a
            // side effect of the fallback clear, or of the last web view finally dying.
            if await !registry.identifiers().contains(identifier) {
                forget(identifier)
                return attempt == 0 && !clearedData ? .alreadyGone : .removed
            }

            // Step 3.
            do {
                try await registry.removeStore(identifier)
            } catch {
                log.notice("removeDataStoreForIdentifier failed for \(identifier.uuidString, privacy: .public)")
            }
            if await !registry.identifiers().contains(identifier) {
                forget(identifier)
                return .removed
            }

            // Step 4, once. The user asked for their data gone, not for a directory gone.
            if !clearedData {
                do {
                    try await registry.clearData(in: identifier)
                    clearedData = true
                } catch {
                    log.error("fallback data clear failed for \(identifier.uuidString, privacy: .public)")
                }
                if await !registry.identifiers().contains(identifier) {
                    forget(identifier)
                    return .removed
                }
            }

            // Step 6.
            if attempt < Self.backoff.count {
                await clock.sleep(for: Self.backoff[attempt])
            }
        }

        // Step 7.
        enqueue(identifier)
        log.error(
            """
            Website data store \(identifier.uuidString, privacy: .public) survived \
            \(Self.backoff.count + 1) removal attempts; queued for the next launch.
            """
        )
        return clearedData ? .deferredAfterClearingData : .deferred
    }

    /// Diffs what WebKit has on disk against the profiles that still exist, and deletes the
    /// strays. Call it at launch. This is also the drain for the deferred queue.
    ///
    /// Single pass, no backoff, on purpose. WebKit is the registry, so a stray that
    /// refuses today is still listed tomorrow and costs nothing to find again — DuckDuckGo
    /// leans on exactly this: *"If this fails, we are going to still clean them next time as
    /// WebKit keeps track of all stores for us."* Backing off here would instead make a
    /// launch with four stubborn orphans sit for half a minute before the window appears.
    ///
    /// No fallback data clear either: clearing a store's data means instantiating it, which
    /// re-creates the directory this call is trying to be rid of. For an orphan — a store no
    /// profile names, so a store nothing can read — the directory is the only problem.
    ///
    /// - Parameter live: every `dataStoreIdentifier` still named by a `Profile` row.
    public func sweepOrphans(keeping live: Set<UUID>) async {
        let present = await registry.identifiers()
        let strays = present.subtracting(live).filter { !$0.isZero }
        guard !strays.isEmpty || !pendingIdentifiers.isEmpty else { return }

        for stray in strays {
            do {
                try await registry.removeStore(stray)
            } catch {
                log.notice("orphan sweep could not remove \(stray.uuidString, privacy: .public); retrying next launch")
            }
        }

        // What is still on disk and still unclaimed is what stays queued. An identifier a
        // live profile has reclaimed, or one WebKit no longer lists, leaves the queue —
        // otherwise the queue only ever grows, and a queue that only grows is a leak.
        let remaining = await registry.identifiers()
        let stillOrphaned = pendingIdentifiers.union(strays).intersection(remaining).subtracting(live)
        if stillOrphaned != pendingIdentifiers {
            pendingIdentifiers = stillOrphaned
            storage.save(stillOrphaned)
        }
        log.info("orphan sweep: \(strays.count) stray(s), \(stillOrphaned.count) still queued")
    }

    // MARK: - The queue

    private func enqueue(_ identifier: UUID) {
        guard !pendingIdentifiers.contains(identifier) else { return }
        pendingIdentifiers.insert(identifier)
        storage.save(pendingIdentifiers)
    }

    private func forget(_ identifier: UUID) {
        guard pendingIdentifiers.contains(identifier) else { return }
        pendingIdentifiers.remove(identifier)
        storage.save(pendingIdentifiers)
    }
}
