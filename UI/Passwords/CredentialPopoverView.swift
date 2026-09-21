//
//  CredentialPopoverView.swift
//  Luna
//
//  The inside of §14.3's picker: a header naming the site, one row per saved
//  username, and — when §14.8 has something to say — a caution line.
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

    init(
        content: CredentialPopover.Content,
        onPick: @escaping (Credential) -> Void,
        onAcceptGenerated: @escaping (String) -> Void
    ) {
        self.content = content
        self.onPick = onPick
        self.onAcceptGenerated = onAcceptGenerated
        super.init(frame: .zero)
        build()
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

        stack.addArrangedSubview(header())

        switch content {
        case let .saved(offer):
            for credential in offer.credentials.prefix(Tokens.Metric.passwordPopoverMaxRows) {
                let row = CredentialRowView(credential: credential) { [weak self] in self?.onPick($0) }
                stack.addArrangedSubview(row)
                row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            }
        case let .generated(suggestion):
            let row = GeneratedPasswordRowView(password: suggestion.generated) { [weak self] password in
                self?.onAcceptGenerated(password)
            }
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        // Safari's picker ends with a way out of it, and so does this one —
        // otherwise a user whose account is not in the list has nowhere to go
        // from here. It matters most when there are more saved credentials
        // than `passwordPopoverMaxRows` will draw.
        if case .saved = content {
            let more = allPasswordsRow()
            stack.addArrangedSubview(more)
            more.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        if let caution = cautionLine() { stack.addArrangedSubview(caution) }

        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(offer == nil
            ? String(localized: "Suggested password for \(site)")
            : String(localized: "Saved passwords for \(site)"))
    }

    /// The way out of the picker: Settings, at the Passwords section.
    ///
    /// Deliberately not "Other Passwords for this site", which is what
    /// Safari says. Safari can offer that because it can read the Passwords
    /// app; Luna cannot, and a row promising a list Luna has no way to fetch
    /// would be a lie in the one piece of chrome that has to be trustworthy
    /// (see `docs/PASSWORDS.md` §3).
    private func allPasswordsRow() -> NSView {
        PopoverActionRowView(
            title: String(localized: "All saved passwords…"),
            symbol: "list.bullet"
        ) {
            SettingsDefaults.lastSection = PasswordsSection.id
            NSApp.sendAction(#selector(AppDelegate.showSettings(_:)), to: nil, from: nil)
        }
    }

    /// The site, spelled out. This is the eTLD+1 the credential is filed
    /// under, not the page's full URL — the whole match rule is "same site",
    /// so the site is what the user should be checking.
    private func header() -> NSView {
        let label = NSTextField(labelWithString: offer == nil
            ? String(localized: "Suggested password · \(site)")
            : site)
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
    func fittingPopoverSize() -> CGSize {
        let width = Tokens.Metric.passwordPopover.width
        layoutSubtreeIfNeeded()
        let height = stack.fittingSize.height
        return CGSize(width: width, height: max(height, Tokens.Metric.passwordPopover.height))
    }

    /// A fade, and nothing else.
    ///
    /// This view is created milliseconds before it is shown, so it has nowhere
    /// to animate from: anything that moves it on the way in starts at a
    /// position that was never meaningful. That is the "it spawns at the side
    /// and then goes there" bug this codebase has grown three times already,
    /// and the standing rule is that a fresh view is placed with animation off
    /// and only faded up. The panel is already at its final frame when this
    /// runs; only the opacity changes.
    func animateIn() {
        guard !Tokens.A11y.reduceMotion else { return }
        alphaValue = 0
        Tokens.Motion.animate(Tokens.Motion.popoverIn) { _ in
            animator().alphaValue = 1
        }
    }
}
