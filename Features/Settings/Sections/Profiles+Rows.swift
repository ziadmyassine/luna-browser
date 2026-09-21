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
        // Untitled, because the first row of the card is the name and a card
        // headed by its own first field says it twice. A Space's card is
        // headed by its gradient and icon, which say something the rows do
        // not; this one has only the name to put up there.
        for profile in session?.profilesByName ?? [] {
            body.card(nil, profileRows(profile, session: session), inList: true)
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
            // Keyed off the count rather than off `canDelete`, which is also
            // false with no session at all — and "0 Spaces are using this" is
            // not a reason for anything.
            disabledReason: spacesOnIt.isEmpty ? nil : Self.inUseReason(spacesOnIt.count)
        ) { [weak self] in self?.deleteProfile(profile, session: session) }
        // Two rows, not three. §9's fan-out stood between them, and on this
        // card it was the same sentence twice: the Spaces sharing a profile
        // are listed above, each one carrying that line on its own card, where
        // it answers the question it exists for — "why am I still logged in
        // over here" is asked about a Space. Here it only described the card
        // it was sitting in. The count it was carrying is not lost: the Delete
        // row states it, and states it where it changes what you can do.
        return [
            (rename, [name, profile.name, "rename profile", "profile name"]),
            pictureRow(profile, session: session),
            (delete, [remove, profile.name, "delete profile", "remove profile", "shared", "favorites"])
        ]
    }

    // MARK: §9's picture

    /// The picture §3.5's avatar wears, chosen and taken off from the same row.
    ///
    /// The thumbnail is in the row rather than only on the avatar because this
    /// is the list of profiles: a column of identical rows saying "Picture"
    /// cannot tell you which of them has one. Remove appears only when there is
    /// something to remove — a permanently dimmed button beside every profile
    /// that has never had a picture is a control that mostly means nothing.
    func pictureRow(
        _ profile: Profile,
        session: BrowserSession?
    ) -> (view: NSView, terms: [String]) {
        let title = String(localized: "Picture")
        let picture = ProfilePicture.image(from: profile.imageData)
        let choose = SettingsPushButton(
            title: picture == nil ? String(localized: "Choose…") : String(localized: "Replace…"),
            isDestructive: false
        )
        choose.onActivate = { [weak self] in self?.choosePicture(for: profile, session: session) }

        var controls: [NSView] = [choose]
        if picture != nil {
            let clear = SettingsPushButton(title: String(localized: "Remove"), isDestructive: true)
            clear.onActivate = { [weak self] in self?.setPicture(nil, on: profile, session: session) }
            controls.append(clear)
        }
        if let picture { controls.insert(Self.thumbnail(picture), at: 0) }

        let row = SettingsRow.accessory(title, subtitle: nil, accessory: Self.side(controls))
        return (row, [title, profile.name, "picture", "photo", "image", "avatar", "profile picture"])
    }

    /// The row's trailing cluster. `chromeGap` between the controls, which is
    /// what two controls take between them everywhere else in the app.
    private static func side(_ views: [NSView]) -> NSView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.spacing = Tokens.Metric.chromeGap
        return stack
    }

    /// The picture at a control's height, round like the avatar that wears it.
    private static func thumbnail(_ image: NSImage) -> NSView {
        let side = Tokens.Metric.settingsControl
        let view = NSImageView(image: image)
        view.imageScaling = .scaleProportionallyUpOrDown
        view.wantsLayer = true
        view.layer?.cornerRadius = side / 2
        view.layer?.masksToBounds = true
        view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: side),
            view.heightAnchor.constraint(equalToConstant: side)
        ])
        return view
    }

    /// One image file, cropped and downsampled on the way in — see
    /// `ProfilePicture` for why the original is not what gets kept.
    private func choosePicture(for profile: Profile, session: BrowserSession?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = String(localized: "Choose a picture for the \(profile.name) profile")
        panel.prompt = String(localized: "Choose")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let data = ProfilePicture.bytes(ofFileAt: url) else {
            // The panel filters by type and the file can still be unreadable —
            // a damaged download, or a format this Mac has no decoder for.
            let alert = NSAlert()
            alert.messageText = String(localized: "That file could not be read as a picture.")
            alert.informativeText = String(localized: "Try a PNG, JPEG or HEIC.")
            alert.runModal()
            return
        }
        setPicture(data, on: profile, session: session)
    }

    private func setPicture(_ data: Data?, on profile: Profile, session: BrowserSession?) {
        guard let session else { return }
        Task { [weak self] in
            do { try await session.setImage(data, forProfile: profile.id) } catch { NSApp.presentError(error) }
            self?.build()
        }
    }

    /// Why Delete is dimmed, counting the Spaces that are the reason.
    ///
    /// The count is here rather than in a line of its own because this is
    /// where it changes what the user can do — see `profileRows`.
    static func inUseReason(_ spaces: Int) -> String {
        spaces == 1
            ? String(localized: "1 Space is using this profile. Move it onto another profile first.")
            : String(localized: "\(spaces) Spaces are using this profile. Move them onto another profile first.")
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
