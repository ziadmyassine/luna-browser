//
//  SavePasswordChipView.swift
//  Luna
//
//  The inside of §14.4's chip: one sentence, three answers.
//
//  The sentence names the **site and the username**, not just "this site".
//  After a submit the user has often just typed one of two accounts they hold
//  there, and "Save password for example.com?" does not tell them which one
//  they are about to overwrite. Update in particular is destructive-ish — it
//  replaces a working password with whatever was in the field — so the row it
//  would replace has to be legible before the button is pressed.
//

import AppKit
import BrowserKit

@MainActor
final class SavePasswordChipView: NSView {

    private let request: PasswordSaveRequest
    private let onSave: () -> Void
    private let onNever: () -> Void
    private let onClose: () -> Void
    private let onHoverChanged: (Bool) -> Void
    private var tracking: NSTrackingArea?
    private let stack = NSStackView()

    init(
        request: PasswordSaveRequest,
        onSave: @escaping () -> Void,
        onNever: @escaping () -> Void,
        onClose: @escaping () -> Void,
        onHoverChanged: @escaping (Bool) -> Void
    ) {
        self.request = request
        self.onSave = onSave
        self.onNever = onNever
        self.onClose = onClose
        self.onHoverChanged = onHoverChanged
        super.init(frame: .zero)
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    private func build() {
        wantsLayer = true
        Glass.apply(.popover, to: self, cornerRadius: Tokens.Metric.passwordChip.cornerRadius)

        let title = NSTextField(wrappingLabelWithString: headline)
        title.font = Tokens.TypeScale.settingsHeading
        title.textColor = Tokens.Text.primary
        title.preferredMaxLayoutWidth = Tokens.Metric.passwordChip.width - 32

        let subtitle = NSTextField(wrappingLabelWithString: detail)
        subtitle.font = Tokens.TypeScale.settingsCaption
        subtitle.textColor = Tokens.Text.secondary
        subtitle.preferredMaxLayoutWidth = Tokens.Metric.passwordChip.width - 32

        let save = SettingsPushButton(
            title: request.kind == .update ? String(localized: "Update") : String(localized: "Save"),
            isDestructive: false
        )
        save.onActivate = { [weak self] in self?.onSave() }

        let never = SettingsPushButton(title: String(localized: "Never for this site"), isDestructive: false)
        never.onActivate = { [weak self] in self?.onNever() }

        let notNow = SettingsPushButton(title: String(localized: "Not Now"), isDestructive: false)
        notNow.onActivate = { [weak self] in self?.onClose() }

        let buttons = NSStackView(views: [never, notNow, save])
        buttons.orientation = .horizontal
        buttons.spacing = Tokens.Metric.chromeGap
        buttons.alignment = .centerY

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.setViews([title, subtitle, buttons], in: .top)
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12)
        ])

        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(headline)
        setAccessibilityHelp(detail)
    }

    private var headline: String {
        switch request.kind {
        case .save: String(localized: "Save password for \(request.site)?")
        case .update: String(localized: "Update password for \(request.site)?")
        }
    }

    /// Names the account, says where it is going, and — when §14.1's spike
    /// result applies — does not claim it will reach the user's iPhone.
    private var detail: String {
        let who = request.username.isEmpty
            ? String(localized: "No username")
            : request.username
        if request.isInsecure {
            return String(localized: "\(who) · this page is not encrypted")
        }
        return String(localized: "\(who) · saved to your Apple Keychain")
    }

    func fittingChipSize() -> CGSize {
        layoutSubtreeIfNeeded()
        let height = stack.fittingSize.height + 24
        return CGSize(
            width: Tokens.Metric.passwordChip.width,
            height: max(height, Tokens.Metric.passwordChip.height)
        )
    }

    /// A fade only — see `CredentialPopoverView.animateIn`. The chip is built
    /// and shown in the same breath, so it has no earlier position to travel
    /// from, and inventing one is the bug rather than the polish.
    func animateIn() {
        guard !Tokens.A11y.reduceMotion else { return }
        alphaValue = 0
        Tokens.Motion.animate(Tokens.Motion.popoverIn) { _ in
            animator().alphaValue = 1
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        tracking = area
    }

    // Hovering pauses the auto-dismiss: a chip that vanishes while the pointer
    // is travelling to its button is a chip that cannot be answered.
    override func mouseEntered(with event: NSEvent) { onHoverChanged(true) }
    override func mouseExited(with event: NSEvent) { onHoverChanged(false) }
}
