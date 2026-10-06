//
//  Passwords.swift
//  Luna
//
//  docs/SETTINGS-SPEC.md §3.10 / §14, a group on the Privacy &
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
import UniformTypeIdentifiers

/// A group on the Privacy & Passwords page (`SettingsGroup`).
@MainActor
final class PasswordsSection: SettingsGroup {

    static let id = "passwords"
    static let title = String(localized: "Passwords")
    static let keywords = ["logins", "passkeys", "autofill", "keychain", "credentials"]

    private let storageLabel = NSTextField(labelWithString: "")

    /// One card: where passwords go first, then the four switches, then
    /// passkeys, whose row says why it is off rather than a note under it.
    func add(to body: SettingsBody) {
        body.card(Self.title, [storageRow()] + switchRows() + [passkeysRow(), manageRow(), importRow(), exportRow()])
        refreshStorageLine()
    }

    // MARK: Rows

    private func switchRows() -> [(view: NSView, terms: [String])] {
        let fill = String(localized: "Offer to fill passwords")
        let save = String(localized: "Offer to save passwords")
        let generate = String(localized: "Suggest strong passwords")
        let auth = String(localized: "Require Touch ID to fill")
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
            (SettingsRow.toggle(auth, value: PasswordSettings.requiresAuthentication) { on in
                PasswordSettings.requiresAuthentication = on
            }, [auth, "login password", "touch id", "biometric", "fingerprint", "authenticate", "unlock"])
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

    // MARK: Import and export (#5, P2.3)

    private func importRow() -> (view: NSView, terms: [String]) {
        let title = String(localized: "Add passwords from a CSV file")
        let row = SettingsRow.button(title, action: String(localized: "Import Passwords…")) {
            Self.importPasswords()
        }
        return (row, [title, "import", "csv", "chrome", "arc", "dia", "1password", "bitwarden"])
    }

    private func exportRow() -> (view: NSView, terms: [String]) {
        let title = String(localized: "Save Luna’s passwords to a CSV file")
        let row = SettingsRow.button(title, action: String(localized: "Export Passwords…")) {
            Task { await Self.exportPasswords() }
        }
        return (row, [title, "export", "csv", "backup"])
    }

    private static func importPasswords() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "Import")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let text = try? String(contentsOf: url, encoding: .utf8),
              let logins = try? PasswordCSV.logins(fromCSV: text)
        else {
            tell(
                String(localized: "Luna couldn’t read that file"),
                String(localized: """
                It needs to be a CSV file with a column for the website and one for the password, \
                as Chrome, the Passwords app, 1Password and Bitwarden export.
                """)
            )
            return
        }
        Task {
            let result = await CredentialStore.shared.importLogins(logins)
            tell(
                String(localized: "Imported \(result.added + result.updated) passwords"),
                String(localized: """
                \(result.added) new, \(result.updated) replaced a password Luna already had, \
                \(result.skipped) skipped for having no password or no website.
                """)
            )
        }
    }

    /// Touch ID before anything else, so the warning and the file dialog are
    /// only ever in front of the person who owns the passwords.
    private static func exportPasswords() async {
        guard await PasswordAuthorization.confirmExport() else { return }
        let logins = await CredentialStore.shared.exportLogins()
        guard !logins.isEmpty else {
            tell(String(localized: "Luna has no saved passwords to export"), "")
            return
        }
        guard SettingsHost.confirm(
            String(localized: "Export \(logins.count) passwords?"),
            String(localized: """
            The file is not encrypted. Anyone who can open it can read every password in it, \
            so delete it once you have imported it elsewhere.
            """),
            action: String(localized: "Export")
        ) else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = String(localized: "Luna Passwords.csv")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        // Removed first so the file is created owner-only rather than
        // overwritten in place, keeping whatever mode the old one had.
        try? FileManager.default.removeItem(at: url)
        let written = FileManager.default.createFile(
            atPath: url.path(percentEncoded: false),
            contents: Data(PasswordCSV.csv(logins).utf8),
            attributes: [.posixPermissions: 0o600]
        )
        if !written {
            tell(String(localized: "Luna couldn’t save the file"), String(localized: "Choose a folder you can write to."))
        }
    }

    private static func tell(_ message: String, _ informative: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = informative
        alert.runModal()
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
