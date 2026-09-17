//
//  Spaces.swift
//  Luna
//
//  docs/SETTINGS-SPEC.md §3.7.
//
//  What is wired: New Space and Delete Space, because `BrowserSession` has
//  `createSpace(name:)` and `deleteSpace(_:)` and both already do the right
//  thing. What is dimmed: rename, reorder, and changing a Space's profile.
//  `BrowserSession.spaces` is `private(set)` and carries no rename, reorder or
//  re-profile call, so the only way to write one from here would be straight
//  into `BrowserStore` — which persists a name the running window never shows.
//  A row that appears to work and does not is worse than a dimmed one (§30.4).
//
//  This section is the only one that rebuilds itself: creating or deleting a
//  Space changes how many rows there are.
//

import AppKit
import BrowserKit

@MainActor
final class SpacesSection: SettingsSection {

    static let id = "spaces"
    static let title = String(localized: "Spaces & Profiles")
    static let symbolName = "square.grid.2x2"

    private let container = NSView()
    private var body = SettingsBody()

    var view: NSView { container }
    var searchIndex: [String] { body.searchIndex }
    func filter(_ query: String) { body.filter(query) }

    init() {
        container.translatesAutoresizingMaskIntoConstraints = false
        build()
    }

    // MARK: Building

    private func build() {
        let session = SettingsHost.session
        let spaces = session?.spaces ?? []
        body = SettingsBody()

        var spaceRows = spaces.map { spaceRow($0, canDelete: spaces.count > 1) }
        spaceRows.append(newSpaceRow())
        spaceRows.append(renameRow())
        body.card(String(localized: "Spaces"), spaceRows)

        var profileRows = spaces.map { profileRow(for: $0, session: session) }
        profileRows.append(deleteProfileDataRow())
        body.card(String(localized: "Profiles"), profileRows)

        body.loose(SettingsRow.note(String(localized: """
        Each Space keeps its own cookies and logins in its own storage (§5.1). Deleting a \
        Space deletes that storage with it — WebKit refuses to remove a store while any tab \
        is still using it, so Luna closes every tab in the Space first and then checks the \
        store really is gone rather than trusting a silent success.
        """)), terms: ["profile", "cookies", "storage", "data store"])

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

    // MARK: Spaces

    private func spaceRow(_ space: Space, canDelete: Bool) -> (view: NSView, terms: [String]) {
        let row = SettingsRow.button(
            space.name,
            action: String(localized: "Delete…"),
            isDestructive: true,
            isEnabled: canDelete,
            disabledReason: canDelete ? nil : String(localized: "A window must always have at least one Space.")
        ) { [weak self] in self?.delete(space) }
        return (row, [space.name, "space", "delete space"])
    }

    private func newSpaceRow() -> (view: NSView, terms: [String]) {
        let title = String(localized: "New Space")
        let row = SettingsRow.button(title, action: title) { [weak self] in self?.createSpace() }
        return (row, [title, "add space", "create space"])
    }

    private func renameRow() -> (view: NSView, terms: [String]) {
        let title = String(localized: "Rename or reorder a Space")
        let row = SettingsRow.button(
            title,
            action: String(localized: "Rename…"),
            isEnabled: false,
            disabledReason: String(localized: "BrowserSession can create and delete Spaces, but cannot yet rename or reorder one.")
        ) {}
        return (row, [title, "rename", "reorder"])
    }

    /// Named at creation on purpose: there is no rename yet, so the name typed
    /// here is the name the Space keeps. `BrowserCommands`' `⌘⇧N` names it
    /// "New Space" for the same reason and could call this instead.
    private func createSpace() {
        guard let session = SettingsHost.session,
              let name = SettingsHost.ask(
                  String(localized: "Name the new Space"),
                  String(localized: "Its tabs and its logins stay separate from every other Space."),
                  action: String(localized: "Create"),
                  placeholder: String(localized: "New Space")
              )
        else { return }
        Task {
            do { try await session.createSpace(name: name) } catch { NSApp.presentError(error) }
            build()
        }
    }

    private func delete(_ space: Space) {
        guard let session = SettingsHost.session,
              SettingsHost.confirm(
                  String(localized: "Delete the Space “\(space.name)”?"),
                  String(localized: """
                  Its tabs close and its cookies, logins and caches are deleted. This cannot be undone.
                  """),
                  action: String(localized: "Delete")
              )
        else { return }
        Task {
            do { try await session.deleteSpace(space.id) } catch { NSApp.presentError(error) }
            build()
        }
    }

    // MARK: Profiles

    /// §5.5's gotcha is why this is dimmed rather than missing: a
    /// `WKWebsiteDataStore` created with an identifier can never adopt the
    /// default store's data, so a Space's profile cannot be swapped after the
    /// fact without silently orphaning a cookie jar in
    /// `~/Library/WebKit/WebsiteDataStore/`.
    private func profileRow(for space: Space, session: BrowserSession?) -> (view: NSView, terms: [String]) {
        let names = (session?.profiles.values.map(\.name) ?? []).sorted()
        let current = session?.profile(for: space)?.name ?? space.name
        let title = String(localized: "Profile for \(space.name)")
        let row = SettingsRow.popup(
            title,
            subtitle: nil,
            options: names.isEmpty ? [current] : names,
            selected: names.firstIndex(of: current) ?? 0,
            isEnabled: false,
            disabledReason: String(localized: "A Space's profile is fixed when the Space is created (§5.5)."),
            onChange: { _ in }
        )
        return (row, [title, current, "profile"])
    }

    private func deleteProfileDataRow() -> (view: NSView, terms: [String]) {
        let title = String(localized: "Delete a profile's data")
        let row = SettingsRow.button(
            title,
            action: String(localized: "Delete…"),
            isDestructive: true,
            isEnabled: false,
            disabledReason: String(localized: "BrowserStore has no delete(profileID:), so this would leave a Space pointing at nothing.")
        ) {}
        return (row, [title, "clear profile", "website data"])
    }
}
