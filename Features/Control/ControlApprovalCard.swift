//
//  ControlApprovalCard.swift
//  Luna
//
//  The sheet a Luna Control request waiting for the user is asked in: what
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
        // §21.1, as the save-password chip does: a sheet that only appears is
        // one a VoiceOver user is never told about.
        NSAccessibility.post(element: view, notification: .announcementRequested, userInfo: [
            .announcement: view.headline,
            .priority: NSAccessibilityPriorityLevel.high.rawValue
        ])
    }
}

/// The inside of the card: who is asking, what for, and the answers.
@MainActor
final class ControlApprovalCardView: NSView {

    let headline: String
    private let stack = NSStackView()

    init(request: ControlApprovals.Request, waiting: Int, onAnswer: @escaping (ControlApprovals.Answer) -> Void) {
        headline = request.isHandoff
            ? String(localized: "\(request.client) needs you to") : String(localized: "\(request.client) wants to")
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        Glass.apply(.popover, to: self, cornerRadius: Tokens.Metric.passwordChip.cornerRadius).pinToEdges()
        build(request, waiting: waiting, onAnswer: onAnswer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        layer.map { Tokens.Shadow.popover.apply(to: $0, in: effectiveAppearance) }
    }

    /// How far the sheet runs up under the page's top edge: its own corner,
    /// so only its lower corners show.
    static let hiddenTop = Tokens.Metric.passwordChip.cornerRadius
    private static let padding = NSEdgeInsets(top: 12 + hiddenTop, left: 16, bottom: 12, right: 16)
    static var sideInsets: CGFloat { padding.left + padding.right }
    /// The save-password chip's width, which is also where the text wraps.
    /// Sized to its widest line instead, a short question made a sheet too
    /// narrow to read as one.
    static var width: CGFloat { Tokens.Metric.passwordChip.width }
    private static var textWidth: CGFloat { width - sideInsets }

    private func build(
        _ request: ControlApprovals.Request, waiting: Int, onAnswer: @escaping (ControlApprovals.Answer) -> Void
    ) {
        let title = label(headline, font: Tokens.TypeScale.settingsHeading, color: Tokens.Text.primary)
        var top: [NSView] = [title]
        if let icon = ControlApp.all.first(where: { $0.folderName == request.client }).flatMap({ ControlAppIcon.image(for: $0.id) }) {
            let image = NSImageView(image: icon)
            image.imageScaling = .scaleProportionallyUpOrDown
            NSLayoutConstraint.activate([
                image.widthAnchor.constraint(equalToConstant: Tokens.Metric.faviconSize),
                image.heightAnchor.constraint(equalToConstant: Tokens.Metric.faviconSize)
            ])
            top.insert(image, at: 0)
        }
        let head = NSStackView(views: top)
        head.spacing = Tokens.Metric.chromeGap

        let action = request.site.map { "\(request.summary) on \($0)" } ?? request.summary
        var views: [NSView] = [
            head,
            label(action, font: Tokens.TypeScale.settingsRow, color: Tokens.Text.primary),
            label(
                request.isHandoff
                    ? String(localized: "It waits until you press Done.")
                    : String(localized: "Luna asks because \(request.reason)."),
                font: Tokens.TypeScale.settingsCaption, color: Tokens.Text.secondary
            )
        ]
        if waiting > 1 {
            views.append(label(
                String(localized: "\(waiting - 1) more waiting"),
                font: Tokens.TypeScale.settingsCaption, color: Tokens.Text.secondary
            ))
        }
        views.append(buttons(request, onAnswer: onAnswer))

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        // The chip's width, or the row of answers when that is wider, and
        // never the width of the space it stands in.
        stack.setHuggingPriority(.defaultHigh, for: .horizontal)
        stack.widthAnchor.constraint(greaterThanOrEqualToConstant: Self.textWidth).isActive = true
        stack.setViews(views, in: .top)
        stack.setCustomSpacing(Tokens.Metric.chromeGapWide, after: views[views.count - 2])
        addSubview(stack)
        let padding = Self.padding
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: padding.left),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -padding.right),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: padding.top),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -padding.bottom)
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("\(headline) \(action)")
    }

    /// `SettingsPushButton`, which already answers hover and press
    /// (`ButtonFeedbackTests`). None is the default button: Return must not
    /// approve something the user has not read.
    private func buttons(
        _ request: ControlApprovals.Request, onAnswer: @escaping (ControlApprovals.Answer) -> Void
    ) -> NSStackView {
        func button(_ title: String, _ answer: ControlApprovals.Answer, destructive: Bool = false) -> SettingsPushButton {
            let button = SettingsPushButton(title: title, isDestructive: destructive)
            button.onActivate = { onAnswer(answer) }
            return button
        }
        var buttons = request.isHandoff ? [
            button(String(localized: "Not Now"), .deny),
            button(String(localized: "Done"), .once)
        ] : [
            button(String(localized: "Deny"), .deny, destructive: true),
            button(String(localized: "Allow Once"), .once)
        ]
        if !request.isHandoff, request.grantable, let site = request.site {
            buttons.append(button(String(localized: "Allow on \(site)"), .always))
        }
        let row = NSStackView(views: buttons)
        row.spacing = Tokens.Metric.chromeGap
        return row
    }

    private func label(_ text: String, font: NSFont, color: NSColor) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = font
        label.textColor = color
        label.preferredMaxLayoutWidth = Self.textWidth
        return label
    }

    /// Wider than `width` only when a long site name puts the buttons past
    /// it: a button cut off is an answer that cannot be given.
    var contentWidth: CGFloat { stack.fittingSize.width }

    func fittingCardSize() -> NSSize {
        layoutSubtreeIfNeeded()
        let fitting = stack.fittingSize
        return NSSize(
            width: fitting.width + Self.sideInsets,
            height: fitting.height + Self.padding.top + Self.padding.bottom
        )
    }
}
