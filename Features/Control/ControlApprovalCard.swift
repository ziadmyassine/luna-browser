//
//  ControlApprovalCard.swift
//  Luna
//
//  The card a Luna Control folder opens when the user clicks it while its
//  client is waiting for an answer: what the call will do, where, why Luna
//  asked, and Deny, Allow Once and — in the allow-per-site mode — Allow on
//  the site. A `request_user` step reads as what the agent needs the user to
//  do, with Not Now and Done. It shows the oldest request; answering one
//  brings up the next, and the card closes when none are left.
//
//  Opened only by that click. A request arriving marks the folder and
//  nothing more, so a prompt never takes the user's window.
//

import AppKit

@MainActor
final class ControlApprovalCard: NSViewController {

    private let folder: UUID
    private weak var approvals: ControlApprovals?
    private weak var popover: NSPopover?
    private let stack = NSStackView()

    /// Opens the card on `anchor` if the folder has a request waiting.
    static func showIfWaiting(forFolder id: UUID, from anchor: NSView) -> Bool {
        guard let approvals = ControlService.current?.approvals, !approvals.pending(inFolder: id).isEmpty else {
            return false
        }
        let card = ControlApprovalCard(folder: id, approvals: approvals)
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = card
        card.popover = popover
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxX)
        return true
    }

    private init(folder: UUID, approvals: ControlApprovals) {
        self.folder = folder
        self.approvals = approvals
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = Tokens.Metric.chromeGap
        stack.edgeInsets = NSEdgeInsets(
            top: Tokens.Metric.chromeGapWide, left: Tokens.Metric.chromeGapWide,
            bottom: Tokens.Metric.chromeGapWide, right: Tokens.Metric.chromeGapWide
        )
        view = stack
        NotificationCenter.default.addObserver(
            self, selector: #selector(approvalsChanged), name: ControlApprovals.didChange, object: nil
        )
        build()
    }

    @objc private func approvalsChanged() { build() }

    private func build() {
        let waiting = approvals?.pending(inFolder: folder) ?? []
        guard let request = waiting.first else {
            popover?.close()
            return
        }
        for view in stack.arrangedSubviews { view.removeFromSuperview() }
        let heading = request.isHandoff
            ? String(localized: "\(request.client) needs you to") : String(localized: "\(request.client) wants to")
        stack.addArrangedSubview(label(heading, font: Tokens.TypeScale.settingsHeading, color: Tokens.Text.primary))
        let action = request.site.map { "\(request.summary) on \($0)" } ?? request.summary
        stack.addArrangedSubview(label(action, font: Tokens.TypeScale.settingsRow, color: Tokens.Text.primary))
        stack.addArrangedSubview(label(
            request.isHandoff
                ? String(localized: "It waits until you press Done.")
                : String(localized: "Luna asks because \(request.reason)."),
            font: Tokens.TypeScale.settingsCaption, color: Tokens.Text.secondary
        ))
        if waiting.count > 1 {
            stack.addArrangedSubview(label(
                String(localized: "\(waiting.count - 1) more waiting"),
                font: Tokens.TypeScale.settingsCaption, color: Tokens.Text.secondary
            ))
        }
        var buttons = request.isHandoff ? [
            button(String(localized: "Not Now"), .deny, request),
            button(String(localized: "Done"), .once, request)
        ] : [
            button(String(localized: "Deny"), .deny, request, destructive: true),
            button(String(localized: "Allow Once"), .once, request)
        ]
        if !request.isHandoff, request.grantable, let site = request.site {
            buttons.append(button(String(localized: "Allow on \(site)"), .always, request))
        }
        let row = NSStackView(views: buttons)
        row.spacing = Tokens.Metric.chromeGap
        stack.addArrangedSubview(row)
    }

    private func label(_ text: String, font: NSFont, color: NSColor) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = font
        label.textColor = color
        label.preferredMaxLayoutWidth = Tokens.Metric.urlPill.width
        return label
    }

    /// `SettingsPushButton`, which already answers hover and press
    /// (`ButtonFeedbackTests`). None is the default button: Return must not
    /// approve something the user has not read.
    private func button(
        _ title: String, _ answer: ControlApprovals.Answer, _ request: ControlApprovals.Request, destructive: Bool = false
    ) -> SettingsPushButton {
        let button = SettingsPushButton(title: title, isDestructive: destructive)
        button.onActivate = { [weak self] in self?.approvals?.answer(request.id, answer) }
        return button
    }
}
