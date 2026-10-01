import Foundation
import WebKit

/// §3.2's site menu, as state the rest of the app can ask a synchronous question of.
///
/// In memory first, SQLite afterwards: `ContentBlocker.apply(to:host:)` runs inside
/// `decidePolicyFor` and the Picture-in-Picture hand-off inside `activateTab`, and neither
/// can wait on a database. Both tables are read once at launch, and every write updates
/// the map before it is persisted. `ContentBlocker`'s per-site exemptions are the same
/// shape for the same reason; they stay separate because their columns are `NOT NULL`.
///
/// There are three kinds of instance, and ``scope(for:)`` hands a data store the right
/// one. ``shared`` is the app's: it holds the answers that hold in every Space, and keeps
/// each Space's own on that Space's behalf. A Space's (``forSpace(_:)``) gives that
/// Space's answers to the `isPerSpace` permissions and the app's to the rest; every tab
/// built on the Space's data store gets it. A private window's (§5.6) keeps its own
/// answers in memory, where nothing outside the window can see them, and reads the app's
/// cross-Space ones. A private window is no Space's jar, so no Space's answers reach it.
@MainActor
public final class SitePermissions {

    public static let shared = SitePermissions()

    enum Role {
        case app
        case space(UUID, app: SitePermissions)
        case privateWindow(app: SitePermissions)
    }

    let role: Role

    /// The app's cross-Space answers, or a private window's every answer; a Space's
    /// instance keeps nothing here. Answered hosts only: absent means "nobody has said",
    /// which resolves to the permission's own default rather than to `false`.
    private var answers: [BrowserStore.SitePermission: [String: Bool]] = [:]
    /// The app's instance only: each Space's answers to the `isPerSpace` permissions.
    private var spaceAnswers: [UUID: [BrowserStore.SitePermission: [String: Bool]]] = [:]
    /// The app's instance only: one instance per Space, so the tab that asks and the
    /// site menu that shows the answer hold the same one.
    private var spaces: [UUID: SitePermissions] = [:]
    /// Nil on a private instance, which is what keeps its writes off disk.
    weak var store: BrowserStore?

    /// §18.2's zoom per site, on the app's instance and a private window's; a Space's
    /// reads the app's (`SitePermissions+SiteSettings.swift`).
    var zooms: [String: Double] = [:]
    /// §4.6's user agent per site, kept the same way. A private window's nil is its own
    /// "as in Settings", which the app's choice must not show through.
    var userAgents: [String: WebViewFactory.UserAgentMode?] = [:]

    /// `ContentBlocker`'s two per-site answers, as a private instance overrides them.
    /// The shared answers stay in `ContentBlocker`; see its `isDisabled(forHost:in:)`.
    var blockingDisabled: [String: Bool] = [:]
    var insecureAllowed: Set<String> = []

    /// Fires whenever an answer this instance gives changes, so a live web view can be re-told.
    public var onChange: (@MainActor (BrowserStore.SitePermission, String) -> Void)?

    /// - Parameter fallback: makes a private window's instance, which reads through to it.
    init(fallback: SitePermissions? = nil) {
        role = fallback.map { .privateWindow(app: $0) } ?? .app
    }

    private init(space id: UUID, app: SitePermissions) {
        role = .space(id, app: app)
    }

    public var isPrivate: Bool {
        if case .privateWindow = role { true } else { false }
    }

    /// The Space whose answers these are, or nil for the app's and a private window's.
    public var spaceID: UUID? {
        if case let .space(id, _) = role { id } else { nil }
    }

    /// The instance a web view on `dataStore` answers to: its Space's, once
    /// ``bind(_:toSpace:)`` has said which Space that is, and for a non-persistent store
    /// an instance that lives exactly as long as the store does. Keyed on the store
    /// because every tab of a private window is built on the same one and no tab of any
    /// other window is. Any other persistent store answers to ``shared``.
    public static func scope(for dataStore: WKWebsiteDataStore) -> SitePermissions {
        if let existing = objc_getAssociatedObject(dataStore, associationKey) as? SitePermissions {
            return existing
        }
        guard !dataStore.isPersistent else { return shared }
        let scoped = SitePermissions(fallback: shared)
        objc_setAssociatedObject(dataStore, associationKey, scoped, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return scoped
    }

    /// Makes every tab built on `dataStore` answer with Space `id`'s answers. Called
    /// where a Space's data store is made.
    public static func bind(_ dataStore: WKWebsiteDataStore, toSpace id: UUID) {
        objc_setAssociatedObject(dataStore, associationKey, shared.forSpace(id), .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    private static let associationKey = UnsafeRawPointer(UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1))

    /// Space `id`'s instance. Asked of a Space's or a private window's instance, the
    /// answer is that instance: neither has Spaces of its own.
    public func forSpace(_ id: UUID) -> SitePermissions {
        guard case .app = role else { return self }
        if let existing = spaces[id] { return existing }
        let scoped = SitePermissions(space: id, app: self)
        spaces[id] = scoped
        return scoped
    }

    /// Lets go of a deleted Space's answers. The database has already let go of them:
    /// its rows cascade with the Space's.
    public func forgetSpace(_ id: UUID) {
        spaceAnswers[id] = nil
        spaces[id] = nil
    }

    /// Call once at startup, beside `ContentBlocker.start`.
    public func start(browserStore: BrowserStore?) {
        store = browserStore
        guard let browserStore else { return }
        Task { [weak self] in
            let loaded = try? await browserStore.sitePermissions()
            let bySpace = try? await browserStore.spaceSitePermissions()
            let zoomed = try? await browserStore.siteZooms()
            let agents = try? await browserStore.siteUserAgents()
            guard let self else { return }
            // Under anything answered while the read was out, which is newer.
            answers.merge(loaded ?? [:], uniquingKeysWith: Self.keepingGiven)
            spaceAnswers.merge(bySpace ?? [:]) { given, read in given.merging(read, uniquingKeysWith: Self.keepingGiven) }
            zooms.merge(zoomed ?? [:]) { given, _ in given }
            userAgents.merge((agents ?? [:]).mapValues { .some($0) }) { given, _ in given }
        }
    }

    private static func keepingGiven(_ given: [String: Bool], _ read: [String: Bool]) -> [String: Bool] {
        given.merging(read) { mine, _ in mine }
    }

    public func isAllowed(_ permission: BrowserStore.SitePermission, forHost host: String?) -> Bool {
        guard let host = ContentBlocker.normalise(host) else { return permission.defaultsToAllowed }
        return answer(permission, host) ?? permission.defaultsToAllowed
    }

    /// The user's answer for this site, or nil when they have not given one — which is
    /// what tells a site that may ask (§17.8) from one that was told no.
    public func answer(_ permission: BrowserStore.SitePermission, forHost host: String?) -> Bool? {
        guard let host = ContentBlocker.normalise(host) else { return nil }
        return answer(permission, host)
    }

    private func answer(_ permission: BrowserStore.SitePermission, _ host: String) -> Bool? {
        switch role {
        case .app:
            answers[permission]?[host]
        case let .space(id, app):
            permission.isPerSpace ? app.spaceAnswers[id]?[permission]?[host] : app.answer(permission, host)
        case let .privateWindow(app):
            answers[permission]?[host] ?? (permission.isPerSpace ? nil : app.answer(permission, host))
        }
    }

    /// The app's instance keeps a per-Space answer given to it in memory only: it is
    /// asked one only for a store no Space owns, which has no Space to file it under.
    public func setAllowed(_ allowed: Bool, _ permission: BrowserStore.SitePermission, forHost host: String) {
        guard let host = ContentBlocker.normalise(host) else { return }
        switch role {
        case .app:
            answers[permission, default: [:]][host] = allowed
            guard !permission.isPerSpace else { break }
            let store = store
            Task { try? await store?.setSitePermission(permission, allowed: allowed, host: host) }
        case let .space(id, app):
            guard permission.isPerSpace else {
                app.setAllowed(allowed, permission, forHost: host)
                break
            }
            app.spaceAnswers[id, default: [:]][permission, default: [:]][host] = allowed
            let store = app.store
            Task { try? await store?.setSitePermission(permission, allowed: allowed, host: host, inSpace: id) }
        case .privateWindow:
            answers[permission, default: [:]][host] = allowed
        }
        onChange?(permission, host)
    }

    /// Every host that has been answered for, whichever way — what a settings surface
    /// would list if one ever wanted to. A private window's lists its own answers only.
    public func answeredHosts(_ permission: BrowserStore.SitePermission) -> [String: Bool] {
        switch role {
        case .app, .privateWindow:
            answers[permission] ?? [:]
        case let .space(id, app):
            permission.isPerSpace ? app.spaceAnswers[id]?[permission] ?? [:] : app.answeredHosts(permission)
        }
    }
}
