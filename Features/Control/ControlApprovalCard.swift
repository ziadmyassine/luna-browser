//
//  ControlApprovalCard.swift
//  Luna
//
//  The card a Luna Control request waiting for the user is asked in: what
//  the call will do, where, why Luna asked, and Deny, Allow Once and — in the
//  allow-per-site mode — Allow on the site. A `request_user` step reads as
//  what the agent needs the user to do, with Not Now and Done. It shows the
//  oldest request; answering one brings up the next, and the card goes when
//  none are left.
//
//  §14.4's save-password chip's shape and place: glass at the top-right of
//  the page, in a panel that never becomes key, so a request is seen the
//  moment it arrives and still does not take the user's window or keyboard.
//  It used to open only when the folder was clicked, and a raised hand on a
//  sidebar row went unnoticed while the agent waited.
//
//  Unlike the chip it does not time out on screen: the request's own
//  five minutes (`ControlApprovals.timeout`) are what end it unanswered.
//

import AppKit
import LunaControl

@MainActor
final class ControlApprovalCard {

    private weak var approvals: ControlApprovals?
    private var panel: NSPanel?
    private weak var anchor: NSView?
    private var shown: UUID?
    private var resizeObserver: (any NSObjectProtocol)?

    init(approvals: ControlApprovals) {
        self.approvals = approvals
    }

    /// Shows the oldest request waiting, over `anchor`'s top-right corner, or
    /// takes the card down when none is.
    func update(over anchor: NSView?) {
        if let anchor { self.anchor = anchor }
        guard let waiting = approvals?.pending, let request = waiting.first,
              let anchor = self.anchor, let window = anchor.window else {
            return dismiss()
        }
        let view = ControlApprovalCardView(request: request, waiting: waiting.count) { [weak self] answer in
            self?.approvals?.answer(request.id, answer)
        }
        let size = view.fittingCardSize()
        view.frame = NSRect(origin: .zero, size: size)
        let panel = self.panel ?? makePanel()
        panel.contentView = view
        if panel.parent !== window {
            panel.parent?.removeChildWindow(panel)
            window.addChildWindow(panel, ordered: .above)
            observeResize(of: window)
        }
        place(panel, size: size)
        if self.panel == nil {
            self.panel = panel
            panel.orderFront(nil)
            view.animateIn()
        }
        guard request.id != shown else { return }
        shown = request.id
        // §21.1, as the chip does: a card that only appears in a corner is
        // one a VoiceOver user is never told about.
        NSAccessibility.post(element: view, notification: .announcementRequested, userInfo: [
            .announcement: view.headline,
            .priority: NSAccessibilityPriorityLevel.high.rawValue
        ])
    }

    private func dismiss() {
        shown = nil
        if let resizeObserver { NotificationCenter.default.removeObserver(resizeObserver) }
        resizeObserver = nil
        guard let panel else { return }
        self.panel = nil
        panel.parent?.removeChildWindow(panel)
        Tokens.Motion.fadePanelOut(panel)
    }

    private func place(_ panel: NSPanel, size: NSSize) {
        guard let anchor, let window = anchor.window else { return }
        let area = window.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        let inset = Tokens.Metric.chromeGapWide
        panel.setFrame(
            NSRect(x: area.maxX - size.width - inset, y: area.maxY - size.height - inset, width: size.width, height: size.height),
            display: true
        )
    }

    /// A child window moves with its parent but does not follow its corner
    /// when the parent is resized, and a request can wait for minutes.
    private func observeResize(of window: NSWindow) {
        if let resizeObserver { NotificationCenter.default.removeObserver(resizeObserver) }
        resizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let panel = self.panel else { return }
                self.place(panel, size: panel.frame.size)
            }
        }
    }

    /// The chip's panel, except that it stays up while Luna is in the
    /// background: the user is usually in the agent's app when it asks, and
    /// Luna's window beside it is where they should see the question.
    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.transient, .ignoresCycle]
        panel.animationBehavior = .utilityWindow
        return panel
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
        Glass.apply(.popover, to: self, cornerRadius: Tokens.Metric.passwordChip.cornerRadius)
        build(request, waiting: waiting, onAnswer: onAnswer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    private static let padding = NSEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
    private static var textWidth: CGFloat { Tokens.Metric.passwordChip.width - padding.left - padding.right }

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

    /// The chip's width, or wider when a long site name puts the buttons
    /// past it: a button cut off is an answer that cannot be given.
    func fittingCardSize() -> NSSize {
        layoutSubtreeIfNeeded()
        let fitting = stack.fittingSize
        return NSSize(
            width: max(Tokens.Metric.passwordChip.width, fitting.width + Self.padding.left + Self.padding.right),
            height: fitting.height + Self.padding.top + Self.padding.bottom
        )
    }

    /// A fade only, as the chip's: it is built and shown in the same breath,
    /// so it has no earlier place to travel from.
    func animateIn() {
        guard !Tokens.A11y.reduceMotion else { return }
        alphaValue = 0
        Tokens.Motion.animate(Tokens.Motion.popoverIn) { _ in
            animator().alphaValue = 1
        }
    }
}
