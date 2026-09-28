import Foundation
import WebKit

/// The parts of pages the user has hidden for good, as state a navigation can ask a
/// synchronous question of.
///
/// Shaped after `SitePermissions` for the same reason: the question is asked inside
/// `decidePolicyFor`, before the document exists, and that cannot wait on a database.
/// So the whole table is read once at launch and every write updates memory first.
///
/// A private window (§5.6) gets an instance of its own from ``scope(for:)``. It shows
/// what the user has hidden everywhere else, and what it hides or brings back itself
/// is kept in memory for as long as the window is open and never written down.
@MainActor
public final class HiddenElements {

    public typealias Element = BrowserStore.HiddenElement

    public static let shared = HiddenElements()

    private var byHost: [String: [Element]] = [:]
    /// A private instance's: shared elements it has brought back, as `host\nselector`.
    private var restoredHere: Set<String> = []
    private weak var store: BrowserStore?
    private let fallback: HiddenElements?

    /// Fires with the site whose list changed, so live pages on it can be re-dressed.
    public var onChange: (@MainActor (String) -> Void)?

    init(fallback: HiddenElements? = nil) {
        self.fallback = fallback
    }

    public static func scope(for dataStore: WKWebsiteDataStore) -> HiddenElements {
        guard !dataStore.isPersistent else { return shared }
        if let existing = objc_getAssociatedObject(dataStore, associationKey) as? HiddenElements {
            return existing
        }
        let scoped = HiddenElements(fallback: shared)
        objc_setAssociatedObject(dataStore, associationKey, scoped, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return scoped
    }

    private static let associationKey = UnsafeRawPointer(UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1))

    /// Call once at startup, beside `SitePermissions.start`.
    public func start(browserStore: BrowserStore?) {
        store = browserStore
        guard let browserStore else { return }
        Task { [weak self] in
            let loaded = try? await browserStore.hiddenElements()
            guard let self, let loaded else { return }
            byHost = loaded
        }
    }

    /// The key a site's list is filed under. `www.` is dropped because a banner
    /// hidden on `www.example.com` is the same banner on `example.com`, and a user
    /// who has to hide it twice will think the first time did not work.
    public static func site(of host: String?) -> String? {
        guard var host = ContentBlocker.normalise(host) else { return nil }
        if host.hasPrefix("www."), host.dropFirst(4).contains(".") { host.removeFirst(4) }
        return host
    }

    /// Oldest first, which is the order they were hidden in.
    public func elements(onHost host: String?) -> [Element] {
        guard let site = Self.site(of: host) else { return [] }
        let restored = restoredHere
        let inherited: [Element] = (fallback?.elements(onHost: site) ?? []).filter { element in
            !restored.contains(Self.key(site, element.selector))
        }
        let taken = Set(inherited.map(\.selector))
        let own: [Element] = (byHost[site] ?? []).filter { !taken.contains($0.selector) }
        return inherited + own
    }

    public func hide(_ element: Element, onHost host: String?) {
        guard let site = Self.site(of: host) else { return }
        restoredHere.remove(Self.key(site, element.selector))
        var list = byHost[site] ?? []
        guard !list.contains(where: { $0.selector == element.selector }) else { return }
        list.append(element)
        byHost[site] = list
        let store = store
        Task { try? await store?.hideElement(element, host: site) }
        onChange?(site)
    }

    public func restore(selector: String, onHost host: String?) {
        guard let site = Self.site(of: host) else { return }
        byHost[site]?.removeAll { $0.selector == selector }
        if byHost[site]?.isEmpty == true { byHost[site] = nil }
        if fallback?.elements(onHost: site).contains(where: { $0.selector == selector }) == true {
            restoredHere.insert(Self.key(site, selector))
        }
        let store = store
        Task { try? await store?.restoreElement(selector: selector, host: site) }
        onChange?(site)
    }

    /// The stylesheet that keeps them hidden. One rule per selector: a selector the
    /// engine cannot parse drops its own rule, where a list would take every other
    /// selector down with it.
    public func css(forHost host: String?) -> String {
        elements(onHost: host)
            .map { "\($0.selector) { display: none !important; }" }
            .joined(separator: "\n")
    }

    private static func key(_ site: String, _ selector: String) -> String { "\(site)\n\(selector)" }
}
