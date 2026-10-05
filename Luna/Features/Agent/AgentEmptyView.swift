//
//  AgentEmptyView.swift
//  Luna
//
//  What the agent panel shows when there is no conversation to show: Astro,
//  a line about what it does, and — when it cannot start — why, with the way
//  round it as a button: turn Luna Control on, sign in through the browser,
//  or use the other engine.
//

import AppKit

@MainActor
final class AgentEmptyView: NSView {

    enum Action: Equatable {
        case turnOnControl, signIn, cancelSignIn, reopenSignInPage
        case use(AgentEngine)
    }

    var onAction: ((Action) -> Void)?

    private let rover = AgentRoverView()
    private let headline = NSTextField(wrappingLabelWithString: "")
    private let detail = NSTextField(wrappingLabelWithString: "")
    private let primary = SettingsPushButton(title: "", isDestructive: false)
    private let secondary = SettingsPushButton(title: "", isDestructive: false)
    private var actions: (primary: Action?, secondary: Action?)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        headline.font = Tokens.TypeScale.settingsHeading
        headline.textColor = Tokens.Text.primary
        headline.alignment = .center
        detail.font = Tokens.TypeScale.agentStep
        detail.textColor = Tokens.Text.secondary
        detail.alignment = .center
        primary.onActivate = { [weak self] in self?.actions.primary.map { self?.onAction?($0) } }
        secondary.onActivate = { [weak self] in self?.actions.secondary.map { self?.onAction?($0) } }
        let stack = NSStackView(views: [rover, headline, detail, primary, secondary])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = Tokens.Metric.chromeGap
        stack.setCustomSpacing(Tokens.Metric.chromeGapWide, after: rover)
        stack.setCustomSpacing(Tokens.Metric.chromeGapWide, after: detail)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            rover.widthAnchor.constraint(equalToConstant: Tokens.Metric.agentRoverHero),
            rover.heightAnchor.constraint(equalToConstant: Tokens.Metric.agentRoverHero),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -Tokens.Metric.chromeGapWide),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            detail.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        show(blocker: nil, engine: .claude)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    override func layout() {
        super.layout()
        detail.preferredMaxLayoutWidth = bounds.width
        headline.preferredMaxLayoutWidth = bounds.width
    }

    /// The words and buttons for `blocker`, or the welcome when there is none.
    func show(blocker: AgentCenter.Blocker?, engine: AgentEngine) {
        let page = Self.page(for: blocker, engine: engine)
        headline.stringValue = page.headline
        detail.stringValue = page.detail
        actions = (page.primary?.action, page.secondary?.action)
        primary.title = page.primary?.title ?? ""
        primary.isHidden = page.primary == nil
        secondary.title = page.secondary?.title ?? ""
        secondary.isHidden = page.secondary == nil
        rover.mood = switch blocker {
        case nil: .idle
        case .signingIn?: .thinking
        default: .stopped
        }
    }

    typealias Button = (title: String, action: Action)

    struct Page {
        var headline: String
        var detail: String
        var primary: Button?
        var secondary: Button?

        init(_ headline: String, _ detail: String, _ primary: Button?, _ secondary: Button?) {
            (self.headline, self.detail, self.primary, self.secondary) = (headline, detail, primary, secondary)
        }
    }

    /// What each state says, apart from the views, so it is tested as words.
    static func page(for blocker: AgentCenter.Blocker?, engine: AgentEngine) -> Page {
        let other = engine == .claude ? AgentEngine.codex : .claude
        let switchEngine: Button = (String(localized: "Use \(other.name) Instead"), .use(other))
        switch blocker {
        case nil:
            return Page(
                String(localized: "Where are we going?"),
                String(localized: """
                Give me a task. I work in tabs of my own, in a folder you can watch, and you can tell me more while I go.
                """),
                nil, nil
            )
        case .controlOff?:
            return Page(
                String(localized: "Where are we going?"),
                String(localized: "The agent works in your tabs through Luna Control, which is off."),
                (String(localized: "Turn On Luna Control"), .turnOnControl), nil
            )
        case let .notInstalled(engine)?:
            return Page(
                String(localized: "\(engine.toolName) isn’t installed"),
                String(localized: "The agent runs on \(engine.name) through \(engine.toolName). \(engine.installHint)"),
                nil, switchEngine
            )
        case let .signedOut(engine)?:
            return Page(
                String(localized: "Sign in to \(engine.name)"),
                String(localized: """
                The agent runs on your own \(engine.name) plan and its limits. Sign in once in your browser, and Luna remembers it.
                """),
                (String(localized: "Sign In with \(engine.name)"), .signIn), switchEngine
            )
        case let .signingIn(engine, page)?:
            return Page(
                String(localized: "Finish in your browser"),
                String(localized: "Sign in to \(engine.name) on the page that opened, then come back here."),
                page == nil ? nil : (String(localized: "Open the Page Again"), .reopenSignInPage),
                (String(localized: "Cancel"), .cancelSignIn)
            )
        }
    }
}
