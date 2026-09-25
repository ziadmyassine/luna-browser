import Foundation
import WebKit

/// §3.2's site menu, as state the rest of the app can ask a synchronous question of.
///
/// In memory first, SQLite afterwards. The two callers that matter cannot wait on a
/// database: `ContentBlocker.apply(to:host:)` runs inside `decidePolicyFor`, and the
/// Picture-in-Picture hand-off runs inside `activateTab`. So the whole table is read once
/// at launch — it is a handful of rows, one per site the user has ever answered for — and
/// every write updates the map before it is persisted.
///
/// Shaped after `ContentBlocker`'s own per-site exemptions for exactly that reason; the
/// two are the same problem, and the blocking one is only separate because it was written
/// first and its column is `NOT NULL`.
///
/// A private window (§5.6) gets an instance of its own from ``scope(for:)``: it reads
/// through to ``shared``, so the user's standing answers still hold there, and it keeps
/// its own answers in memory, where nothing outside that window can see them.
@MainActor
public final class SitePermissions {

    public static let shared = SitePermissions()

    /// Answered hosts only. Absent means "nobody has said", which resolves to the
    /// permission's own default rather than to `false`.
    private var answers: [BrowserStore.SitePermission: [String: Bool]] = [:]
    /// Nil on a private instance, which is what keeps its writes off disk.
    private weak var store: BrowserStore?
    /// A private instance's: asked whatever this one has not been told itself.
    private let fallback: SitePermissions?

    /// `ContentBlocker`'s two per-site answers, as a private instance overrides them.
    /// The shared answers stay in `ContentBlocker`; see its `isDisabled(forHost:in:)`.
    var blockingDisabled: [String: Bool] = [:]
    var insecureAllowed: Set<String> = []

    /// Fires whenever an answer changes, so a live web view can be re-told.
    public var onChange: (@MainActor (BrowserStore.SitePermission, String) -> Void)?

    init(fallback: SitePermissions? = nil) {
        self.fallback = fallback
    }

    public var isPrivate: Bool { fallback != nil }

    /// The instance a web view on `dataStore` answers to: ``shared`` for a persistent
    /// store, and for a non-persistent one an instance that lives exactly as long as
    /// the store does. Keyed on the store because every tab of a private window is
    /// built on the same one and no tab of any other window is.
    public static func scope(for dataStore: WKWebsiteDataStore) -> SitePermissions {
        guard !dataStore.isPersistent else { return shared }
        if let existing = objc_getAssociatedObject(dataStore, associationKey) as? SitePermissions {
            return existing
        }
        let scoped = SitePermissions(fallback: shared)
        objc_setAssociatedObject(dataStore, associationKey, scoped, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return scoped
    }

    private static let associationKey = UnsafeRawPointer(UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1))

    /// Call once at startup, beside `ContentBlocker.start`.
    public func start(browserStore: BrowserStore?) {
        store = browserStore
        guard let browserStore else { return }
        Task { [weak self] in
            let loaded = try? await browserStore.sitePermissions()
            guard let self, let loaded else { return }
            answers = loaded
        }
    }

    public func isAllowed(_ permission: BrowserStore.SitePermission, forHost host: String?) -> Bool {
        guard let host = ContentBlocker.normalise(host) else { return permission.defaultsToAllowed }
        return answer(permission, host) ?? permission.defaultsToAllowed
    }

    private func answer(_ permission: BrowserStore.SitePermission, _ host: String) -> Bool? {
        answers[permission]?[host] ?? fallback?.answer(permission, host)
    }

    public func setAllowed(_ allowed: Bool, _ permission: BrowserStore.SitePermission, forHost host: String) {
        guard let host = ContentBlocker.normalise(host) else { return }
        answers[permission, default: [:]][host] = allowed
        let store = store
        Task { try? await store?.setSitePermission(permission, allowed: allowed, host: host) }
        onChange?(permission, host)
    }

    /// Every host that has been answered for, whichever way — what a settings surface
    /// would list if one ever wanted to.
    public func answeredHosts(_ permission: BrowserStore.SitePermission) -> [String: Bool] {
        answers[permission] ?? [:]
    }
}
