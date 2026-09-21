//
//  Spaces.swift
//  Luna
//
//  docs/SETTINGS-SPEC.md §3.7, and SPACES-SPEC §6.2/§6.4.
//
//  Nothing here is dimmed for a missing method. `BrowserSession` carries
//  `renameSpace`, `reorderSpace`, `setIcon`, `setGradient`, `setProfile` and
//  `deleteSpace(_:policy:)`, so every row that used to name the call it was
//  waiting for is wired to it instead — the reason went, the row stayed (§30.4).
//
//  One card per Space, and the card is that Space's colour. The section was a
//  column of identical grey cards six rows deep, where finding "the blue one"
//  meant reading every heading — the one list in Luna where the twelve
//  gradients were not doing the work they exist for. `SpaceCardView` heads each
//  card with the Space's own pair at §8.2a's full intensity, its icon, its name
//  and §9's fan-out line.
//
//  Two of the six rows went into the header's corner button. Icon and gradient
//  were popups listing nouns — "Flask", "Mulberry" — for settings whose content
//  is a picture; `SpaceAppearanceView` shows both as grids of themselves.
//
//  The one thing this section says that no other browser's does is the fan-out:
//  Space → Profile is many-to-one, and nothing in Arc, Chrome or Firefox tells
//  you so. "Work profile · shared with 3 Spaces" is the whole answer to "why am
//  I still logged in over here" — the most-reported conceptual confusion in
//  reviews of Arc and the oldest open one in Firefox's containers (§9). It sits
//  on the card's head because it describes the Space, not a setting.
//
//  This section is the only one that rebuilds itself: creating, renaming,
//  reordering or deleting a Space changes what the rows say and how many there
//  are.
//

import AppKit
import BrowserKit
import WebKit

@MainActor
final class SpacesSection: SettingsSection {

    static let id = "spaces"
    static let title = String(localized: "Spaces & Profiles")
    static let symbolName = "square.grid.2x2"

    private let container = NSView()
    /// Internal rather than private only because Swift's `private` is
    /// file-scoped and §9's Profile cards are built in `Profiles+Rows.swift`.
    var body = SettingsBody()
    /// Retained for as long as it is open: `NSPopover` does not hold itself,
    /// and the section that built it is about to rebuild.
    private var appearance: NSPopover?

    var view: NSView { container }
    var searchIndex: [String] { body.searchIndex }
    func filter(_ query: String) { body.filter(query) }

    init() {
        container.translatesAutoresizingMaskIntoConstraints = false
        build()
    }

    // MARK: Building

    /// The list is the session's, not `UserDefaults`', and every other way of
    /// making a Space is outside this window — §6.1's swipe, its footer menu,
    /// and the Command Bar. See `SettingsSection.willAppear`.
    func willAppear() { build() }

    /// Internal, not private: the dialogs live in `Spaces+Dialogs.swift` and
    /// every one of them ends by rebuilding this section.
    func build() {
        let session = SettingsHost.session
        let spaces = session?.spaces ?? []
        appearance?.close()
        body = SettingsBody()

        // §6.1 above the cards it makes, not in a card of its own — see
        // `SettingsRow.heading`.
        let add = newSpaceButton(sharing: spaces, session: session)
        body.heading(
            SettingsRow.heading(String(localized: "Spaces"), accessory: add.view),
            terms: add.terms
        )

        for (index, space) in spaces.enumerated() {
            let rows = spaceRows(space, at: index, of: spaces, session: session)
            body.card(
                SpaceCardView(
                    space: space,
                    subtitle: Self.fanOut(space, session: session),
                    rows: rows.map(\.view),
                    onAppearance: { [weak self] anchor in
                        self?.editAppearance(of: space, from: anchor, session: session)
                    }
                ),
                rows: rows,
                inList: true
            )
        }

        profileCards(session)
        body.card(nil, [clearProfileDataRow(spaces, session: session)])

        body.loose(SettingsRow.note(String(localized: """
        A Space owns its tabs; a **profile** owns the cookies and logins those tabs use, and several \
        Spaces can share one. Favorites are per profile too, so a tile you add in one Space appears in \
        every Space on the same profile — which is also why deleting a Space only deletes its cookies \
        when no other Space is still using them. Light and Dark stay a whole-app setting; a Space's \
        gradient does not change it.
        """)), terms: ["profile", "cookies", "storage", "data store", "favorites", "shared"])

        install()
    }

    private func install() {
        for subview in container.subviews { subview.removeFromSuperview() }
        let stack = body.view
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
    }

    // MARK: One Space

    /// Internal, not private, so `SpacesSectionTests` can build the rows for a
    /// synthetic Space without a running session — which is the only way to
    /// assert that none of them is dimmed any more.
    ///
    /// Four rows, not six. §6.2's icon and gradient are on the card's
    /// corner button; see `appearanceChoices` for the pair, and
    /// `SpaceAppearanceView` for why a grid beat a popup for both.
    func spaceRows(
        _ space: Space,
        at index: Int,
        of spaces: [Space],
        session: BrowserSession?
    ) -> [(view: NSView, terms: [String])] {
        [
            nameRow(space, session: session),
            profileRow(space, session: session),
            positionRow(space, at: index, count: spaces.count, session: session),
            deleteRow(space, canDelete: spaces.count > 1)
        ]
    }

    /// §6.2's rename. Commits on Return and on losing focus, because
    /// `SettingsRow.text` sets `sendsActionOnEndEditing` — a name typed and then
    /// clicked away from is a name the user meant.
    private func nameRow(_ space: Space, session: BrowserSession?) -> (view: NSView, terms: [String]) {
        let title = String(localized: "Name")
        let row = SettingsRow.text(
            title, value: space.name, placeholder: space.name, limit: SpaceNameFormatter()
        ) { [weak self] typed in
            let name = typed.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, name != space.name, let session else { return }
            Task {
                do { try await session.renameSpace(space.id, to: name) } catch { NSApp.presentError(error) }
                self?.build()
            }
        }
        return (row, [title, space.name, "rename", "rename space"])
    }

    /// §6.2's reorder, as a position rather than a drag: a list of at most a
    /// handful of Spaces does not need a drag affordance to be reorderable, and
    /// every project researched shipped a persisted order with no way to change
    /// it at all.
    private func positionRow(
        _ space: Space,
        at index: Int,
        count: Int,
        session: BrowserSession?
    ) -> (view: NSView, terms: [String]) {
        let title = String(localized: "Position in the sidebar")
        let labels = (1...max(count, 1)).map(String.init)
        let row = SettingsRow.popup(
            title,
            subtitle: nil,
            options: labels,
            selected: index
        ) { [weak self] choice in
            guard let session, choice != index else { return }
            Task {
                do { try await session.reorderSpace(space.id, to: choice) } catch { NSApp.presentError(error) }
                self?.build()
            }
        }
        return (row, [title, space.name, "reorder", "order", "position", "move space"])
    }

    /// §6.1/§9's fan-out, and §3.3's Profile swap.
    ///
    /// The row itself is the swap; the label — the one Arc has nowhere — is
    /// on the card's head, where it describes the Space rather than pretending
    /// to be a caption on a popup.
    private func profileRow(_ space: Space, session: BrowserSession?) -> (view: NSView, terms: [String]) {
        let profiles = (session?.profiles.values.map { $0 } ?? []).sorted { $0.name < $1.name }
        let current = session?.profile(for: space)
        let title = String(localized: "Profile")
        let names = profiles.map(\.name)
        let row = SettingsRow.popup(
            title,
            subtitle: nil,
            options: names.isEmpty ? [current?.name ?? space.name] : names,
            selected: profiles.firstIndex { $0.id == space.profileID } ?? 0
        ) { [weak self] choice in
            guard let session, profiles.indices.contains(choice),
                  profiles[choice].id != space.profileID,
                  self?.confirmProfileSwap(space, to: profiles[choice]) == true else {
                self?.build()
                return
            }
            Task {
                do {
                    try await session.setProfile(profiles[choice].id, forSpace: space.id)
                } catch {
                    NSApp.presentError(error)
                }
                self?.build()
            }
        }
        return (row, [title, Self.fanOut(space, session: session), space.name, "profile", "shared", "cookies"])
    }

    private func deleteRow(_ space: Space, canDelete: Bool) -> (view: NSView, terms: [String]) {
        let title = String(localized: "Delete this Space")
        let row = SettingsRow.button(
            title,
            action: String(localized: "Delete…"),
            isDestructive: true,
            isEnabled: canDelete,
            disabledReason: canDelete ? nil : String(localized: "A window must always have at least one Space.")
        ) { [weak self] in self?.delete(space) }
        return (row, [title, space.name, "delete space", "remove space"])
    }

    /// §9's fan-out for one Space, with the same answer whether a session is
    /// running or not — a synthetic Space in a test is a Space on its own
    /// profile with no Favorites, which is exactly what the label should say.
    static func fanOut(_ space: Space, session: BrowserSession?) -> String {
        let current = session?.profile(for: space)
        return fanOutLabel(
            profileName: current?.name ?? space.name,
            spacesOnProfile: current.map { session?.spaces(onProfile: $0.id) ?? [] } ?? [space],
            favorites: current.map { session?.favorites(onProfile: $0.id).count ?? 0 } ?? 0
        )
    }

    // MARK: §6.2's appearance

    /// Every icon and every gradient a Space can take, for §2's search and for
    /// the test that proves neither left the app when they left the row list.
    static var appearanceChoices: (gradients: [String], icons: [String]) {
        (SpaceAppearanceView.gradientNames, symbols.map(\.label))
    }

    /// The corner button. A popover standing on the button that opened it —
    /// see `SpaceAppearanceView` for why it is not a pane or a sheet.
    ///
    /// Both writes rebuild the section, which throws this popover away with it;
    /// the grid marks the choice itself in the meantime so the click is never
    /// silent. The failures are presented rather than swallowed: unlike a
    /// colour chosen from the §3.5 dot's menu, a user in Settings is here to
    /// change this and is owed the reason it did not take.
    private func editAppearance(of space: Space, from anchor: NSView, session: BrowserSession?) {
        let content = SpaceAppearanceView(
            space: space,
            onGradient: { [weak self] gradient in
                guard let session, gradient != space.gradient else { return }
                Task {
                    do {
                        try await session.setGradient(gradient, forSpace: space.id)
                    } catch {
                        NSApp.presentError(error)
                    }
                    self?.build()
                }
            },
            onIcon: { [weak self] name in
                guard let session, name != space.symbolName else { return }
                Task {
                    do { try await session.setIcon(name, forSpace: space.id) } catch { NSApp.presentError(error) }
                    self?.build()
                }
            }
        )
        let controller = NSViewController()
        controller.view = content
        let popover = NSPopover()
        popover.contentViewController = controller
        popover.behavior = .transient
        // Below the button, not above it. `SpaceAppearanceButton` is not a
        // flipped view, so `.maxY` is its top edge — and a card at the head
        // of the pane put the grid off the top of the screen entirely, over
        // whatever was behind the window. There is always pane below a card
        // header; there is not always screen above one.
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        appearance = popover
    }
}
