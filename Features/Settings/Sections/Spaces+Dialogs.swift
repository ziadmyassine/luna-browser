//
//  Spaces+Dialogs.swift
//  Luna
//
//  Everything §3.7's Spaces section asks rather than shows: creating a Space
//  onto a chosen profile, §6.4's deletion dialog, moving a Space across a
//  profile boundary, clearing a profile's cookies — and the four pure
//  functions that write their sentences.
//
//  Split out of `Spaces.swift` because that file grew past the project's
//  400-line rule the moment a Space had six settings instead of one. The
//  strings are `static` and free of AppKit on purpose: a dialog whose wording
//  can only be checked by clicking it is a dialog whose wording is never
//  checked, and these four are the ones that have to beat Firefox's and
//  Chrome's.
//

import AppKit
import BrowserKit
import WebKit

@MainActor
extension SpacesSection {

    // MARK: New Space (§6.1)

    /// Creating a Space now asks which cookie jar it lands in, which is the
    /// half that was modelled and unreachable: `createSpace` always minted a
    /// fresh `Profile`, so many Spaces to one Profile could be stored and never
    /// made. The popup's first entry is a new profile; the rest are the ones
    /// that exist.
    /// A button beside the section's heading, not a row in a card. As a row
    /// it needed a card, and the card needed a heading, so the pane read
    /// `Spaces` ▸ card ▸ `New Space` ▸ `[New Space]`. The heading names what
    /// the cards below it are and this adds one; see `SettingsRow.heading`.
    func newSpaceButton(
        sharing spaces: [Space],
        session: BrowserSession?
    ) -> (view: NSView, terms: [String]) {
        let title = String(localized: "New Space")
        let button = SettingsPushButton(title: title, isDestructive: false)
        button.onActivate = { [weak self] in self?.createSpace(session: session) }
        return (button, [title, "add space", "create space", "share profile"])
    }

    private func createSpace(session: BrowserSession?) {
        guard let session else { return }
        let profiles = session.profiles.values.sorted { $0.name < $1.name }
        let field = NSTextField(frame: NSRect(origin: .zero, size: Tokens.Metric.urlPill.size))
        field.placeholderString = String(localized: "New Space")
        let picker = NSPopUpButton(frame: .zero, pullsDown: false)
        picker.addItem(withTitle: String(localized: "Its own profile — separate cookies and logins"))
        for profile in profiles {
            picker.addItem(withTitle: String(localized: "Share the \(profile.name) profile"))
        }

        let alert = NSAlert()
        alert.messageText = String(localized: "Name the new Space")
        alert.informativeText = String(localized: """
        A Space on its own profile is logged out of everything. A Space sharing a profile is already \
        logged in wherever that profile is, and shares its Favorites.
        """)
        alert.accessoryView = Self.stack([field, picker])
        alert.addButton(withTitle: String(localized: "Create"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.buttons.last?.keyEquivalent = "\u{1b}"
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let typed = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else { return }
        let choice = picker.indexOfSelectedItem
        // Passed explicitly, never defaulted: "its own profile" is an answer the
        // user gave, not one this call site inherited.
        let profileID: UUID? = choice > 0 && profiles.indices.contains(choice - 1) ? profiles[choice - 1].id : nil
        Task {
            do {
                try await session.createSpace(name: typed, profileID: profileID)
            } catch {
                NSApp.presentError(error)
            }
            build()
        }
    }

    // MARK: §6.4's deletion dialog

    /// Firefox warns about the tab count and says nothing about the cookies and
    /// logins it is about to destroy. Chrome itemises the data and never says
    /// that it force-closes your windows. Luna has to say a third thing neither
    /// of them has to, because Space → Profile is many-to-one: whether the
    /// cookies go at all depends on who else is on this profile.
    ///
    /// And it offers the choice §6.3 added rather than announcing a loss: the
    /// tabs are archived, or adopted into another Space. Nothing is destroyed
    /// on the way through and the whole thing is undoable, so the dialog says
    /// that instead of Vivaldi's "this cannot be undone".
    func delete(_ space: Space) {
        guard let session = SettingsHost.session else { return }
        let others = session.spaces.filter { $0.id != space.id }
        let sharing = session.spaces(onProfile: space.profileID).filter { $0.id != space.id }
        let tabCount = session.list[space.id].count

        // The site count is the one number that has to be fetched. WebKit is
        // the only thing that knows it, `fetchDataRecords` is async, and a
        // dialog that guessed would be worse than one that waits a beat.
        Task {
            let sites = sharing.isEmpty ? await Self.siteCount(session.dataStore(forSpace: space.id)) : nil
            guard let policy = self.askDeletion(space, others: others, sharing: sharing, tabs: tabCount, sites: sites)
            else { return }
            do { try await session.deleteSpace(space.id, policy: policy) } catch { NSApp.presentError(error) }
            self.build()
        }
    }

    private func askDeletion(
        _ space: Space,
        others: [Space],
        sharing: [Space],
        tabs: Int,
        sites: Int?
    ) -> SpaceDeletionPolicy? {
        guard !others.isEmpty else { return nil }
        let picker = NSPopUpButton(frame: .zero, pullsDown: false)
        picker.addItem(withTitle: String(localized: "Archive its tabs — ⌘⇧T still reopens them"))
        for other in others {
            picker.addItem(withTitle: String(localized: "Move its tabs to \(other.name)"))
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = Self.deletionTitle(space)
        alert.informativeText = Self.deletionDetail(
            profileName: SettingsHost.session?.profile(for: space)?.name ?? space.name,
            tabs: tabs,
            sites: sites,
            sharing: sharing.map(\.name)
        )
        if tabs > 0 { alert.accessoryView = Self.stack([picker]) }
        alert.addButton(withTitle: String(localized: "Delete Space"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.buttons.last?.keyEquivalent = "\u{1b}"
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let choice = picker.indexOfSelectedItem
        // Explicit both ways. A `deleteSpace` that silently took `.archiveTabs`
        // because nobody chose is the ambiguity this dialog exists to remove.
        guard tabs > 0, choice > 0, others.indices.contains(choice - 1) else { return .archiveTabs }
        return .adopt(into: others[choice - 1].id)
    }

    /// Arc's wording for the same operation, which is the only prior art that
    /// allows it at all: Firefox and Chrome refuse to move anything across a
    /// profile boundary, and Zen allows it silently and it does not work.
    func confirmProfileSwap(_ space: Space, to profile: Profile) -> Bool {
        SettingsHost.confirm(
            String(localized: "Move “\(space.name)” onto the \(profile.name) profile?"),
            String(localized: """
            Its tabs reload against \(profile.name)'s cookies, so anywhere this Space was signed in and \
            \(profile.name) is not, it is signed out. Its Favorites change to \(profile.name)'s — Favorites \
            belong to the profile, not to the Space.
            """),
            action: String(localized: "Move")
        )
    }

    // MARK: Profiles

    /// Was dimmed for "BrowserStore has no delete(profileID:)". It is not a
    /// row about deleting the row — every profile has at least one Space
    /// naming it, so a deletable profile cannot be reached from here. What the
    /// user actually wants from this button is the cookie jar emptied, which
    /// WebKit does directly and which is honest about affecting every Space on
    /// the profile.
    func clearProfileDataRow(
        _ spaces: [Space],
        session: BrowserSession?
    ) -> (view: NSView, terms: [String]) {
        let title = String(localized: "Sign out of a profile everywhere")
        let row = SettingsRow.button(
            title,
            action: String(localized: "Clear…"),
            isDestructive: true,
            isEnabled: session != nil && !spaces.isEmpty
        ) { [weak self] in self?.clearProfileData(spaces, session: session) }
        return (row, [title, "clear profile", "website data", "cookies", "sign out", "logout"])
    }

    private func clearProfileData(_ spaces: [Space], session: BrowserSession?) {
        guard let session else { return }
        let profiles = session.profiles.values.sorted { $0.name < $1.name }
            .filter { profile in spaces.contains { $0.profileID == profile.id } }
        guard let first = profiles.first else { return }

        let picker = NSPopUpButton(frame: .zero, pullsDown: false)
        for profile in profiles {
            let count = session.spaces(onProfile: profile.id).count
            picker.addItem(withTitle: Self.fanOutLabel(
                profileName: profile.name,
                spacesOnProfile: session.spaces(onProfile: profile.id),
                favorites: session.favorites(onProfile: profile.id).count
            ))
            picker.lastItem?.tag = count
        }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Clear a profile's cookies and logins?")
        alert.informativeText = String(localized: """
        Every Space on the profile is signed out of everything at once — that is what sharing a profile \
        means. The Spaces, their tabs and their Favorites stay; only the cookies, logins and site data go, \
        and that cannot be undone.
        """)
        alert.accessoryView = Self.stack([picker])
        alert.addButton(withTitle: String(localized: "Clear"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.buttons.last?.keyEquivalent = "\u{1b}"
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let chosen = profiles.indices.contains(picker.indexOfSelectedItem)
            ? profiles[picker.indexOfSelectedItem]
            : first
        guard let space = spaces.first(where: { $0.profileID == chosen.id }) else { return }
        let store = session.dataStore(forSpace: space.id)
        Task {
            await store.removeData(
                ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                modifiedSince: .distantPast
            )
            build()
        }
    }

    // MARK: - The strings, as pure functions

    /// §9's label, and the reason this section exists in the shape it does.
    ///
    /// Arc has no UI anywhere that shows a Space's profile fan-out, and neither
    /// does Chrome or Firefox. It is the root of the most-reported conceptual
    /// confusion in every review of Arc, predicted by Mozilla in 2016 and still
    /// open: *"A user may open an account in one container and not understand
    /// why they are not logged into the account on other containers."*
    static func fanOutLabel(profileName: String, spacesOnProfile: [Space], favorites: Int) -> String {
        let tiles = favorites == 1
            ? String(localized: "1 Favorite")
            : String(localized: "\(favorites) Favorites")
        guard spacesOnProfile.count > 1 else {
            return String(localized: "\(profileName) profile · this Space only · \(tiles)")
        }
        return String(localized: "\(profileName) profile · shared with \(spacesOnProfile.count) Spaces · \(tiles)")
    }

    static func deletionTitle(_ space: Space) -> String {
        String(localized: "Delete “\(space.name)”?")
    }

    /// The three clauses, and which of them is true depends on the fan-out.
    ///
    /// `sites` is nil exactly when the profile is shared, because then the
    /// cookie jar is not deleted at all — `deleteSpace` only removes a store no
    /// surviving Space names. §6.4's example sentence ("permanently deletes
    /// cookies … Spaces Research and Side Project also use this profile and
    /// will be affected") states both halves of that at once and is false in
    /// the one case the clause was written for; this says the true thing.
    static func deletionDetail(profileName: String, tabs: Int, sites: Int?, sharing: [String]) -> String {
        var clauses: [String] = []
        switch tabs {
        case 0: clauses.append(String(localized: "It has no open tabs."))
        case 1: clauses.append(String(localized: "Its 1 open tab is kept — archived, or moved to the Space you pick below."))
        default: clauses.append(String(localized: "Its \(tabs) open tabs are kept — archived, or moved to the Space you pick below."))
        }
        if sharing.isEmpty {
            switch sites {
            case let .some(count) where count > 0:
                clauses.append(String(localized: """
                This permanently deletes cookies, logins and site data for \(count) sites, because no other \
                Space uses the \(profileName) profile.
                """))
            default:
                clauses.append(String(localized: """
                This permanently deletes the \(profileName) profile's cookies, logins and site data, because \
                no other Space uses it.
                """))
            }
        } else {
            clauses.append(String(localized: """
            Its cookies and logins stay: \(Self.list(sharing)) also use the \(profileName) profile, and \
            deleting this Space does not touch it.
            """))
        }
        clauses.append(String(localized: "Undo restores the Space and everything in it."))
        return clauses.joined(separator: " ")
    }

    /// "Research", "Research and Side Project", "A, B and C".
    static func list(_ names: [String]) -> String {
        switch names.count {
        case 0: return ""
        case 1: return String(localized: "Space \(names[0])")
        default:
            let head = names.dropLast().joined(separator: ", ")
            return String(localized: "Spaces \(head) and \(names[names.count - 1])")
        }
    }

    // MARK: - Bits

    /// §13.10: Arc supports emoji as well as SF Symbols, and SigmaOS is
    /// emoji-first. Luna is symbols-only for now and that is named in the
    /// report rather than pretended away.
    ///
    /// The first entry is the one a Space is born with. It was missing, and
    /// it made the picker lie: `firstIndex(of:) ?? 0` showed "Grid" selected on
    /// every Space that had never been re-iconed, which was all of them.
    /// `SpaceAppearanceView` marks the icon a Space actually wears, so the same
    /// gap showed up honestly instead — as a grid with nothing chosen in it.
    static let symbols: [(label: String, name: String)] = [
        (String(localized: "Moon"), BrowserSession.defaultSpaceSymbol),
        (String(localized: "Grid"), "square.grid.2x2"),
        (String(localized: "Planet"), "globe.americas"),
        (String(localized: "Briefcase"), "briefcase"),
        (String(localized: "House"), "house"),
        (String(localized: "Book"), "book"),
        (String(localized: "Hammer"), "hammer"),
        (String(localized: "Flask"), "flask"),
        (String(localized: "Cart"), "cart"),
        (String(localized: "Heart"), "heart"),
        (String(localized: "Bolt"), "bolt"),
        (String(localized: "Leaf"), "leaf"),
        (String(localized: "Music"), "music.note")
    ]

    private static func siteCount(_ store: WKWebsiteDataStore) async -> Int {
        await store.dataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()).count
    }

    /// `NSAlert.accessoryView` is laid out by the alert, which does not do Auto
    /// Layout for it — a stack with a frame is the shape that survives.
    private static func stack(_ views: [NSView]) -> NSView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = Tokens.Metric.rowGap
        stack.frame = NSRect(
            origin: .zero,
            size: CGSize(
                width: Tokens.Metric.urlPill.width,
                height: Tokens.Metric.urlPill.height * CGFloat(views.count) + Tokens.Metric.rowGap
            )
        )
        return stack
    }
}
