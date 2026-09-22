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
    static let title = String(localized: "Spaces")
    static let symbolName = "square.grid.2x2"
    static let keywords = ["profiles", "cookie jars", "workspaces", "gradients"]

    private let container = NSView()
    /// Internal rather than private only because Swift's `private` is
    /// file-scoped and the dialogs in `Spaces+Dialogs.swift` rebuild it.
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
        let add = newSpaceButton(session: session)
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
                    picture: ProfilePicture.image(from: space.imageData),
                    rows: rows.map(\.view),
                    onAppearance: { [weak self] anchor in
                        self?.editAppearance(of: space, from: anchor, session: session)
                    }
                ),
                rows: rows,
                inList: true
            )
        }

        body.card(nil, [clearProfileDataRow(spaces, session: session)])

        body.loose(SettingsRow.note(String(localized: """
        A Space owns its tabs and the cookies and logins those tabs use, so an account you sign into \
        in one Space is not signed in in another. Favorites belong to a Space for the same reason: a \
        tile is a logged-in app. Deleting a Space deletes its cookies with it, and nothing else is \
        signed out. Light and Dark stay a whole-app setting; a Space's gradient does not change it.
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
            pictureRow(space, session: session),
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

    private func deleteRow(_ space: Space, canDelete: Bool) -> (view: NSView, terms: [String]) {
        let title = String(localized: "Delete this Space")
        let row = SettingsRow.button(
            title,
            action: String(localized: "Delete…"),
            isDestructive: true,
            isEnabled: canDelete,
            disabledReason: canDelete ? nil : String(localized: "A window must always have at least one Space.")
        ) { [weak self] in self?.delete(space) }
        // "cookies" and "logins" are on this row because deleting a Space is
        // what deletes them now — the Profile row that used to answer for
        // those words is gone, and the vocabulary people search with is not.
        return (row, [title, space.name, "delete space", "remove space", "cookies", "logins"])
    }

    /// What the card's head says under the name. It does not repeat the name:
    /// the line above it is the name, and the fan-out only carried one because
    /// the name it carried was the Profile's. The picker in `Spaces+Dialogs`
    /// still needs one, which is why `fanOutLabel` keeps taking it.
    ///
    /// The same answer whether a session is running or not — a synthetic Space
    /// in a test has no Favorites, which is what the label should say.
    static func fanOut(_ space: Space, session: BrowserSession?) -> String {
        favoritesLabel(session?.favorites(inSpace: space.id).count ?? 0)
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
