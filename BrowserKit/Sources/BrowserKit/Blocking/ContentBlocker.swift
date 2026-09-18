import CryptoKit
import Foundation
import WebKit

/// Luna's content blocking (§17.1–§17.4, §17.6): fetch → convert → compile → cache.
///
/// **Why this is a `@MainActor` class and not an actor.** `WKContentRuleListStore` is
/// declared `WK_SWIFT_UI_ACTOR`, so every one of its methods is already main-actor
/// isolated; an actor wrapper around it would hop to the main actor for each call and
/// buy nothing. The expensive half — parsing a filter list and encoding 80,000 rules to
/// JSON — is what actually moves off, in ``refresh()``.
///
/// **Measured on 2026-09-17, macOS 26 / Xcode 26.6, M-series:**
/// | list | rules | compile |
/// |---|---|---|
/// | EasyList | 81,268 | **2.89 s** |
/// | EasyPrivacy | 56,037 | 1.94 s |
/// | Fanboy Annoyance | 49,087 | 2.01 s |
///
/// A compile does not block the main thread outright — a 10 ms timer kept firing
/// throughout — but it stalls it for up to **353 ms** at a time, which is half of
/// §19.1's entire 800 ms launch budget in one hitch. Looking an already-compiled list up
/// by identifier costs **0.000 s**. That gap is the whole design: launch looks lists up,
/// and only an install or a scheduled update ever compiles.
@MainActor
public final class ContentBlocker {

    public static let shared = ContentBlocker()

    /// What blocking can honestly say about itself. The first run with no network has to
    /// land on ``notReady`` (D14, §32) — lists are never bundled, so there is genuinely
    /// nothing to block with, and pretending otherwise is the failure §17.1 calls out.
    public enum Status: Sendable, Equatable {
        case notReady
        case updating
        case ready(rules: Int, updated: Date)
        case failed(String)
    }

    /// §17.2's three lists, each independently toggleable.
    public enum Category: String, CaseIterable, Sendable, Codable {
        case ads, trackers, annoyances

        /// Fetched at runtime, never bundled (D14). EasyList is GPL/CC-BY-SA and Luna is
        /// GPL-3.0-or-later, so the licences agree — the rule is about shipping, not law.
        public var source: URL {
            switch self {
            case .ads: URL(string: "https://easylist.to/easylist/easylist.txt")!
            case .trackers: URL(string: "https://easylist.to/easylist/easyprivacy.txt")!
            case .annoyances: URL(string: "https://easylist.to/easylist/fanboy-annoyance.txt")!
            }
        }
    }

    public private(set) var status: Status = .notReady {
        didSet { if status != oldValue { onStatusChange?(status) } }
    }

    public var onStatusChange: (@MainActor (Status) -> Void)?

    /// How often the lists are re-fetched (§17.1 "refresh on a schedule").
    public var refreshInterval: TimeInterval = 24 * 60 * 60

    private let store: WKContentRuleListStore
    // Internal, not private: §17.6 lives in ContentBlockerHTTPS.swift and `private` is
    // file-scoped. Still unreachable outside the module.
    let defaults: UserDefaults
    private var compiled: [Category: [WKContentRuleList]] = [:]
    private var ruleCounts: [Category: Int] = [:]
    private var disabledHosts: Set<String> = []
    var insecureHosts: Set<String> = []
    /// §3.2's Local Network permission, compiled once. Internal rather than private
    /// because the list that fills it lives in `ContentBlockerLocalNetwork.swift` and
    /// `private` is file-scoped; still unreachable outside the module.
    var localNetworkList: WKContentRuleList?
    private var blockedCounts: [UUID: Int] = [:]
    /// https URL → the http URL it was upgraded from, so a failure can be told apart from
    /// an ordinary one. Bounded: this is a breadcrumb, not a history.
    var upgrades: [String: URL] = [:]
    weak var browserStore: BrowserStore?
    private var refreshTask: Task<Void, Never>?

    /// Same reason as `localNetworkList` above: the compile for §3.2's list is written
    /// next door and needs the store this one was handed.
    var ruleListStore: WKContentRuleListStore { store }

    init(store: WKContentRuleListStore = .default(), defaults: UserDefaults = .standard) {
        self.store = store
        self.defaults = defaults
    }

    // MARK: - Launch and refresh

    /// Call once at startup. Loads what is already compiled — **it never compiles** — and
    /// schedules the update for after the launch budget has been spent.
    public func start(browserStore: BrowserStore?) {
        self.browserStore = browserStore
        Task { await loadCached() }
        // §3.2's Local Network permission. Nine rules, so it is compiled on the spot —
        // the 2.9 s figure above belongs to the 80,000-rule filter lists, not to this.
        Task { await prepareLocalNetworkList() }
        if let browserStore {
            Task { [weak self] in
                let hosts = try? await browserStore.blockingExemptions()
                guard let self, let hosts else { return }
                self.disabledHosts = hosts.blockingDisabled
                self.insecureHosts = hosts.insecureAllowed
            }
        }
        scheduleRefresh()
    }

    /// Attaches every already-compiled list for the enabled categories. Cheap: a lookup
    /// of a list the store already holds measured at 0.000 s.
    private func loadCached() async {
        for category in Category.allCases where isEnabled(category) {
            var lists: [WKContentRuleList] = []
            for identifier in identifiers(for: category) {
                // A missing identifier **throws** `WKError.contentRuleListStoreLookUpFailed`
                // (code 7) — it does not hand back nil (measured). Treating the throw as
                // "not cached yet" is the whole of the offline first run.
                guard let list = try? await store.contentRuleList(forIdentifier: identifier) else {
                    lists.removeAll()
                    break
                }
                lists.append(list)
            }
            if !lists.isEmpty {
                compiled[category] = lists
                ruleCounts[category] = defaults.integer(forKey: Key.ruleCount(category))
            }
        }
        publishStatus()
    }

    private func scheduleRefresh() {
        let last = defaults.object(forKey: Key.lastRefresh) as? Date ?? .distantPast
        let due = Date().timeIntervalSince(last) >= refreshInterval
        refreshTask = Task { [weak self] in
            // Launch first. Even the download competes for the network with the first
            // page the user asked for (§19.1).
            try? await Task.sleep(for: .seconds(due ? 5 : 60))
            await self?.refresh()
        }
    }

    /// Fetch → convert → compile → cache, for every enabled category.
    ///
    /// - Parameter force: recompile even when the content hash is unchanged.
    public func refresh(force: Bool = false) async {
        guard status != .updating else { return }
        status = .updating
        var failures: [String] = []

        for category in Category.allCases {
            guard isEnabled(category) else {
                compiled[category] = nil
                continue
            }
            do {
                try await update(category, force: force)
            } catch {
                failures.append("\(category.rawValue): \(error.localizedDescription)")
            }
        }

        if failures.isEmpty { defaults.set(Date(), forKey: Key.lastRefresh) }
        await removeStaleIdentifiers()
        publishStatus(failures: failures)
    }

    private func update(_ category: Category, force: Bool) async throws {
        let (data, response) = try await URLSession.shared.data(from: category.source)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw URLError(.badServerResponse)
        }
        let hash = Self.hash(data)

        // The content hash is the cache key (§17.1). An unchanged list must not pay 2.9 s
        // of compile again, so a matching hash plus a list the store still holds is the
        // whole of the work.
        if !force, hash == defaults.string(forKey: Key.hash(category)), compiled[category] != nil { return }

        // Parsing and JSON-encoding 80,000 rules is ~1.4 s of pure CPU; it has no business
        // on the main actor. The compile itself cannot move — the API is main-actor — so
        // it stays here, off the launch path by construction.
        let (encoded, ruleCount): ([String], Int) = try await Task.detached(priority: .utility) {
            guard let text = String(bytes: data, encoding: .utf8) else { throw Failure.notUTF8 }
            let conversion = FilterListConverter.convert(text)
            let encoder = JSONEncoder()
            let chunks = try conversion.chunked().map { chunk -> String in
                guard let json = String(bytes: try encoder.encode(chunk), encoding: .utf8) else {
                    throw Failure.notUTF8
                }
                return json
            }
            return (chunks, conversion.count)
        }.value

        guard !encoded.isEmpty else { throw Failure.emptyList }

        var lists: [WKContentRuleList] = []
        for (index, json) in encoded.enumerated() {
            let identifier = Self.identifier(category, hash: hash, chunk: index)
            // `compileContentRuleList` returns an implicitly-unwrapped optional; a nil
            // list with no error is not documented but is cheap to refuse.
            guard let list = try await store.compileContentRuleList(
                forIdentifier: identifier, encodedContentRuleList: json
            ) else { throw Failure.compileReturnedNothing }
            lists.append(list)
        }

        defaults.set(hash, forKey: Key.hash(category))
        defaults.set(encoded.count, forKey: Key.chunks(category))
        defaults.set(ruleCount, forKey: Key.ruleCount(category))
        ruleCounts[category] = ruleCount
        compiled[category] = lists
    }

    /// Old hashes leave compiled lists behind, and each one is tens of megabytes on disk.
    private func removeStaleIdentifiers() async {
        var keep = Set(Category.allCases.flatMap { identifiers(for: $0) })
        // Not a category's list, and it carries the same `luna-` prefix the sweep matches
        // on — without this line every refresh deleted §3.2's Local Network rules.
        keep.insert(Self.localNetworkIdentifier)
        guard let available = await store.availableIdentifiers() else { return }
        for identifier in available where identifier.hasPrefix(Self.prefix) && !keep.contains(identifier) {
            try? await store.removeContentRuleList(forIdentifier: identifier)
        }
    }

    private func publishStatus(failures: [String] = []) {
        let total = compiled.keys.reduce(0) { $0 + (ruleCounts[$1] ?? 0) }
        if compiled.isEmpty {
            status = failures.isEmpty ? .notReady : .failed(failures.joined(separator: "; "))
        } else {
            status = .ready(rules: total, updated: defaults.object(forKey: Key.lastRefresh) as? Date ?? Date())
        }
    }

    // MARK: - Applying to a web view (§17.2)

    /// **The seam `WebViewFactory` needs.** Attaches the enabled lists, or none of them
    /// when the user has turned blocking off for this site.
    ///
    /// Safe to call on every main-frame navigation: adding and removing an already-compiled
    /// list is a pointer hand-off, not a compile.
    public func apply(to controller: WKUserContentController, host: String? = nil) {
        controller.removeAllContentRuleLists()
        // §3.2's Local Network permission is **not** part of ad blocking and is not
        // covered by turning ad blocking off for a site: they are two answers to two
        // questions, and a user who allows this site's ads has not thereby let it talk
        // to the printer. A nil host is the resting configuration, before the first
        // navigation says where it is going — refused, which is the safe direction.
        if let localNetworkList, !SitePermissions.shared.isAllowed(.localNetwork, forHost: host) {
            controller.add(localNetworkList)
        }
        guard !isDisabled(forHost: host) else { return }
        for category in Category.allCases where isEnabled(category) {
            for list in compiled[category] ?? [] { controller.add(list) }
        }
    }

    /// How many compiled lists ``apply(to:host:)`` would attach. `WKUserContentController`
    /// has no getter for what it holds, so this is the only way to see it.
    var attachedListCount: Int {
        Category.allCases.filter { isEnabled($0) }.reduce(0) { $0 + (compiled[$1]?.count ?? 0) }
    }

    public func isEnabled(_ category: Category) -> Bool {
        defaults.object(forKey: Key.enabled(category)) as? Bool ?? true
    }

    /// Recompiles nothing: the lists stay in the store, they just stop being attached.
    public func setEnabled(_ enabled: Bool, for category: Category) {
        defaults.set(enabled, forKey: Key.enabled(category))
        if enabled, compiled[category] == nil {
            Task { await refresh() }
        }
    }

    // MARK: - Per-site (§17.2)

    public func isDisabled(forHost host: String?) -> Bool {
        guard let host = Self.normalise(host) else { return false }
        return disabledHosts.contains(host)
    }

    /// Persists in `siteSettings` (§17.2). In-memory first so the navigation path can
    /// answer synchronously — `decidePolicyFor` cannot wait on SQLite.
    public func setDisabled(_ disabled: Bool, forHost host: String) {
        guard let host = Self.normalise(host) else { return }
        if disabled { disabledHosts.insert(host) } else { disabledHosts.remove(host) }
        let store = browserStore
        Task { try? await store?.setBlockingDisabled(disabled, host: host) }
    }

    // MARK: - Blocked counts (§17.4)

    /// The name `TabController` must register a handler for, if the count is wanted.
    public static let blockedMessageName = "lunaBlocked"

    /// WebKit exposes **no** public callback for a blocked load: `WKContentRuleList` has
    /// only an `identifier`, and the delegate that would report an action is SPI (D10).
    /// What is observable, and was measured, is that a blocked sub-resource fires `error`
    /// on its element and leaves **no** Resource Timing entry, while a 404 or a decode
    /// failure fires the same `error` and does leave one. That difference is the count.
    ///
    /// It is a heuristic, and it is the honest ceiling of the public API.
    /// ponytail: heuristic count; replace if WebKit ever ships a real blocked-load callback.
    public static let blockedCountScript = """
    (function () {
      var seen = 0;
      document.addEventListener('error', function (event) {
        var target = event.target;
        if (!target || !target.src) { return; }
        var source = target.src;
        setTimeout(function () {
          if (performance.getEntriesByName(source).length > 0) { return; }
          seen++;
          var handler = window.webkit && window.webkit.messageHandlers
            && window.webkit.messageHandlers.lunaBlocked;
          if (handler) { handler.postMessage({ count: seen, url: source }); }
        }, 0);
      }, true);
    })();
    """

    public func blockedCount(tab: UUID) -> Int { blockedCounts[tab] ?? 0 }

    /// Call with the running total the page reports; it resets itself on navigation.
    public func setBlockedCount(_ count: Int, tab: UUID) { blockedCounts[tab] = count }

    public func resetBlockedCount(tab: UUID) { blockedCounts[tab] = 0 }

    public func forgetTab(_ tab: UUID) { blockedCounts[tab] = nil }

    // MARK: - Identifiers, hashing, keys

    enum Failure: Error, LocalizedError {
        case emptyList
        case notUTF8
        case compileReturnedNothing

        var errorDescription: String? {
            switch self {
            case .emptyList: "The filter list produced no rules."
            case .notUTF8: "The filter list was not UTF-8."
            case .compileReturnedNothing: "WebKit compiled the list but returned nothing."
            }
        }
    }

    static let prefix = "luna-"

    /// The content hash is *in* the identifier, so a changed list is a different list and
    /// an unchanged one is found by lookup instead of rebuilt.
    static func identifier(_ category: Category, hash: String, chunk: Int) -> String {
        "\(prefix)\(category.rawValue)-\(hash)-\(chunk)"
    }

    static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    /// Lowercased, trailing dot removed — `siteSettings` is keyed by host and
    /// `Example.com.` and `example.com` are the same site.
    static func normalise(_ host: String?) -> String? {
        guard var host = host?.lowercased(), !host.isEmpty else { return nil }
        while host.hasSuffix(".") { host.removeLast() }
        return host.isEmpty ? nil : host
    }

    private func identifiers(for category: Category) -> [String] {
        guard let hash = defaults.string(forKey: Key.hash(category)) else { return [] }
        let chunks = max(1, defaults.integer(forKey: Key.chunks(category)))
        return (0 ..< chunks).map { Self.identifier(category, hash: hash, chunk: $0) }
    }

    enum Key {
        static let lastRefresh = "blocking.lastRefresh"
        static let httpsOnly = "blocking.httpsOnly"
        static func hash(_ category: Category) -> String { "blocking.hash.\(category.rawValue)" }
        static func chunks(_ category: Category) -> String { "blocking.chunks.\(category.rawValue)" }
        static func ruleCount(_ category: Category) -> String { "blocking.ruleCount.\(category.rawValue)" }
        static func enabled(_ category: Category) -> String { "blocking.enabled.\(category.rawValue)" }
    }
}
