//
//  ControlApprovalCard.swift
//  Luna
//
//  The card a Luna Control request waiting for the user is asked in: what
//  the call will do, where, why Luna asked, and Deny, Allow Once and — in the
//  allow-per-site mode — Allow on the site. A `request_user` step reads as
//  what the agent needs the user to do, with Not Now and Done. It shows the
//  oldest request; answering one brings up the next, and the sheet goes back
//  up when none are left.
//
//  It drops from the top edge of whatever page is in front
//  (`ControlSurfaceView`), not only the agent's own: a raised hand on a
//  sidebar row alone goes unnoticed while the agent waits. No window becomes
//  key, and the page keeps the keyboard. It does not time out on screen; the
//  request's own five minutes (`ControlApprovals.timeout`) end it unanswered.
//

import AppKit
import LunaControl

@MainActor
final class ControlApprovalCard {

    private weak var approvals: ControlApprovals?
    private var shown: (id: UUID, waiting: Int)?

    init(approvals: ControlApprovals) {
        self.approvals = approvals
    }

    /// Shows the oldest request waiting on `surface`, or sends the sheet back
    /// up when none is.
    func update(on surface: ControlSurfaceView?) {
        guard let surface else { return }
        guard let waiting = approvals?.pending, let request = waiting.first else {
            shown = nil
            return surface.showSheet(nil)
        }
        if let shown, shown.id == request.id, shown.waiting == waiting.count, surface.sheet != nil { return }
        let isNew = shown?.id != request.id
        shown = (request.id, waiting.count)
        let view = ControlApprovalCardView(request: request, waiting: waiting.count) { [weak self] answer in
            self?.approvals?.answer(request.id, answer)
        }
        surface.showSheet(view)
        guard isNew else { return }
        // §21.1: a sheet that only appears is
        // one a VoiceOver user is never told about.
        NSAccessibility.post(element: view, notification: .announcementRequested, userInfo: [
            .announcement: view.headline,
            .priority: NSAccessibilityPriorityLevel.high.rawValue
        ])
    }
}

/// The inside of the card, in the toast's looks (`PageToastView`): the same
/// glass, ink and plain words to press, floating a gap under the bar. A
/// question short enough for one line is a toast's capsule, its answers on
/// the line; a longer one wraps, with who is asking and why in quieter ink
/// under it and the answers under that, in the same glass rounded to a
/// capsule's corner.
@MainActor
final class ControlApprovalCardView: NSView {

    let headline: String
    private let stack = NSStackView()
    private(set) var isCompact = false

    init(request: ControlApprovals.Request, waiting: Int, onAnswer: @escaping (ControlApprovals.Answer) -> Void) {
        headline = Self.headline(for: request)
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        build(request, waiting: waiting, onAnswer: onAnswer)
        Glass.apply(.popover, to: self, cornerRadius: Self.corner).pinToEdges()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        layer.map { Tokens.Shadow.popover.apply(to: $0, in: effectiveAppearance) }
    }

    private static func headline(for request: ControlApprovals.Request) -> String {
        if !request.choices.isEmpty { return String(localized: "\(request.client) needs you") }
        return request.isHandoff
            ? String(localized: "\(request.client) needs you to") : String(localized: "\(request.client) wants to")
    }

    /// The toast's own corner: a capsule's, at the toast's height.
    static var corner: CGFloat { Tokens.Agent.capsuleHeight / 2 }
    /// The card floats a gap under the bar, as a toast does, where the old
    /// sheet ran up under it: a negative tuck.
    static let hiddenTop = -Tokens.Metric.chromeGap
    private static let padding = NSEdgeInsets(top: 10, left: corner, bottom: 10, right: corner - Tokens.Metric.chromeGap)
    static var sideInsets: CGFloat { padding.left + padding.right }
    /// The card's width, which is also where the text wraps.
    static var width: CGFloat { Tokens.Metric.approvalCard.width }
    private static var textWidth: CGFloat { width - sideInsets - Tokens.Metric.faviconSize - Tokens.Metric.chromeGap }

    /// Who is asking: the raised hand for a question, Astro for Astro, else
    /// the app's icon.
    private func mark(for request: ControlApprovals.Request) -> NSImageView {
        let image: NSImage
        if !request.choices.isEmpty || request.isHandoff {
            image = NSImage(systemSymbolName: "hand.raised.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: Tokens.TypeScale.settingsRow.pointSize, weight: .medium)) ?? NSImage()
        } else if request.client == String(localized: "Astro") {
            image = AgentGlyph.image(pointSize: Tokens.Metric.faviconSize)
        } else {
            let app = ControlApp.all.first { $0.folderName == request.client }
            image = app.flatMap { ControlAppIcon.image(for: $0.id) }
                ?? NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil) ?? NSImage()
        }
        let view = NSImageView(image: image)
        view.contentTintColor = Tokens.Text.primary
        view.imageScaling = .scaleProportionallyUpOrDown
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: Tokens.Metric.faviconSize),
            view.heightAnchor.constraint(equalToConstant: Tokens.Metric.faviconSize)
        ])
        return view
    }

    private func build(
        _ request: ControlApprovals.Request, waiting: Int, onAnswer: @escaping (ControlApprovals.Answer) -> Void
    ) {
        let action = request.site.map { "\(request.summary) on \($0)" } ?? request.summary
        let words = answers(request, onAnswer: onAnswer)
        let text = label(action, font: Tokens.TypeScale.settingsRow, color: Tokens.Text.primary)
        let quiet = [
            request.client,
            request.isHandoff || !request.choices.isEmpty ? nil : String(localized: "Luna asks because \(request.reason)"),
            waiting > 1 ? String(localized: "\(waiting - 1) more waiting") : nil
        ].compactMap { $0 }.joined(separator: " · ")
        let detail = label(quiet, font: Tokens.TypeScale.settingsCaption, color: Tokens.Text.secondary)
        let mark = mark(for: request)

        // One line when it all fits, as a toast is.
        let line = text.attributedStringValue.size().width + words.fittingSize.width + Tokens.Metric.chromeGap * 2
        isCompact = quiet == request.client && line <= Self.textWidth
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.setHuggingPriority(.defaultHigh, for: .horizontal)
        if isCompact {
            text.maximumNumberOfLines = 1
            let row = NSStackView(views: [mark, text, words])
            row.spacing = Tokens.Metric.chromeGap
            row.alignment = .centerY
            stack.setViews([row], in: .top)
            stack.toolTip = request.client
        } else {
            let top = NSStackView(views: [mark, text])
            top.spacing = Tokens.Metric.chromeGap
            top.alignment = .firstBaseline
            let indent = Tokens.Metric.faviconSize + Tokens.Metric.chromeGap
            for view in [detail, words] as [NSView] {
                let wrap = NSStackView(views: [view])
                wrap.edgeInsets = NSEdgeInsets(top: 0, left: indent, bottom: 0, right: 0)
                stack.addArrangedSubview(wrap)
            }
            stack.insertArrangedSubview(top, at: 0)
            stack.setCustomSpacing(6, after: stack.arrangedSubviews[1])
        }
        stack.widthAnchor.constraint(greaterThanOrEqualToConstant: Self.width - Self.sideInsets).isActive = true
        addSubview(stack)
        let padding = Self.padding
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: padding.left),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -padding.right),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: isCompact ? 0 : padding.top),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: isCompact ? 0 : -padding.bottom)
        ])
        if isCompact { heightAnchor.constraint(equalToConstant: Tokens.Agent.capsuleHeight).isActive = true }
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("\(headline) \(action)")
    }

    /// The toast's words (`PopoutTextButton`), at the text's own ink, Deny in
    /// red. None is a default: Return must not approve something unread.
    private func answers(
        _ request: ControlApprovals.Request, onAnswer: @escaping (ControlApprovals.Answer) -> Void
    ) -> NSStackView {
        func word(_ title: String, _ answer: ControlApprovals.Answer, destructive: Bool = false) -> PopoutTextButton {
            let button = PopoutTextButton(
                title: title, label: title, restingInk: destructive ? Tokens.Accent.danger : Tokens.Text.primary,
                font: Tokens.TypeScale.settingsRow
            )
            button.onActivate = { onAnswer(answer) }
            return button
        }
        var words: [PopoutTextButton]
        if !request.choices.isEmpty {
            words = request.choices.enumerated().map { word($1, .choice($0)) }
        } else if request.isHandoff {
            words = [word(String(localized: "Not Now"), .deny), word(String(localized: "Done"), .once)]
        } else {
            words = [word(String(localized: "Deny"), .deny, destructive: true), word(String(localized: "Allow Once"), .once)]
            if request.grantable, let site = request.site { words.append(word(String(localized: "Allow on \(site)"), .always)) }
        }
        let row = NSStackView(views: words)
        row.spacing = 2
        return row
    }

    private func label(_ text: String, font: NSFont, color: NSColor) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = font
        label.textColor = color
        label.preferredMaxLayoutWidth = Self.textWidth
        return label
    }

    /// Wider than `width` only when a long site name puts the answers past
    /// it: an answer cut off is one that cannot be given.
    var contentWidth: CGFloat { stack.fittingSize.width }

    func fittingCardSize() -> NSSize {
        layoutSubtreeIfNeeded()
        let fitting = stack.fittingSize
        return NSSize(
            width: fitting.width + Self.sideInsets,
            height: isCompact ? Tokens.Agent.capsuleHeight : fitting.height + Self.padding.top + Self.padding.bottom
        )
    }
}
