//
//  Spaces+Dialogs.swift
//  Luna
//
//  Everything §3.7's Spaces section asks rather than shows: naming a new Space,
//  §6.4's deletion dialog, clearing a Space's cookies — and the pure functions
//  that write their sentences.
//
//  Split out of `Spaces.swift` when a Space grew six settings instead of one.
//  The strings are `static` and free of AppKit on purpose: a dialog whose
//  wording can only be checked by clicking it is one whose wording is never
//  checked.
//

import AppKit
import BrowserKit
import WebKit

@MainActor
extension SpacesSection {

    // MARK: New Space (§6.1)

    /// A button beside the section's heading, not a row in a card. As a row
    /// it needed a card, and the card needed a heading, so the pane read
    /// `Spaces` ▸ card ▸ `New Space` ▸ `[New Space]`. The heading names what
    /// the cards below it are and this adds one; see `SettingsRow.heading`.
    func newSpaceButton(session: BrowserSession?) -> (view: NSView, terms: [String]) {
        let title = String(localized: "New Space")
        let button = SettingsPushButton(title: title, isDestructive: false)
        button.onActivate = { [weak self] in self?.createSpace(session: session) }
        return (button, [title, "add space", "create space", "new profile"])
    }

    /// A name, and nothing else to decide.
    ///
    /// It asked which cookie jar to use until §9's `v7`: a Space could be put
    /// on another Space's jar, which is the one question in this pane nobody
    /// ever answered on purpose. Every Space has its own now, so the dialog is
    /// a field.
    private func createSpace(session: BrowserSession?) {
        guard let session else { return }
        let field = NSTextField(frame: NSRect(origin: .zero, size: Tokens.Metric.urlPill.size))
        field.placeholderString = String(localized: "New Space")
        field.formatter = SpaceNameFormatter()

        let alert = NSAlert()
        alert.messageText = String(localized: "Name the new Space")
        alert.informativeText = String(localized: """
        It starts signed out of everything: a Space keeps its own cookies and logins, so an account \
        you sign into here is not signed in anywhere else.
        """)
        alert.accessoryView = Self.stack([field])
        alert.addButton(withTitle: String(localized: "Create"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.buttons.last?.keyEquivalent = "\u{1b}"
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let typed = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else { return }
        Task {
            do { try await session.createSpace(name: typed) } catch { NSApp.presentError(error) }
            build()
        }
    }

    // MARK: §6.4's deletion dialog

    /// Firefox warns about the tab count and says nothing about the cookies and
    /// logins it is about to destroy. Chrome itemises the data and never says
    /// that it force-closes your windows. Luna says both.
    ///
    /// And it offers the choice §6.3 added rather than announcing a loss: the
    /// tabs are archived, or adopted into another Space. Nothing is destroyed
    /// on the way through and the whole thing is undoable, so the dialog says
    /// that instead of Vivaldi's "this cannot be undone".
    func delete(_ space: Space) {
        guard let session = SettingsHost.session else { return }
        let others = session.spaces.filter { $0.id != space.id }
        let tabCount = session.list[space.id].count

        // The site count is the one number that has to be fetched. WebKit is
        // the only thing that knows it, `fetchDataRecords` is async, and a
        // dialog that guessed would be worse than one that waits a beat.
        Task {
            let sites = await Self.siteCount(session.dataStore(forSpace: space.id))
            guard let policy = self.askDeletion(space, others: others, tabs: tabCount, sites: sites)
            else { return }
            do { try await session.deleteSpace(space.id, policy: policy) } catch { NSApp.presentError(error) }
            self.build()
        }
    }

    private func askDeletion(
        _ space: Space,
        others: [Space],
        tabs: Int,
        sites: Int?
    ) -> SpaceDeletionPolicy? {
        guard !others.isEmpty else { return nil }
        let picker = NSPopUpButton(frame: .zero, pullsDown: false)
        picker.addItem(withTitle: String(localized: "Keep its tabs in History — ⌘⇧T still reopens them"))
        for other in others {
            picker.addItem(withTitle: String(localized: "Move its tabs to \(other.name)"))
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = Self.deletionTitle(space)
        alert.informativeText = Self.deletionDetail(spaceName: space.name, tabs: tabs, sites: sites)
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

    // MARK: Signing out

    /// Not a row about deleting anything: the Space stays, its tabs stay, its
    /// Favorites stay, and what goes is the cookie jar's contents. WebKit
    /// empties one directly.
    func clearProfileDataRow(
        _ spaces: [Space],
        session: BrowserSession?
    ) -> (view: NSView, terms: [String]) {
        let title = String(localized: "Sign a Space out of everything")
        let row = SettingsRow.button(
            title,
            action: String(localized: "Clear…"),
            isDestructive: true,
            isEnabled: session != nil && !spaces.isEmpty
        ) { [weak self] in self?.clearProfileData(spaces, session: session) }
        return (row, [title, "clear profile", "website data", "cookies", "sign out", "logout"])
    }

    /// Signs one Space out of everything without deleting it.
    ///
    /// It asked which *profile* to clear until §9's `v7`, and warned that every
    /// Space on it went at once — which was the whole hazard of sharing one.
    /// A Space owns its jar now, so the question is which Space, and the answer
    /// affects nothing else.
    private func clearProfileData(_ spaces: [Space], session: BrowserSession?) {
        guard let session, let first = spaces.first else { return }

        let picker = NSPopUpButton(frame: .zero, pullsDown: false)
        for space in spaces {
            picker.addItem(withTitle: Self.fanOutLabel(
                spaceName: space.name,
                favorites: session.favorites(inSpace: space.id).count
            ))
        }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Clear a Space's cookies and logins?")
        alert.informativeText = String(localized: """
        The Space, its tabs and its Favorites stay; only the cookies, logins and site data go, and that \
        cannot be undone. No other Space is touched.
        """)
        alert.accessoryView = Self.stack([picker])
        alert.addButton(withTitle: String(localized: "Clear"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.buttons.last?.keyEquivalent = "\u{1b}"
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let chosen = spaces.indices.contains(picker.indexOfSelectedItem)
            ? spaces[picker.indexOfSelectedItem]
            : first
        let store = session.dataStore(forSpace: chosen.id)
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
    /// What a Space's own jar holds, for the one dialog that asks you to pick
    /// between them.
    ///
    /// It was §9's fan-out — "shared with 3 Spaces" — and the answer to the
    /// most-reported conceptual confusion in every review of Arc, predicted by
    /// Mozilla in 2016: *"A user may open an account in one container and not
    /// understand why they are not logged into the account on other
    /// containers."* Luna answered it by explaining the sharing. `v7` answered
    /// it by ending the sharing, so all that is left to say is whose tiles
    /// these are.
    static func fanOutLabel(spaceName: String, favorites: Int) -> String {
        String(localized: "\(spaceName) · \(favoritesLabel(favorites))")
    }

    /// The count on its own, for the card's head, where the name is already
    /// the line above. One Favorite must not read "1 Favorites".
    static func favoritesLabel(_ favorites: Int) -> String {
        favorites == 1
            ? String(localized: "1 Favorite")
            : String(localized: "\(favorites) Favorites")
    }

    static func deletionTitle(_ space: Space) -> String {
        String(localized: "Delete “\(space.name)”?")
    }

    /// Three clauses: what happens to the tabs, what happens to the logins, and
    /// that the whole thing is undoable.
    ///
    /// The second one used to have two forms, because a shared cookie jar was
    /// not deleted with the Space that named it — §6.4's example sentence
    /// ("permanently deletes cookies … Spaces Research and Side Project also
    /// use this profile and will be affected") states both halves at once and
    /// was false in the one case the clause was written for. A Space owns its
    /// jar now, so there is one true thing to say and this says it.
    static func deletionDetail(spaceName: String, tabs: Int, sites: Int?) -> String {
        var clauses: [String] = []
        switch tabs {
        case 0: clauses.append(String(localized: "It has no open tabs."))
        case 1: clauses.append(String(localized: "Its 1 open tab is kept — in History, or moved to the Space you pick below."))
        default: clauses.append(String(localized: "Its \(tabs) open tabs are kept — in History, or moved to the Space you pick below."))
        }
        switch sites {
        case let .some(count) where count > 0:
            clauses.append(String(localized: """
            This permanently deletes cookies, logins and site data for \(count) sites. No other Space is \
            signed out.
            """))
        default:
            clauses.append(String(localized: """
            This permanently deletes \(spaceName)'s cookies, logins and site data. No other Space is \
            signed out.
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
    /// Internal for `body`'s reason: every dialog this section raises stands
    /// its fields in one of these, and §9's Profile dialogs are next door.
    ///
    /// The width is stated here because the stack takes it away. Adding a view
    /// to an `NSStackView` turns that view's autoresizing mask off, so the
    /// frame it was built with is dropped and Auto Layout sizes it to its own
    /// content — and an empty `NSTextField`'s own content is nothing. Every
    /// field in every dialog this pane raises came out a few points wide, tall
    /// enough to be a field and too narrow to type a name into.
    static func stack(_ views: [NSView]) -> NSView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = Tokens.Metric.rowGap
        for view in views {
            view.widthAnchor.constraint(equalToConstant: Tokens.Metric.urlPill.width).isActive = true
        }
        // Measured rather than counted: a popup and a field are not the same
        // height, and the old arithmetic assumed they were.
        stack.frame = NSRect(origin: .zero, size: stack.fittingSize)
        return stack
    }
}
