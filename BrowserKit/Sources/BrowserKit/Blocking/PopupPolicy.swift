import Foundation

/// §17's pop-up modes, stored in `privacy.popupMode` as the raw value.
public enum PopupMode: String, CaseIterable, Sendable {
    /// WebKit's macOS default: every `window.open` and `target="_blank"` opens.
    case off
    /// WebKit refuses the gesture-less ones; a gestured one opens only when
    /// `PopupPolicy.allows` finds a reason.
    case smart
    /// Nothing opens but a modified click or a site the user allowed.
    case blockAll
}

/// One pop-up that did not open, kept so the user can open it after all.
public struct BlockedPopup: Equatable, Sendable {
    public let url: URL
    public let date: Date

    public init(url: URL, date: Date = Date()) {
        self.url = url
        self.date = date
    }
}

/// Which new windows open. Pure, apart from the two settings it reads, so the
/// whole decision is a table `PopupBlockingTests` walks.
public enum PopupPolicy {

    public enum Key {
        public static let mode = "privacy.popupMode"
        public static let showsAddress = "privacy.popupShowsAddress"
    }

    public static func mode(in defaults: UserDefaults = .standard) -> PopupMode {
        defaults.string(forKey: Key.mode).flatMap(PopupMode.init(rawValue:)) ?? .smart
    }

    public static func setMode(_ mode: PopupMode, in defaults: UserDefaults = .standard) {
        defaults.set(mode.rawValue, forKey: Key.mode)
    }

    /// Whether the chip names the blocked pop-up's host. Off by default: the
    /// address of an ad network is noise to most people.
    public static func showsAddress(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: Key.showsAddress)
    }

    public static func setShowsAddress(_ shows: Bool, in defaults: UserDefaults = .standard) {
        defaults.set(shows, forKey: Key.showsAddress)
    }

    /// How long after a gestured pop-up the opener may not be moved cross-site
    /// by script. A tab-under fires in the same task as the `window.open`, or on
    /// the next timer; two seconds covers both with room for a slow page, and is
    /// short enough that a page's own later redirect is not caught.
    public static let tabUnderWindow: TimeInterval = 2

    // MARK: - The decision

    /// What `createWebViewWith` knows about one new window.
    public struct Request: Sendable {
        public var url: URL?
        /// The tab's main-frame page, not the frame that asked: an ad iframe
        /// opening its own domain is not the site the user is on.
        public var openerURL: URL?
        /// ⌘-click or middle-click — the user asking for a new tab outright.
        public var isModifiedClick: Bool
        /// The link under the last trusted pointer press in the page.
        public var pressedLink: URL?
        /// The site's own "Always Allow" (`SitePermissions` `.popups`).
        public var siteAllowed: Bool

        public init(url: URL?, openerURL: URL?, isModifiedClick: Bool, pressedLink: URL?, siteAllowed: Bool) {
            self.url = url
            self.openerURL = openerURL
            self.isModifiedClick = isModifiedClick
            self.pressedLink = pressedLink
            self.siteAllowed = siteAllowed
        }
    }

    public static func allows(_ request: Request, mode: PopupMode) -> Bool {
        if mode == .off || request.siteAllowed || request.isModifiedClick { return true }
        guard mode == .smart else { return false }
        // A blank window opens, on probation: sign-in buttons open one on the
        // click and point it at the provider once a call returns, and so does
        // the click-hijack with an ad. Its first navigation is judged instead —
        // see `needsProbation`.
        guard let url = request.url, !isBlank(url) else { return true }
        return PublicSuffix.isSameSite(url.host(), request.openerURL?.host())
            || isSignIn(url)
            || request.pressedLink.map { $0.absoluteString == url.absoluteString } == true
    }

    /// `window.open()`, `window.open('')` and `window.open('about:blank')`.
    public static func isBlank(_ url: URL?) -> Bool {
        guard let url else { return true }
        return url.absoluteString.isEmpty || url.absoluteString == "about:blank"
    }

    /// A blank pop-up that opened only because it was blank. Its first scripted
    /// navigation away from blank is judged by `allows`, with the opener's page
    /// and pressed link, as if that address had been the pop-up's own.
    public static func needsProbation(_ request: Request, mode: PopupMode) -> Bool {
        mode == .smart && isBlank(request.url) && !request.isModifiedClick && !request.siteAllowed
    }

    // MARK: - Sign-in

    /// Identity providers whose "Sign in with …" window is cross-site by
    /// nature and never an ad. Breaking one of these is the failure a user
    /// blames the browser for, so they open under Smart without a pressed link.
    /// Matched on host or subdomain, and on a path fragment where the host also
    /// serves ordinary pages — GitHub and Facebook are sites in their own right.
    static let signInProviders: [(host: String, path: String)] = [
        ("accounts.google.com", "/"),
        ("appleid.apple.com", "/"),
        ("login.microsoftonline.com", "/"),
        ("login.live.com", "/"),
        ("github.com", "/login"),
        ("facebook.com", "/dialog/oauth")
    ]

    /// A sign-in provider, or any URL carrying an OAuth authorisation request:
    /// `client_id` with `redirect_uri` or `response_type`.
    public static func isSignIn(_ url: URL) -> Bool {
        guard let host = url.host()?.lowercased() else { return false }
        let path = url.path()
        let provider = signInProviders.contains { rule in
            (host == rule.host || host.hasSuffix(".\(rule.host)")) && path.contains(rule.path)
        }
        guard !provider else { return true }
        let names = Set(URLComponents(url: url, resolvingAgainstBaseURL: true)?.queryItems?.map(\.name) ?? [])
        return names.contains("client_id") && (names.contains("redirect_uri") || names.contains("response_type"))
    }

    // MARK: - The trust boundary

    /// A URL a page script reported, or nil. Page scripts are the page's to
    /// rewrite, so a report is a string of unknown shape: it is resolved against
    /// the frame that sent it and kept only if it is somewhere on the web.
    public static func reportedURL(_ value: Any?, relativeTo frameURL: URL?) -> URL? {
        guard let string = value as? String, !string.isEmpty,
              let url = URL(string: string, relativeTo: frameURL)?.absoluteURL,
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              url.host()?.isEmpty == false
        else { return nil }
        return url
    }
}

/// One tab's pop-up state: what was blocked, the link last pressed, and the
/// tab-under guard. In memory only, for the life of the tab — a private
/// window's blocked pop-ups must not reach the disk, and nobody's need to.
@MainActor
public final class PopupGuard {

    /// Newest first.
    public private(set) var blocked: [BlockedPopup] = []
    var pressedLink: URL?
    private var tabUnderDeadline: Date?
    /// Set on a blank pop-up's own tab — see `PopupPolicy.needsProbation`.
    var probation: PopupProbation?

    static let historyLimit = 10
    /// `createWebViewWith` returning nil makes `window.open` return null, and the
    /// page script reports that too; the second report of one pop-up lands within
    /// the same run-loop turn or two.
    static let duplicateWindow: TimeInterval = 1

    public init() {}

    /// - Returns: false for a duplicate, which is not recorded.
    @discardableResult
    func record(_ url: URL, at date: Date = Date()) -> Bool {
        if let last = blocked.first, last.url == url, date.timeIntervalSince(last.date) < Self.duplicateWindow {
            return false
        }
        blocked.insert(BlockedPopup(url: url, date: date), at: 0)
        if blocked.count > Self.historyLimit { blocked.removeLast(blocked.count - Self.historyLimit) }
        return true
    }

    /// Starts the tab-under window, or ends it for a sign-in pop-up, whose
    /// opener is expected to move on its own once the provider answers.
    func arm(exempt: Bool, at date: Date = Date()) {
        tabUnderDeadline = exempt ? nil : date.addingTimeInterval(PopupPolicy.tabUnderWindow)
    }

    func disarm() { tabUnderDeadline = nil }

    /// Whether a main-frame navigation of the opener is a tab-under. A navigation
    /// the user asked for ends the window, since everything after it is theirs.
    func refusesTabUnder(to url: URL, from opener: URL?, isUserInitiated: Bool, at date: Date = Date()) -> Bool {
        guard let deadline = tabUnderDeadline else { return false }
        guard date < deadline, !isUserInitiated else {
            tabUnderDeadline = nil
            return false
        }
        return !PublicSuffix.isSameSite(url.host(), opener?.host()) && !PopupPolicy.isSignIn(url)
    }
}

/// What a blank pop-up is judged against: the opener's context when it opened.
@MainActor
struct PopupProbation {
    weak var opener: TabController?
    let openerURL: URL?
    let pressedLink: URL?

    /// Whether `url` may be where the pop-up goes, by Smart's rules. A modified
    /// click or an allowed site never reaches probation, so neither applies.
    func allows(_ url: URL) -> Bool {
        PopupPolicy.allows(
            PopupPolicy.Request(
                url: url, openerURL: openerURL, isModifiedClick: false, pressedLink: pressedLink, siteAllowed: false
            ),
            mode: .smart
        )
    }
}
