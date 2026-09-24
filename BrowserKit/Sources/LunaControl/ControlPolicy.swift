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

    /// What acting on the call's element would set off, from the page
    /// library's `inspect`.
    public var risks: Set<ControlRisk>

    public init(escalated: Bool = false, isInternalPage: Bool = false, risks: Set<ControlRisk> = []) {
        self.escalated = escalated
        self.isInternalPage = isInternalPage
        self.risks = risks
    }
}

/// Something about an acting call that no mode or grant covers. Raw values
/// are what the library's `inspect` reports.
public enum ControlRisk: String, Sendable, CaseIterable, Comparable {
    /// The element is a CAPTCHA or inside one. Proving a person is there is
    /// the user's to do.
    case captcha
    /// Typing into a password, card, one-time-code or other secret field
    /// (`secret` in the library): the agent has no business holding the value.
    case secretField
    case payment
    case credentials
    case personalData
    case authorization
    case destructive
    case download

    /// The risks that are the user's to carry out, not to approve.
    public var handsOff: Bool { self == .captcha || self == .secretField }

    public static let asking = allCases.filter { !$0.handsOff }

    /// Worded to follow "because" when it asks; a step's name when it hands off.
    public var reason: String {
        switch self {
        case .captcha: "the page is checking that a person is there (a CAPTCHA)"
        case .secretField: "typing into a password, card or one-time-code field"
        case .payment: "it may pay for, order or subscribe to something"
        case .credentials: "it submits a sign-in form"
        case .personalData: "it submits personal details such as an address, phone number or ID number"
        case .authorization: "it may give another app access to the user's account"
        case .destructive: "it may delete something"
        case .download: "it downloads a file to this Mac"
        }
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        (allCases.firstIndex(of: lhs) ?? 0) < (allCases.firstIndex(of: rhs) ?? 0)
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
    public static let scriptReason = "it runs a script on the page, which can do anything the user can there"
    public static let fileReason = "it opens a file on this Mac"
    public static let uploadReason = "it uploads a file from this Mac to the page"
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
        var risks = facts.risks
        if let url = command.destination, isAuthorization(url) { risks.insert(.authorization) }
        // Before the mode and before any grant: these are never the kind of
        // call a standing answer was given for.
        if let step = risks.filter(\.handsOff).min() { return .handoff(step.reason) }
        // Before the mode: a local file is outside every site the user can
        // have meant, and reading it back is one `page_text` away.
        if command.opensFile { return .ask(reason: fileReason, grantable: false) }
        if let risk = risks.min() { return .ask(reason: risk.reason, grantable: false) }
        if facts.escalated { return .ask(reason: injectionReason, grantable: false) }
        // A site grant is about acting on the page; which of the user's files
        // leaves the Mac is asked every time, short of allow-all.
        if command.readsLocalFile, permissions.mode != .allowAll { return .ask(reason: uploadReason, grantable: false) }
        // A script can do anything on the site, so no grant stands for it;
        // only Allow All lets it run unasked.
        if case .javascript = command, permissions.mode != .allowAll {
            return .ask(reason: scriptReason, grantable: false)
        }
        return byMode(site: site, client: client, permissions: permissions)
    }

    private static func byMode(site: String?, client: String, permissions: ControlPermissions) -> ControlDecision {
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

    /// An OAuth or OpenID Connect authorization request: the consent screen
    /// where one click hands a third party the user's account.
    public static func isAuthorization(_ url: URL) -> Bool {
        let names = Set((URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { $0.name.lowercased() })
        return names.contains("client_id") && !names.isDisjoint(with: ["redirect_uri", "response_type"])
    }
}

extension ControlCommand {

    /// Whether the call can change something beyond the agent's own view of
    /// the page: a navigation, input, script. Reading, scrolling, hovering,
    /// a screenshot and waiting cannot, and never ask.
    ///
    /// A blank tab loads nothing, and `tab_close` is already limited to the
    /// agent's own folder, so neither asks either.
    public var acts: Bool {
        switch self {
        case .listTabs, .readPage, .pageText, .find, .scroll, .hover, .screenshot, .console, .network, .wait, .closeTab,
             .requestUser: false
        case let .openTab(url): url != nil
        // Dismissing is what the dialog's timeout does anyway; accepting may
        // be the "Are you sure?" of whatever the page is about to do.
        case let .dialog(accept, _): accept
        case .navigate, .click, .type, .key, .drag, .fill, .javascript, .upload: true
        }
    }

    /// Where a navigation is going, which is the site it acts on.
    public var destination: URL? {
        switch self {
        case let .openTab(url): url
        case let .navigate(.url(url)): url
        default: nil
        }
    }

    var readsLocalFile: Bool {
        guard case let .upload(_, files) = self else { return false }
        return files.contains { if case .path = $0 { true } else { false } }
    }

    var opensFile: Bool {
        switch self {
        case let .openTab(url?), let .navigate(.url(url)): url.isFileURL
        default: false
        }
    }
}
