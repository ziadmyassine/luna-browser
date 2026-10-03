//
//  CredentialPopoverRows.swift
//  Luna
//
//  The rows §14.3's picker is built from: a saved account, §14.5's generated
//  password, and a row that does something other than fill. They share
//  `PickerRowView`, which owns the highlight and the pointer, so the picker
//  can move one selection across all three with the arrow keys.
//
//  Split out of `CredentialPopoverView.swift` for that file's length limit. They
//  are `internal` rather than `private` only because Swift's `private` is
//  file-scoped; nothing outside this pair of files builds one.
//

import AppKit
import BrowserKit

// MARK: - The shared row

/// One selectable line of the picker. A list row, not a button: it highlights
/// and does not swell (see `CLAUDE.md`). The chosen row is filled with the
/// accent and its words turn to `Accent.onTint`, as the system's own autofill
/// menu draws it — the second of `Tokens.Accent.onTint`'s exceptions.
@MainActor
class PickerRowView: NSView {

    /// The pointer arrived (`true`) or left. The picker decides what that
    /// selects, because a keyboard selection elsewhere has to give way to it.
    var onHover: ((Bool) -> Void)?

    private let action: () -> Void
    private let highlight = NSView()
    private var tracking: NSTrackingArea?

    init(action: @escaping () -> Void) {
        self.action = action
        super.init(frame: .zero)
        wantsLayer = true
        highlight.wantsLayer = true
        highlight.layer?.backgroundColor = Tokens.Accent.tint.cgColor
        highlight.layer?.cornerRadius = 7
        highlight.layer?.cornerCurve = .continuous
        highlight.alphaValue = 0
        highlight.translatesAutoresizingMaskIntoConstraints = false
        addSubview(highlight)
        NSLayoutConstraint.activate([
            highlight.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            highlight.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            highlight.topAnchor.constraint(equalTo: topAnchor, constant: 1),
            highlight.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    var isSelected = false {
        didSet {
            guard isSelected != oldValue else { return }
            Tokens.Motion.animate(Tokens.Motion.rowHover) { _ in
                highlight.animator().alphaValue = isSelected ? 1 : 0
            }
            inkDidChange()
        }
    }

    /// Ink for a label on this row: `onTint` over the accent, `normal` off it.
    func ink(_ normal: NSColor) -> NSColor { isSelected ? Tokens.Accent.onTint : normal }

    /// The selection changed; a row recolours its words here.
    func inkDidChange() {}

    func activate() { action() }

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

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }

    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        action()
    }

    override func accessibilityPerformPress() -> Bool {
        action()
        return true
    }
}

// MARK: - One saved account

@MainActor
final class CredentialRowView: PickerRowView {

    /// Named so a test can ask whether the fingerprint is drawn without
    /// guessing at image ordering.
    static let biometricIdentifier = "password-row-biometric"

    /// What the row's trailing end says about Touch ID.
    enum Fingerprint {
        /// No prompt will come.
        case none
        /// A prompt will come when the row is picked: the system's symbol.
        case symbol
        /// A finger on the sensor fills without a dialog. The picker puts the
        /// badge on the chosen account only, since that is the one it fills.
        case inline
    }

    let credential: Credential
    private let title = NSTextField(labelWithString: "")
    private let subtitle = NSTextField(labelWithString: "")

    init(credential: Credential, fingerprint: Fingerprint, onPick: @escaping (Credential) -> Void) {
        self.credential = credential
        super.init { onPick(credential) }
        build(fingerprint: fingerprint)
    }

    override func inkDidChange() {
        title.textColor = ink(Tokens.Text.primary)
        subtitle.textColor = ink(Tokens.Text.secondary)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    /// The site's own mark in colour, and a coloured key tile when there is
    /// none. A row that looks like the site is a row the user recognises
    /// without reading it.
    private func makeGlyph() -> NSImageView {
        let glyph = NSImageView()
        glyph.translatesAutoresizingMaskIntoConstraints = false
        glyph.imageScaling = .scaleProportionallyUpOrDown
        glyph.image = Self.favicon(for: credential) ?? Self.keyTile
        glyph.wantsLayer = true
        glyph.layer?.cornerRadius = 6
        glyph.layer?.cornerCurve = .continuous
        glyph.layer?.masksToBounds = true
        return glyph
    }

    /// A key on the accent, for a site whose own mark Luna has not cached.
    /// Drawn per appearance, so it follows the user's accent colour.
    static let keyTile = NSImage(size: CGSize(width: 24, height: 24), flipped: false) { rect in
        let tile = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        NSGradient(starting: Tokens.Accent.tint.blended(withFraction: 0.25, of: .white) ?? Tokens.Accent.tint,
                   ending: Tokens.Accent.tint)?.draw(in: tile, angle: -90)
        let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
            .applying(.init(paletteColors: [.white]))
        if let key = NSImage(systemSymbolName: "key.fill", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
            key.draw(in: CGRect(
                x: rect.midX - key.size.width / 2, y: rect.midY - key.size.height / 2,
                width: key.size.width, height: key.size.height
            ))
        }
        return true
    }

    /// The username over what the row is and for which site, in Safari's
    /// words. An empty username is a real saved credential — plenty of sites
    /// have only a password — so it gets a name rather than an empty row the
    /// pointer cannot find. The site is there because one saved account can be
    /// the right one on `github.com` and the wrong one on a page that merely
    /// looks like it.
    private func styleLabels() {
        title.stringValue = credential.username.isEmpty ? String(localized: "(no username)") : credential.username
        title.font = Tokens.TypeScale.sidebarRow
        subtitle.stringValue = String(localized: "Password for \(credential.site)")
        subtitle.font = Tokens.TypeScale.settingsCaption
        for label in [title, subtitle] {
            label.lineBreakMode = .byTruncatingMiddle
            label.translatesAutoresizingMaskIntoConstraints = false
        }
        inkDidChange()
    }

    private func build(fingerprint: Fingerprint) {
        let glyph = makeGlyph()
        styleLabels()

        addSubview(glyph)
        addSubview(title)
        addSubview(subtitle)
        activateConstraints(glyph: glyph, fingerprint: fingerprint)

        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(String(localized: "Fill \(credential.username) for \(credential.site)"))
    }

    /// Where the row's pieces sit, and the two the fingerprint displaces.
    /// Split from `build` for its length limit; the arithmetic is the half that
    /// changes when a placement does.
    private func activateConstraints(glyph: NSView, fingerprint: Fingerprint) {
        var constraints: [NSLayoutConstraint] = [
            heightAnchor.constraint(equalToConstant: Self.height),
            glyph.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            glyph.centerYAnchor.constraint(equalTo: centerYAnchor),
            glyph.widthAnchor.constraint(equalToConstant: 24),
            glyph.heightAnchor.constraint(equalToConstant: 24),
            title.leadingAnchor.constraint(equalTo: glyph.trailingAnchor, constant: 10),
            title.bottomAnchor.constraint(equalTo: centerYAnchor, constant: 1),
            subtitle.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 1)
        ]

        // The fingerprint says what the click will cost before it is spent —
        // a prompt nobody expected is the thing that makes people distrust a
        // picker. Absent entirely when no prompt will come, rather than drawn
        // dim: a symbol that means nothing is worse than no symbol. Red, as
        // the Mac draws Touch ID.
        let trailing: CGFloat
        switch fingerprint {
        case .none:
            trailing = 12
        case .inline:
            trailing = Self.fingerprintSide + 20
        case .symbol:
            trailing = Self.fingerprintSide + 20
            let biometric = TouchIDBadge()
            addSubview(biometric)
            constraints += [
                biometric.centerXAnchor.constraint(equalTo: trailingAnchor, constant: -(12 + Self.fingerprintSide / 2)),
                biometric.centerYAnchor.constraint(equalTo: centerYAnchor)
            ]
        }
        constraints += [
            title.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -trailing),
            subtitle.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -trailing)
        ]
        NSLayoutConstraint.activate(constraints)
    }

    static let height: CGFloat = 46

    /// The room a row leaves for the Touch ID mark: `LAAuthenticationView`
    /// at `.small` measures 32 pt, and the badge is centred in the same box.
    static let fingerprintSide: CGFloat = 32

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
final class GeneratedPasswordRowView: PickerRowView {

    private let value: NSTextField

    init(password: String, width: CGFloat, onAccept: @escaping (String) -> Void) {
        value = NSTextField(wrappingLabelWithString: password)
        super.init { onAccept(password) }

        value.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        value.textColor = Tokens.Text.primary
        value.lineBreakMode = .byCharWrapping
        value.preferredMaxLayoutWidth = width - 32
        value.translatesAutoresizingMaskIntoConstraints = false
        addSubview(value)

        NSLayoutConstraint.activate([
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

    override func inkDidChange() { value.textColor = ink(Tokens.Text.primary) }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }
}

// MARK: - A row that does something other than fill

/// The picker's non-credential row. It carries no credential and can never
/// fill one.
@MainActor
final class PopoverActionRowView: PickerRowView {

    private let glyph: NSImageView
    private let label: NSTextField

    init(title: String, symbol: String, onActivate: @escaping () -> Void) {
        glyph = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil) ?? NSImage())
        label = NSTextField(labelWithString: title)
        super.init(action: onActivate)

        glyph.contentTintColor = Tokens.Text.secondary
        glyph.translatesAutoresizingMaskIntoConstraints = false

        label.font = Tokens.TypeScale.sidebarRow
        label.textColor = Tokens.Text.secondary
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false

        addSubview(glyph)
        addSubview(label)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 30),
            glyph.centerXAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            glyph.centerYAnchor.constraint(equalTo: centerYAnchor),
            glyph.widthAnchor.constraint(equalToConstant: 16),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 46),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(title)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    override func inkDidChange() {
        glyph.contentTintColor = ink(Tokens.Text.secondary)
        label.textColor = ink(Tokens.Text.secondary)
    }
}

// MARK: - The fingerprint

/// The picker's fingerprint: the Touch ID symbol, bold and red. The system's
/// own `LAAuthenticationView` draws its fingerprint faint and pink, and on the
/// accent-filled chosen row it all but disappeared. It answers the sensor:
/// a finger accepted turns it into a green tick, one refused shakes it.
@MainActor
final class TouchIDBadge: NSView {

    static let side: CGFloat = 28

    private let glyph = NSImageView()

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityIdentifier(CredentialRowView.biometricIdentifier)

        glyph.image = Self.symbol("touchid")
        glyph.contentTintColor = Tokens.Accent.danger
        glyph.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glyph)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Self.side),
            heightAnchor.constraint(equalToConstant: Self.side),
            glyph.centerXAnchor.constraint(equalTo: centerXAnchor),
            glyph.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    private static func symbol(_ name: String) -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config) ?? NSImage()
    }

    /// The finger was accepted: the fingerprint turns into a tick, in the
    /// green the Mac uses for "this is fine", as Touch ID's own sheet does.
    func succeed() {
        let tick = Self.symbol("checkmark.circle.fill")
        glyph.contentTintColor = Tokens.Accent.secure
        guard !Tokens.A11y.reduceMotion else {
            glyph.image = tick
            return
        }
        glyph.setSymbolImage(tick, contentTransition: .replace.downUp)
        glyph.addSymbolEffect(.bounce)
    }

    /// The finger was refused; the sensor is listening again.
    func refuse() {
        guard !Tokens.A11y.reduceMotion else { return }
        glyph.addSymbolEffect(.wiggle)
    }
}
