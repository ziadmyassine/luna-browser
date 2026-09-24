import Foundation

/// How much a connected app may do before the user is asked. Settings holds
/// the choice; no tool can read or change it.
public enum ControlMode: String, Sendable, CaseIterable {
    /// Every call that acts on a page waits for the user.
    case ask
    /// Acting calls on a site the user has allowed for this app go ahead;
    /// anywhere else waits for the user, who can allow the site then.
    case allowPerSite = "site"
    /// Acting calls go ahead unless something about the page escalates them.
    case allowAll = "all"
}

/// "This app may act on this site without asking." Keyed by the client's
/// display name — the folder's name — and the registrable domain, so a grant
/// for `example.com` covers `shop.example.com` and nothing at `example.org`.
public struct ControlGrant: Hashable, Sendable, Codable {
    public var client: String
    public var site: String

    public init(client: String, site: String) {
        self.client = client
        self.site = site
    }
}

/// The user's standing answers: the mode and the sites allowed per app.
public struct ControlPermissions: Sendable, Equatable {
    public var mode: ControlMode
    public var grants: Set<ControlGrant>

    public init(mode: ControlMode = .ask, grants: Set<ControlGrant> = []) {
        self.mode = mode
        self.grants = grants
    }
}

/// What the app found out about the call's page before deciding.
public struct ControlFacts: Sendable, Equatable {
    /// The page has addressed the agent (`ControlUntrusted.addressesAgent`)
    /// since this connection began: every acting call on the site now asks.
    public var escalated: Bool
    /// The tab shows a page Luna serves itself — Settings' neighbours, not
    /// the web — which no client may read or drive.
    public var isInternalPage: Bool

    public init(escalated: Bool = false, isInternalPage: Bool = false) {
        self.escalated = escalated
        self.isInternalPage = isInternalPage
    }
}

public enum ControlDecision: Sendable, Equatable {
    case allow
    /// Wait for the user. `grantable` offers "allow on this site" beside
    /// "allow once", which is only meaningful in `.allowPerSite` and only
    /// for a call with a site to grant.
    case ask(reason: String, grantable: Bool)
    case deny(String)
    /// Only the user can do this step — they are asked to, rather than asked
    /// whether the agent may.
    case handoff(String)
}

/// The one place a call is weighed. Pure, so every rule here is a test in
/// `ControlPolicyTests` rather than a property of a running app.
public enum ControlPolicy {

    /// Why a call asks, worded to follow "because".
    public static let actingReason = "it acts on the page"
    public static let injectionReason = "the page contained text addressed to an AI agent"
    public static let fileReason = "it opens a file on this Mac"
    public static let internalReason = "That tab shows one of Luna's own pages, which Luna Control cannot read or act on."

    /// - Parameter site: the registrable domain the call acts on — the tab's,
    ///   or for a navigation the destination's. Nil for a page with none
    ///   (`about:`, `data:`, a file), which no grant can cover.
    public static func decide(
        _ command: ControlCommand,
        site: String?,
        client: String,
        facts: ControlFacts,
        permissions: ControlPermissions
    ) -> ControlDecision {
        if facts.isInternalPage { return .deny(internalReason) }
        guard command.acts else { return .allow }
        // Before the mode: a local file is outside every site the user can
        // have meant, and reading it back is one `page_text` away.
        if command.opensFile { return .ask(reason: fileReason, grantable: false) }
        if facts.escalated { return .ask(reason: injectionReason, grantable: false) }
        switch permissions.mode {
        case .allowAll:
            return .allow
        case .allowPerSite:
            if let site, permissions.grants.contains(ControlGrant(client: client, site: site)) { return .allow }
            return .ask(reason: actingReason, grantable: site != nil)
        case .ask:
            return .ask(reason: actingReason, grantable: false)
        }
    }
}

extension ControlCommand {

    /// Whether the call can change something beyond the agent's own view of
    /// the page: a navigation, input, script. Reading, scrolling, a
    /// screenshot and waiting cannot, and never ask.
    ///
    /// A blank tab loads nothing, and `tab_close` is already limited to the
    /// agent's own folder, so neither asks either.
    public var acts: Bool {
        switch self {
        case .listTabs, .readPage, .pageText, .find, .scroll, .screenshot, .console, .wait, .closeTab: false
        case let .openTab(url): url != nil
        case .navigate, .click, .type, .key, .fill, .javascript: true
        }
    }

    var opensFile: Bool {
        switch self {
        case let .openTab(url?), let .navigate(.url(url)): url.isFileURL
        default: false
        }
    }
}
