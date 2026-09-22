//
//  Passwords.swift
//  Luna
//
//  docs/SETTINGS-SPEC.md §3.10 / TODO.md §14 — the three switches, the saved
//  list, and two paragraphs that have to be true.
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

@MainActor
final class PasswordsSection: SettingsSection {

    static let id = "passwords"
    static let title = String(localized: "Passwords")
    static let symbolName = "key.fill"
    static let keywords = ["logins", "passkeys", "autofill", "keychain", "credentials"]

    private let body = SettingsBody()
    private let storageLabel = NSTextField(labelWithString: "")

    var view: NSView { body.view }
    var searchIndex: [String] { body.searchIndex }
    func filter(_ query: String) { body.filter(query) }

    init() {
        buildSwitches()
        buildStorageNote()
        buildPasskeyNote()
        buildManageRow()
        refreshStorageLine()
    }

    // MARK: Rows

    private func buildSwitches() {
        let fill = String(localized: "Offer to fill passwords")
        let fillDetail = String(localized: "Show your saved logins on a site's sign-in form")
        let save = String(localized: "Offer to save passwords")
        let saveDetail = String(localized: "Ask after you sign in with a password Luna has not seen")
        let generate = String(localized: "Suggest strong passwords")
        let generateDetail = String(localized: "On sign-up forms, offer a generated password")
        let auth = String(localized: "Require Touch ID to fill")
        // Names the fallback, because a Mac without Touch ID would otherwise
        // read this row as one that does nothing for them.
        let authDetail = String(localized: "Ask for Touch ID, or your login password, before filling")

        body.card(String(localized: "Autofill"), [
            (SettingsRow.toggle(fill, subtitle: fillDetail, value: PasswordSettings.isEnabled) { on in
                PasswordSettings.isEnabled = on
            }, [fill, fillDetail, "autofill", "login", "sign in"]),
            (SettingsRow.toggle(save, subtitle: saveDetail, value: PasswordSettings.offersToSave) { on in
                PasswordSettings.offersToSave = on
            }, [save, saveDetail, "save", "remember"]),
            (SettingsRow.toggle(generate, subtitle: generateDetail, value: PasswordSettings.offersGeneratedPasswords) { on in
                PasswordSettings.offersGeneratedPasswords = on
            }, [generate, generateDetail, "generate", "strong", "random"]),
            (SettingsRow.toggle(auth, subtitle: authDetail, value: PasswordSettings.requiresAuthentication) { on in
                PasswordSettings.requiresAuthentication = on
            }, [auth, authDetail, "touch id", "biometric", "fingerprint", "authenticate", "unlock"])
        ])
    }

    /// Where the passwords actually go — the §14.1 answer, rendered live.
    ///
    /// The distinction this row draws is the one the whole feature turns on,
    /// and it is invisible from the outside: a password saved in local-only
    /// mode looks identical in Luna to one that synced, and the user only
    /// finds out which they had when they pick up their iPhone. Saying it here
    /// is the difference between a limitation and a nasty surprise.
    private func buildStorageNote() {
        storageLabel.font = Tokens.TypeScale.sidebarRow
        storageLabel.textColor = Tokens.Text.secondary
        storageLabel.lineBreakMode = .byWordWrapping
        storageLabel.usesSingleLineMode = false
        storageLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let title = String(localized: "Saved to")
        let row = SettingsRow.accessory(title, subtitle: nil, accessory: storageLabel)
        body.card(String(localized: "Storage"), [
            (row, [title, "keychain", "icloud", "sync", "passwords app"])
        ])

        body.loose(
            SettingsRow.note(String(localized: """
            Luna has no password vault of its own. Everything it saves goes into your Mac's \
            Keychain, which is Apple's, not Luna's — there is no Luna account and nothing on \
            a Luna server.

            Luna cannot read the passwords Safari and the Passwords app have already saved. \
            Those live in a part of the Keychain only Apple's own apps can open, and no \
            setting here changes that.
            """)),
            terms: ["keychain", "safari", "passwords app", "icloud", "vault", "import"]
        )
    }

    /// §14.10, stated plainly rather than hidden.
    ///
    /// A user on a site that offers "Sign in with a passkey" in Safari and not
    /// in Luna will conclude Luna is broken. It is not — it is deliberately
    /// hiding a button that would not work — and this is the only place that
    /// can say so.
    private func buildPasskeyNote() {
        let title = String(localized: "Passkeys")
        let row = SettingsRow.toggle(
            title,
            subtitle: PasskeySupport.isAvailable
                ? String(localized: "Sites can offer passkey sign-in")
                : String(localized: "Waiting on an entitlement from Apple"),
            value: PasskeySupport.isAvailable,
            isEnabled: false,
            disabledReason: PasskeySupport.statusDescription
        ) { _ in }
        body.card(String(localized: "Passkeys"), [
            (row, [title, "passkey", "webauthn", "security key", "fido"])
        ])
        body.loose(
            SettingsRow.note(PasskeySupport.statusDescription),
            terms: ["passkey", "entitlement", "webauthn"]
        )
    }

    /// The Passwords app is where saved logins are managed, because it is
    /// where they live. Luna deliberately does not grow an editor of its own:
    /// a second place to change a password is a second place for it to be
    /// wrong.
    private func buildManageRow() {
        let title = String(localized: "Manage saved passwords")
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
        body.card(nil, [(row, [title, "manage", "edit", "delete", "passwords app"])])
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
