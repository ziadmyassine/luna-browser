//
//  Passwords.swift
//  Luna
//
//  docs/SETTINGS-SPEC.md §3.10 / TODO.md §14, a group on the Privacy &
//  Passwords page: where passwords go, the switches, and passkeys.
//
//  This section replaces a "deliberately not here" entry, because §14.1's
//  spike has run. The objection was that the window "must not hint at a
//  password manager that may never ship in this shape"; what ships is a bridge
//  into the user's own Keychain, and the spike measured how far it reaches.
//  Both halves are on this page — the half that works today and the half
//  waiting on a signature.
//
//  §30.4 applies with full force: a password pane that overstates what it does
//  is worse than one that does not exist, because the user acts on it. Nothing
//  here describes a capability Luna lacks at the moment the page is drawn — the
//  sync line and the passkey line are rendered from live state.
//

import AppKit
import BrowserKit

/// A group on the Privacy & Passwords page (`SettingsGroup`).
@MainActor
final class PasswordsSection: SettingsGroup {

    static let id = "passwords"
    static let title = String(localized: "Passwords")
    static let keywords = ["logins", "passkeys", "autofill", "keychain", "credentials"]

    private let storageLabel = NSTextField(labelWithString: "")

    /// One card: where passwords go first, then the four switches, then
    /// passkeys, whose row says why it is off rather than a note under it.
    func add(to body: SettingsBody) -> [(view: NSView, terms: [String])] {
        body.card(Self.title, [storageRow()] + switchRows() + [passkeysRow(), manageRow()])
        body.loose(
            SettingsRow.note(String(localized: """
            Luna has no password vault or account of its own. It can’t read what Safari has saved; \
            only Apple’s apps can.
            """)),
            terms: ["keychain", "safari", "passwords app", "icloud", "vault", "import"]
        )
        refreshStorageLine()
        return []
    }

    // MARK: Rows

    private func switchRows() -> [(view: NSView, terms: [String])] {
        let fill = String(localized: "Offer to fill passwords")
        let save = String(localized: "Offer to save passwords")
        let generate = String(localized: "Suggest strong passwords")
        let auth = String(localized: "Require Touch ID to fill")
        // Names the fallback, because a Mac without Touch ID would otherwise
        // read this row as one that does nothing for them.
        let authDetail = String(localized: "Or your login password")
        return [
            (SettingsRow.toggle(fill, value: PasswordSettings.isEnabled) { on in
                PasswordSettings.isEnabled = on
            }, [fill, "autofill", "login", "sign in"]),
            (SettingsRow.toggle(save, value: PasswordSettings.offersToSave) { on in
                PasswordSettings.offersToSave = on
            }, [save, "save", "remember"]),
            (SettingsRow.toggle(generate, value: PasswordSettings.offersGeneratedPasswords) { on in
                PasswordSettings.offersGeneratedPasswords = on
            }, [generate, "generate", "strong", "random"]),
            (SettingsRow.toggle(auth, subtitle: authDetail, value: PasswordSettings.requiresAuthentication) { on in
                PasswordSettings.requiresAuthentication = on
            }, [auth, authDetail, "touch id", "biometric", "fingerprint", "authenticate", "unlock"])
        ]
    }

    private func storageRow() -> (view: NSView, terms: [String]) {
        storageLabel.font = Tokens.TypeScale.settingsRow
        storageLabel.textColor = Tokens.Text.secondary
        storageLabel.lineBreakMode = .byWordWrapping
        storageLabel.usesSingleLineMode = false
        storageLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let title = String(localized: "Saved to")
        let row = SettingsRow.accessory(title, subtitle: nil, accessory: storageLabel)
        return (row, [title, "keychain", "icloud", "sync", "passwords app"])
    }

    private func passkeysRow() -> (view: NSView, terms: [String]) {
        let title = String(localized: "Passkeys")
        // One line, not `PasskeySupport.statusDescription`'s paragraph: the row
        // only has to say why the switch will not move.
        let reason = PasskeySupport.isAvailable
            ? String(localized: "Sites can offer passkey sign-in")
            : String(localized: "Needs permission from Apple, which Luna doesn’t have yet")
        let row = SettingsRow.toggle(
            title,
            value: PasskeySupport.isAvailable,
            isEnabled: false,
            disabledReason: reason
        ) { _ in }
        return (row, [title, "passkey", "webauthn", "security key", "fido", "entitlement"])
    }

    private func manageRow() -> (view: NSView, terms: [String]) {
        let title = String(localized: "See and edit saved passwords")
        let row = SettingsRow.button(title, action: String(localized: "Open Passwords…")) {
            // The Passwords app, by bundle identifier rather than by path: it
            // moved out of System Settings in macOS 15 and a hard-coded path
            // would break again the next time Apple moves it.
            let url = URL(fileURLWithPath: "/System/Applications/Passwords.app")
            if FileManager.default.fileExists(atPath: url.path) {
                NSWorkspace.shared.open(url)
            } else {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Passwords-Settings.extension")!)
            }
        }
        return (row, [title, "manage", "edit", "delete", "passwords app"])
    }

    // MARK: Live state

    /// Re-probes rather than trusting a value latched at launch: the whole
    /// point of the probe is that its answer changes the day Luna is signed,
    /// and a settings pane that had to be reopened to notice would be the last
    /// place anyone looked.
    private func refreshStorageLine() {
        Task { [weak self] in
            let capability = await CredentialStore.shared.refreshCapability()
            guard let self else { return }
            storageLabel.stringValue = Self.describe(capability)
        }
    }

    static func describe(_ capability: CredentialStore.Capability) -> String {
        switch capability {
        case .synced:
            String(localized: "iCloud Keychain — they appear in the Passwords app and on your other devices")
        case .local, .unknown:
            String(localized: "This Mac only — syncing to your other devices needs a signed build of Luna")
        case let .unavailable(status):
            // Interpolated as a string, not as an `Int`. `String(localized:)`
            // formats an integer interpolation for the locale, which turns
            // `-25300` into `-25,300` — and the only reason the number is here
            // at all is so the user can search for it. A grouping separator
            // makes it unfindable, which is worse than omitting it.
            String(localized: "The Keychain refused to save (error \(String(status)))")
        }
    }
}
