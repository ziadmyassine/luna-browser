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

// MARK: - One saved username

@MainActor
private final class CredentialRowView: NSView {

    /// Named so a test can ask whether the fingerprint is drawn without
    /// guessing at image ordering.
    static let biometricIdentifier = "password-row-biometric"

    private let credential: Credential
    private let onPick: (Credential) -> Void
    private let highlight = NSView()
    private var tracking: NSTrackingArea?

    init(credential: Credential, onPick: @escaping (Credential) -> Void) {
        self.credential = credential
        self.onPick = onPick
        super.init(frame: .zero)
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    private func build() {
        wantsLayer = true
        highlight.wantsLayer = true
        highlight.layer?.backgroundColor = Tokens.Surface.hover.cgColor
        highlight.layer?.cornerRadius = 7
        highlight.layer?.cornerCurve = .continuous
        highlight.alphaValue = 0
        highlight.translatesAutoresizingMaskIntoConstraints = false
        addSubview(highlight)

        // The site's own mark, exactly as the sidebar draws it, and the generic
        // key only when there is none. A row that looks like the site is a row
        // the user recognises without reading it — which is most of what
        // Safari's panel is doing that Luna's was not.
        let glyph = NSImageView()
        glyph.translatesAutoresizingMaskIntoConstraints = false
        glyph.imageScaling = .scaleProportionallyUpOrDown
        if let favicon = Self.favicon(for: credential) {
            glyph.image = favicon
            glyph.wantsLayer = true
            glyph.layer?.cornerRadius = 3
            glyph.layer?.cornerCurve = .continuous
            glyph.layer?.masksToBounds = true
        } else {
            glyph.image = NSImage(systemSymbolName: "key.fill", accessibilityDescription: nil)
            glyph.contentTintColor = Tokens.Text.secondary
        }

        // An empty username is a real saved credential — plenty of sites have
        // only a password — so it gets a name rather than an empty row the
        // pointer cannot find.
        let title = NSTextField(labelWithString: credential.username.isEmpty
            ? String(localized: "(no username)")
            : credential.username)
        title.font = Tokens.TypeScale.sidebarRow
        title.textColor = Tokens.Text.primary
        title.lineBreakMode = .byTruncatingMiddle
        title.translatesAutoresizingMaskIntoConstraints = false

        // The site under the username, because one saved account can be the
        // right one on `github.com` and the wrong one on a page that merely
        // looks like it. §14.8 already refuses the cross-site fill; this is the
        // same fact said where the user can read it.
        let subtitle = NSTextField(labelWithString: credential.site)
        subtitle.font = Tokens.TypeScale.settingsCaption
        subtitle.textColor = Tokens.Text.secondary
        subtitle.lineBreakMode = .byTruncatingMiddle
        subtitle.translatesAutoresizingMaskIntoConstraints = false

        addSubview(glyph)
        addSubview(title)
        addSubview(subtitle)

        var constraints: [NSLayoutConstraint] = [
            heightAnchor.constraint(equalToConstant: 42),
            highlight.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            highlight.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            highlight.topAnchor.constraint(equalTo: topAnchor, constant: 1),
            highlight.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1),
            glyph.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            glyph.centerYAnchor.constraint(equalTo: centerYAnchor),
            glyph.widthAnchor.constraint(equalToConstant: 16),
            glyph.heightAnchor.constraint(equalToConstant: 16),
            title.leadingAnchor.constraint(equalTo: glyph.trailingAnchor, constant: 9),
            title.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            subtitle.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 1)
        ]

        // The fingerprint says what the click will cost before it is spent —
        // a prompt nobody expected is the thing that makes people distrust a
        // picker. Absent entirely when the preference is off, rather than
        // drawn dim: a symbol that means nothing is worse than no symbol.
        if PasswordSettings.requiresAuthentication {
            let biometric = NSImageView(
                image: NSImage(systemSymbolName: "touchid", accessibilityDescription: nil) ?? NSImage()
            )
            biometric.contentTintColor = Tokens.Text.secondary
            biometric.translatesAutoresizingMaskIntoConstraints = false
            biometric.setAccessibilityIdentifier(Self.biometricIdentifier)
            addSubview(biometric)
            constraints += [
                biometric.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
                biometric.centerYAnchor.constraint(equalTo: centerYAnchor),
                biometric.widthAnchor.constraint(equalToConstant: 15),
                title.trailingAnchor.constraint(lessThanOrEqualTo: biometric.leadingAnchor, constant: -8),
                subtitle.trailingAnchor.constraint(lessThanOrEqualTo: biometric.leadingAnchor, constant: -8)
            ]
        } else {
            constraints += [
                title.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
                subtitle.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12)
            ]
        }
        NSLayoutConstraint.activate(constraints)

        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(String(localized: "Fill \(credential.username) for \(credential.site)"))
    }

    /// The site's icon from the favicon cache §4.7 already fills.
    ///
    /// Tries the origin the credential was saved from before the site key: a
    /// credential saved on `accounts.google.com` has that host's mark cached,
    /// and `google.com` may never have been visited at all.
    private static func favicon(for credential: Credential) -> NSImage? {
        if let origin = credential.originURL, let image = SidebarIcons.favicon(for: origin) {
            return image
        }
        return SidebarIcons.favicon(for: URL(string: "https://\(credential.site)"))
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

    override func mouseEntered(with event: NSEvent) { setHighlighted(true) }
    override func mouseExited(with event: NSEvent) { setHighlighted(false) }

    private func setHighlighted(_ on: Bool) {
        Tokens.Motion.animate(Tokens.Motion.rowHover) { _ in
            highlight.animator().alphaValue = on ? 1 : 0
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onPick(credential)
    }

    override func accessibilityPerformPress() -> Bool {
        onPick(credential)
        return true
    }
}

// MARK: - §14.5's generated password

/// One row showing the generated password itself.
///
/// It is shown, not hidden behind "Use Strong Password". The user is about
/// to be committed to a secret they have never seen, on a site that may well
/// reject it for a rule it never declared; being able to read it before taking
/// it is what makes that recoverable. It is also monospaced and
/// `byCharWrapping`, because the one thing a person does with a generated
/// password on screen is check a character they think they misread.
@MainActor
private final class GeneratedPasswordRowView: NSView {

    private let password: String
    private let onAccept: (String) -> Void
    private let highlight = NSView()
    private var tracking: NSTrackingArea?

    init(password: String, onAccept: @escaping (String) -> Void) {
        self.password = password
        self.onAccept = onAccept
        super.init(frame: .zero)
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    private func build() {
        wantsLayer = true
        highlight.wantsLayer = true
        highlight.layer?.backgroundColor = Tokens.Surface.hover.cgColor
        highlight.layer?.cornerRadius = 7
        highlight.layer?.cornerCurve = .continuous
        highlight.alphaValue = 0
        highlight.translatesAutoresizingMaskIntoConstraints = false
        addSubview(highlight)

        let value = NSTextField(wrappingLabelWithString: password)
        value.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        value.textColor = Tokens.Text.primary
        value.lineBreakMode = .byCharWrapping
        value.preferredMaxLayoutWidth = Tokens.Metric.passwordPopover.width - 32
        value.translatesAutoresizingMaskIntoConstraints = false
        addSubview(value)

        NSLayoutConstraint.activate([
            highlight.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            highlight.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            highlight.topAnchor.constraint(equalTo: topAnchor, constant: 1),
            highlight.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1),
            value.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            value.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            value.topAnchor.constraint(equalTo: topAnchor, constant: 7),
            value.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -7)
        ])

        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(String(localized: "Use this strong password"))
        // Read out character by character rather than as a word VoiceOver will
        // try and fail to pronounce.
        setAccessibilityHelp(password.map(String.init).joined(separator: " "))
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

    override func mouseEntered(with event: NSEvent) { setHighlighted(true) }
    override func mouseExited(with event: NSEvent) { setHighlighted(false) }

    private func setHighlighted(_ on: Bool) {
        Tokens.Motion.animate(Tokens.Motion.rowHover) { _ in
            highlight.animator().alphaValue = on ? 1 : 0
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onAccept(password)
    }

    override func accessibilityPerformPress() -> Bool {
        onAccept(password)
        return true
    }
}

// MARK: - A row that does something other than fill

/// The picker's non-credential row. Same hover behaviour as
/// ``CredentialRowView`` so the list reads as one list, but it carries no
/// credential and can never fill one.
@MainActor
private final class PopoverActionRowView: NSView {

    private let onActivate: () -> Void
    private let highlight = NSView()
    private var tracking: NSTrackingArea?

    init(title: String, symbol: String, onActivate: @escaping () -> Void) {
        self.onActivate = onActivate
        super.init(frame: .zero)
        build(title: title, symbol: symbol)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    private func build(title: String, symbol: String) {
        wantsLayer = true
        highlight.wantsLayer = true
        highlight.layer?.backgroundColor = Tokens.Surface.hover.cgColor
        highlight.layer?.cornerRadius = 7
        highlight.layer?.cornerCurve = .continuous
        highlight.alphaValue = 0
        highlight.translatesAutoresizingMaskIntoConstraints = false
        addSubview(highlight)

        let glyph = NSImageView(
            image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil) ?? NSImage()
        )
        glyph.contentTintColor = Tokens.Text.secondary
        glyph.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: title)
        label.font = Tokens.TypeScale.sidebarRow
        label.textColor = Tokens.Text.secondary
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false

        addSubview(glyph)
        addSubview(label)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 30),
            highlight.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            highlight.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            highlight.topAnchor.constraint(equalTo: topAnchor, constant: 1),
            highlight.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1),
            glyph.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            glyph.centerYAnchor.constraint(equalTo: centerYAnchor),
            glyph.widthAnchor.constraint(equalToConstant: 16),
            label.leadingAnchor.constraint(equalTo: glyph.trailingAnchor, constant: 9),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(title)
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

    override func mouseEntered(with event: NSEvent) { setHighlighted(true) }
    override func mouseExited(with event: NSEvent) { setHighlighted(false) }

    private func setHighlighted(_ on: Bool) {
        Tokens.Motion.animate(Tokens.Motion.rowHover) { _ in
            highlight.animator().alphaValue = on ? 1 : 0
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onActivate()
    }

    override func accessibilityPerformPress() -> Bool {
        onActivate()
        return true
    }
}
