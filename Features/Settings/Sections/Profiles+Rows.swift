//
//  Profiles+Rows.swift
//  Luna
//
//  §9's Profiles as a group of their own in the Spaces pane: one card each,
//  named, made and unmade.
//
//  They were reachable from exactly one control before this — the popup on a
//  Space's card that moves that Space onto a different one. So a Profile could
//  be chosen between and never named: `createSpace` names a new Profile after
//  the Space being made and nothing afterwards could change it, which left
//  every Space made by §30.9's swipe on a Profile called `Space 2`.
//
//  A third file on this section rather than more of either half: the two that
//  exist are the section's own rows and the dialogs those rows raise, and this
//  is neither — it is a second list beside the first one.
//

import AppKit
import BrowserKit

extension SpacesSection {

    /// §9's group, under the Spaces it explains.
    func profileCards(_ session: BrowserSession?) {
        let add = newProfileButton(session: session)
        body.heading(SettingsRow.heading(String(localized: "Profiles"), accessory: add.view), terms: add.terms)
        for profile in session?.profilesByName ?? [] {
            body.card(profile.name, profileRows(profile, session: session))
        }
    }

    /// Name, what is on it, and whether it can go.
    ///
    /// Internal for `SpacesSectionTests`' reason: the rows are assertable
    /// without a running session, and "every row is live" is the claim this
    /// section has had to keep before.
    func profileRows(
        _ profile: Profile,
        session: BrowserSession?
    ) -> [(view: NSView, terms: [String])] {
        let spacesOnIt = session?.spaces(onProfile: profile.id) ?? []
        let fanOut = SpacesSection.fanOutLabel(
            profileName: profile.name,
            spacesOnProfile: spacesOnIt,
            favorites: session?.favorites(onProfile: profile.id).count ?? 0
        )
        let name = String(localized: "Name")
        let rename = SettingsRow.text(
            name, value: profile.name, placeholder: profile.name, limit: SpaceNameFormatter()
        ) { [weak self] typed in
            let new = typed.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !new.isEmpty, new != profile.name, let session else { return }
            Task {
                do { try await session.renameProfile(profile.id, to: new) } catch { NSApp.presentError(error) }
                self?.build()
            }
        }
        // Empty only while a Space still names it, which is the store's rule
        // and not this pane's: deleting a jar out from under a Space would
        // sign it out of everything with nothing to undo it.
        let canDelete = spacesOnIt.isEmpty && session != nil
        let remove = String(localized: "Delete this profile")
        let delete = SettingsRow.button(
            remove,
            action: String(localized: "Delete…"),
            isDestructive: true,
            isEnabled: canDelete,
            disabledReason: canDelete ? nil : String(localized: """
            A profile in use cannot be deleted. Move its Spaces onto another profile first.
            """)
        ) { [weak self] in self?.deleteProfile(profile, session: session) }
        return [
            (rename, [name, profile.name, "rename profile", "profile name"]),
            (SettingsRow.note(fanOut), [fanOut, "shared", "spaces", "favorites"]),
            (delete, [remove, profile.name, "delete profile", "remove profile"])
        ]
    }

    // MARK: Making one

    func newProfileButton(session: BrowserSession?) -> (view: NSView, terms: [String]) {
        let title = String(localized: "New Profile")
        let button = SettingsPushButton(title: title, isDestructive: false)
        button.onActivate = { [weak self] in self?.createProfile(session: session) }
        return (button, [title, "new profile", "add profile", "separate cookies", "logins"])
    }

    private func createProfile(session: BrowserSession?) {
        guard let session else { return }
        let field = NSTextField(frame: NSRect(origin: .zero, size: Tokens.Metric.urlPill.size))
        field.placeholderString = String(localized: "New Profile")
        field.formatter = SpaceNameFormatter()

        let alert = NSAlert()
        alert.messageText = String(localized: "Name the new profile")
        // What a Profile with nothing on it is for, because an empty cookie
        // jar does nothing until a Space is pointed at it and the button that
        // does that is on the other card.
        alert.informativeText = String(localized: """
        A profile is a set of cookies and logins. This one starts empty and signed out of everything. \
        Move a Space onto it from that Space's Profile row — its tabs reload against the new profile, \
        so it is signed out of anywhere the old one was signed in.
        """)
        alert.accessoryView = Self.stack([field])
        alert.addButton(withTitle: String(localized: "Create"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.buttons.last?.keyEquivalent = "\u{1b}"
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let typed = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else { return }
        Task { [weak self] in
            do { try await session.createProfile(named: typed) } catch { NSApp.presentError(error) }
            self?.build()
        }
    }

    // MARK: Unmaking one

    private func deleteProfile(_ profile: Profile, session: BrowserSession?) {
        guard let session else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Delete the \(profile.name) profile?")
        alert.informativeText = String(localized: """
        No Space is using it, so no tabs, Favorites or logins go with it. Its cookies were cleared when \
        the last Space left it.
        """)
        alert.addButton(withTitle: String(localized: "Delete"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.buttons.last?.keyEquivalent = "\u{1b}"
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task { [weak self] in
            do { try await session.deleteProfile(profile.id) } catch { NSApp.presentError(error) }
            self?.build()
        }
    }
}
