//
//  CredentialPopoverView.swift
//  Luna
//
//  The inside of §14.3's picker: one row per saved account, a way out to every
//  saved password, and — when §14.8 has something to say — a caution line. Its
//  rows share one selection, which the pointer and the arrow keys both move.
//
//  The caution line is the point of this view, not decoration. §14.8 asks that
//  a fill into a page reached through a redirect chain be treated as
//  suspicious, and that an insecure origin be visible. Luna cannot judge
//  whether a redirect was legitimate; the user can, because only they know
//  where they meant to go. So it neither blocks nor stays quiet — it names the
//  site the password is about to be typed into, next to the button that types
//  it.
//

import AppKit
import BrowserKit

@MainActor
final class CredentialPopoverView: NSView {

    private let content: CredentialPopover.Content
    private let onPick: (Credential) -> Void
    private let onAcceptGenerated: (String) -> Void
    private let stack = NSStackView()
    private var rows: [PickerRowView] = []
    private let fingerprint: CredentialRowView.Fingerprint

    /// The chosen row: the first when the picker opens, as Safari's, then
    /// wherever the pointer or the arrow keys put it.
    private(set) var selectedIndex: Int? {
        didSet {
            for (index, row) in rows.enumerated() { row.isSelected = index == selectedIndex }
            if let selectedIndex, rows[selectedIndex] is CredentialRowView { touchIndex = selectedIndex }
        }
    }

    /// Whether the selection was made with the arrow keys. Only then does
    /// Return take it: the row chosen when the picker opens is one the user
    /// never chose, and the Return they meant for the page's own button must
    /// not fill instead.
    private(set) var selectionIsFromKeyboard = false

    /// The account a finger on the sensor fills: the chosen row, or the last
    /// account chosen while the choice is on the row that leaves the list.
    private var touchIndex = 0 { didSet { if touchIndex != oldValue { placeTouchID() } } }
    private var touchView: NSView?
    private var touchPlacement: [NSLayoutConstraint] = []

    var touchCredential: Credential? {
        (rows.indices.contains(touchIndex) ? rows[touchIndex] as? CredentialRowView : nil)?.credential
    }

    /// - Parameter inlineTouchID: whether the picker will hang its live Touch
    ///   ID view on the chosen row (see `CredentialPopover`).
    init(
        content: CredentialPopover.Content,
        inlineTouchID: Bool = false,
        onPick: @escaping (Credential) -> Void,
        onAcceptGenerated: @escaping (String) -> Void
    ) {
        self.content = content
        self.onPick = onPick
        self.onAcceptGenerated = onAcceptGenerated
        if case let .saved(offer) = content {
            fingerprint = Self.fingerprint(for: offer, inline: inlineTouchID)
        } else {
            fingerprint = .none
        }
        super.init(frame: .zero)
        build()
    }

    /// What the rows say about Touch ID. With the live view, a finger fills
    /// even a name-only step, which asks for nothing but is quicker that way;
    /// without it, only a row whose pick will prompt shows the symbol.
    static func fingerprint(for offer: PasswordOffer, inline: Bool) -> CredentialRowView.Fingerprint {
        guard PasswordSettings.requiresAuthentication else { return .none }
        if inline { return .inline }
        return offer.fillsUsernameOnly ? .none : .symbol
    }

    /// The offer, when there is one. `nil` for §14.5's generated password,
    /// which has no saved credentials and no §14.8 flags to carry.
    private var offer: PasswordOffer? {
        if case let .saved(offer) = content { return offer }
        return nil
    }

    private var site: String {
        switch content {
        case let .saved(offer): offer.site
        case let .generated(suggestion): suggestion.site
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    // MARK: - Building

    private func build() {
        wantsLayer = true
        Glass.apply(.popover, to: self, cornerRadius: Tokens.Metric.passwordPopover.cornerRadius)

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.edgeInsets = NSEdgeInsets(top: 6, left: 0, bottom: 6, right: 0)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        switch content {
        case let .saved(offer):
            let pick: (Credential) -> Void = { [weak self] in self?.onPick($0) }
            for credential in offer.credentials.prefix(Tokens.Metric.passwordPopoverMaxRows) {
                add(CredentialRowView(credential: credential, fingerprint: fingerprint, onPick: pick))
            }
            // Safari's picker ends with a way out of it, and so does this one —
            // otherwise a user whose account is not in the list has nowhere to
            // go from here. It matters most when there are more saved
            // credentials than `passwordPopoverMaxRows` will draw.
            let rule = separator()
            stack.addArrangedSubview(rule)
            rule.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            add(allPasswordsRow())
        case let .generated(suggestion):
            stack.addArrangedSubview(header())
            let accept: (String) -> Void = { [weak self] in self?.onAcceptGenerated($0) }
            add(GeneratedPasswordRowView(
                password: suggestion.generated, width: Tokens.Metric.passwordPopover.width, onAccept: accept
            ))
        }

        if let caution = cautionLine() { stack.addArrangedSubview(caution) }
        if !rows.isEmpty { selectedIndex = 0 }

        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(offer == nil
            ? String(localized: "Suggested password for \(site)")
            : String(localized: "Saved passwords for \(site)"))
    }

    private func add(_ row: PickerRowView) {
        let index = rows.count
        rows.append(row)
        row.onHover = { [weak self] inside in
            guard let self else { return }
            // The pointer leaving keeps the choice, as a menu's does: the
            // chosen row is also where a finger on the sensor goes.
            guard inside else { return }
            selectionIsFromKeyboard = false
            selectedIndex = index
        }
        stack.addArrangedSubview(row)
        row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    // MARK: - The keyboard

    /// The first arrow takes the row already chosen into the keyboard's hands
    /// rather than skipping past it; after that the arrows move, and past
    /// either end the selection stays put.
    func moveSelection(by step: Int) {
        guard !rows.isEmpty else { return }
        defer { selectionIsFromKeyboard = true }
        guard let current = selectedIndex else {
            selectedIndex = step > 0 ? 0 : rows.count - 1
            return
        }
        guard selectionIsFromKeyboard else { return }
        selectedIndex = min(max(current + step, 0), rows.count - 1)
    }

    // MARK: - Touch ID

    /// Puts the fingerprint on the account a finger would fill, in the room
    /// that row left for it; it follows the choice from row to row.
    func showTouchID() {
        touchView?.removeFromSuperview()
        let badge = TouchIDBadge()
        touchView = badge
        addSubview(badge)
        placeTouchID()
    }

    private func placeTouchID() {
        guard let touchView, rows.indices.contains(touchIndex) else { return }
        NSLayoutConstraint.deactivate(touchPlacement)
        touchPlacement = [
            touchView.centerXAnchor.constraint(
                equalTo: trailingAnchor, constant: -(12 + CredentialRowView.fingerprintSide / 2)
            ),
            touchView.centerYAnchor.constraint(equalTo: rows[touchIndex].centerYAnchor)
        ]
        NSLayoutConstraint.activate(touchPlacement)
    }

    /// Takes the row the arrow keys chose. False when they chose none, so the
    /// key goes on to the page.
    func activateKeyboardSelection() -> Bool {
        guard selectionIsFromKeyboard, let selectedIndex, rows.indices.contains(selectedIndex) else { return false }
        rows[selectedIndex].activate()
        return true
    }

    // MARK: - Pieces

    /// A hairline between the accounts and the row that leaves them, inset to
    /// the rows' highlight so it reads as part of the list.
    private func separator() -> NSView {
        let host = NSView()
        let line = NSView()
        line.wantsLayer = true
        line.layer?.backgroundColor = Tokens.Line.hairline.cgColor
        line.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(line)
        NSLayoutConstraint.activate([
            host.heightAnchor.constraint(equalToConstant: 9),
            line.heightAnchor.constraint(equalToConstant: 1),
            line.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: 12),
            line.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -12),
            line.centerYAnchor.constraint(equalTo: host.centerYAnchor)
        ])
        return host
    }

    /// The way out of the picker: Settings, at the Passwords section.
    ///
    /// Deliberately not "Other Passwords for this site", which is what
    /// Safari says. Safari can offer that because it can read the Passwords
    /// app; Luna cannot, and a row promising a list Luna has no way to fetch
    /// would be a lie in the one piece of chrome that has to be trustworthy
    /// (see `docs/PASSWORDS.md` §3).
    private func allPasswordsRow() -> PickerRowView {
        PopoverActionRowView(
            title: String(localized: "All saved passwords…"),
            symbol: "list.bullet"
        ) {
            SettingsDefaults.lastSection = PasswordsSection.id
            NSApp.sendAction(#selector(AppDelegate.showSettings(_:)), to: nil, from: nil)
        }
    }

    /// What a generated password is and for which site. A saved account's
    /// row names its own site, so only this offer needs a header.
    private func header() -> NSView {
        let label = NSTextField(labelWithString: String(localized: "Suggested password · \(site)"))
        label.font = Tokens.TypeScale.settingsCaption
        label.textColor = Tokens.Text.tertiary
        return inset(label, top: 2, bottom: 4)
    }

    /// §14.8's two warnings, in order of severity. Only one is shown: a page
    /// that is both insecure and redirected is not twice as alarming, and two
    /// stacked warnings train the eye past both.
    private func cautionLine() -> NSView? {
        guard let offer else { return nil }
        let text: String
        if offer.isInsecure {
            text = String(localized: "This page is not encrypted — a password typed here can be read in transit.")
        } else if offer.viaRedirect {
            text = String(localized: "You were redirected here. Check the address is the one you meant.")
        } else {
            return nil
        }

        let label = NSTextField(wrappingLabelWithString: text)
        label.font = Tokens.TypeScale.settingsCaption
        // Not red. A caution the user must read is worth more than one they
        // learn to flinch past, and §21.4's contrast floor is easier to hold
        // in secondary ink than in an alert colour over glass.
        label.textColor = Tokens.Text.secondary
        label.preferredMaxLayoutWidth = Tokens.Metric.passwordPopover.width - 24
        return inset(label, top: 4, bottom: 2)
    }

    private func inset(_ child: NSView, top: CGFloat, bottom: CGFloat) -> NSView {
        let host = NSView()
        child.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(child)
        NSLayoutConstraint.activate([
            child.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: 12),
            child.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -12),
            child.topAnchor.constraint(equalTo: host.topAnchor, constant: top),
            child.bottomAnchor.constraint(equalTo: host.bottomAnchor, constant: -bottom)
        ])
        return host
    }

    // MARK: - Sizing

    /// The panel's size, measured from the content rather than assumed.
    ///
    /// Measured at the width it will be shown at. Measured unconstrained, a
    /// caution line was laid out on one line and then wrapped to two in the
    /// panel, and the extra line pushed the glass's rounded top out of the
    /// window — the picker looked cut off at its top corners.
    func fittingPopoverSize() -> CGSize {
        let width = Tokens.Metric.passwordPopover.width
        let pin = stack.widthAnchor.constraint(equalToConstant: width)
        pin.isActive = true
        defer { pin.isActive = false }
        stack.layoutSubtreeIfNeeded()
        let height = stack.fittingSize.height
        return CGSize(width: width, height: max(height, Tokens.Metric.passwordPopover.height))
    }

    /// §6's popover entrance: a spring from `foldedScale` to full size about
    /// the corner standing on the field, while `CredentialPopover` fades the
    /// panel up. The pop-out unfolds out of its button the same way.
    ///
    /// Scale only, never position. The panel is already at its final frame
    /// when this runs, and a fresh view that moved on its way in would start
    /// from a place that was never meaningful — the "it spawns at the side and
    /// then goes there" bug this codebase has grown three times already.
    func animateIn(growingDown: Bool) {
        guard !Tokens.A11y.reduceMotion, let layer,
              let spring = Tokens.Motion.popoverIn.springAnimation(keyPath: "transform.scale")
        else { return }
        let frame = layer.frame
        let corner = CGPoint(x: 0, y: growingDown ? 1 : 0)
        layer.anchorPoint = corner
        layer.position = CGPoint(x: frame.minX + frame.width * corner.x, y: frame.minY + frame.height * corner.y)
        spring.fromValue = Self.foldedScale
        spring.toValue = 1.0
        layer.add(spring, forKey: "pickerIn")
    }

    /// §6's 0.96, as the pop-out folds: near enough to full size that it
    /// reads as the same list arriving rather than a small thing growing.
    private static let foldedScale: CGFloat = 0.96
}
