//
//  CredentialPopoverRows.swift
//  Luna
//
//  The three kinds of row §14.3's picker is built from: a saved username, §14.5's
//  generated password, and a row that does something other than fill.
//
//  Split out of `CredentialPopoverView.swift` for that file's length limit. They
//  are `internal` rather than `private` only because Swift's `private` is
//  file-scoped; nothing outside this pair of files builds one.
//

import AppKit
import BrowserKit

// MARK: - One saved username

@MainActor
final class CredentialRowView: NSView {

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

    /// The site's own mark, exactly as the sidebar draws it, and the generic
    /// key only when there is none. A row that looks like the site is a row the
    /// user recognises without reading it.
    private func makeGlyph() -> NSImageView {
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
        return glyph
    }

    /// The username. An empty one is a real saved credential — plenty of sites
    /// have only a password — so it gets a name rather than an empty row the
    /// pointer cannot find.
    private func makeTitle() -> NSTextField {
        let title = NSTextField(labelWithString: credential.username.isEmpty
            ? String(localized: "(no username)")
            : credential.username)
        title.font = Tokens.TypeScale.sidebarRow
        title.textColor = Tokens.Text.primary
        title.lineBreakMode = .byTruncatingMiddle
        title.translatesAutoresizingMaskIntoConstraints = false
        return title
    }

    /// The site under the username, because one saved account can be the right
    /// one on `github.com` and the wrong one on a page that merely looks like
    /// it. §14.8 already refuses the cross-site fill; this says the same thing
    /// where the user can read it.
    private func makeSubtitle() -> NSTextField {
        let subtitle = NSTextField(labelWithString: credential.site)
        subtitle.font = Tokens.TypeScale.settingsCaption
        subtitle.textColor = Tokens.Text.secondary
        subtitle.lineBreakMode = .byTruncatingMiddle
        subtitle.translatesAutoresizingMaskIntoConstraints = false
        return subtitle
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

        let glyph = makeGlyph()
        let title = makeTitle()
        let subtitle = makeSubtitle()

        addSubview(glyph)
        addSubview(title)
        addSubview(subtitle)
        activateConstraints(glyph: glyph, title: title, subtitle: subtitle)

        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(String(localized: "Fill \(credential.username) for \(credential.site)"))
    }

    /// Where the row's four pieces sit, and the two the fingerprint displaces.
    /// Split from `build` for its length limit; the arithmetic is the half that
    /// changes when a placement does.
    private func activateConstraints(glyph: NSView, title: NSView, subtitle: NSView) {
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
    }

    /// The site's icon from the favicon cache §4.7 already fills.
    ///
    /// Tries the origin the credential was saved from before the site key: a
    /// credential saved on `accounts.google.com` has that host's mark cached,
    /// and `google.com` may never have been visited at all.
    private static func favicon(for credential: Credential) -> NSImage? {
        if let origin = credential.originURL, let image = SidebarIcons.shared.favicon(for: origin) {
            return image
        }
        return SidebarIcons.shared.favicon(for: URL(string: "https://\(credential.site)"))
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
final class GeneratedPasswordRowView: NSView {

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
final class PopoverActionRowView: NSView {

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
