import Foundation

/// §3.2's site menu, as state the rest of the app can ask a synchronous question of.
///
/// **In memory first, SQLite afterwards.** The two callers that matter cannot wait on a
/// database: `ContentBlocker.apply(to:host:)` runs inside `decidePolicyFor`, and the
/// Picture-in-Picture hand-off runs inside `activateTab`. So the whole table is read once
/// at launch — it is a handful of rows, one per site the user has ever answered for — and
/// every write updates the map before it is persisted.
///
/// Shaped after `ContentBlocker`'s own per-site exemptions for exactly that reason; the
/// two are the same problem, and the blocking one is only separate because it was written
/// first and its column is `NOT NULL`.
@MainActor
public final class SitePermissions {

    public static let shared = SitePermissions()

    /// Answered hosts only. Absent means "nobody has said", which resolves to the
    /// permission's own default rather than to `false`.
    private var answers: [BrowserStore.SitePermission: [String: Bool]] = [:]
    private weak var store: BrowserStore?

    /// Fires whenever an answer changes, so a live web view can be re-told.
    public var onChange: (@MainActor (BrowserStore.SitePermission, String) -> Void)?

    init() {}

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
        return answers[permission]?[host] ?? permission.defaultsToAllowed
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
