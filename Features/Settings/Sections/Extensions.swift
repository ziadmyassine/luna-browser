//
//  Extensions.swift
//  Luna
//
//  docs/SETTINGS-SPEC.md §3.8: the extensions Luna has, where each one runs,
//  and the two ways to add another.
//
//  Adding comes first, as a field rather than a button that opens a dialog
//  with a field in it. Then the extensions, as small cards two to a row, each
//  headed by its own icon — `ExtensionCardView` has why they are not the
//  full-width cards of rows they started as.
//

import AppKit
import BrowserKit

@MainActor
final class ExtensionsSection: NSObject, SettingsSection {

    static let id = "extensions"
    static let title = String(localized: "Extensions")
    static let symbolName = ExtensionsSymbol.name
    static let keywords = ["add-ons", "plug-ins", "web extensions", "chrome web store", "pin", "toolbar"]

    private let container = NSView()
    private var body = SettingsBody()
    private var query = ""
    /// Kept across rebuilds: an install finishing rebuilds the pane, and the
    /// field it was typed into, with its "Added" line, has to survive that.
    private let addField = ExtensionAddField()
    /// The cards on screen, in order, so a change that keeps the same
    /// extensions updates them rather than building the pane again.
    private var shown: [(id: String, card: ExtensionCardView)] = []
    /// The Details popover, while one is open.
    private weak var details: NSPopover?

    var view: NSView { container }
    var searchIndex: [String] { body.searchIndex }

    func filter(_ query: String) {
        self.query = query
        body.filter(query)
    }

    override init() {
        super.init()
        container.translatesAutoresizingMaskIntoConstraints = false
        addField.onAdd = { [weak self] text in
            await ExtensionInstaller.install(webStoreLink: text, window: self?.container.window)
        }
        build()
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: ExtensionsCenter.didChange, object: nil)
    }

    /// Most changes are one extension turned on or off, pinned, or moved
    /// between Spaces — often by a switch on this pane that is still sliding.
    /// Only a different list of extensions builds the pane again.
    @objc private func refresh() {
        let installed = center.installed
        guard installed.map(\.id) == shown.map(\.id) else { return build() }
        for (info, entry) in zip(installed, shown) {
            let made = model(for: info)
            entry.card.update(made.model)
            body.setTerms(made.terms, for: entry.card)
        }
        body.filter(query)
    }

    func willAppear() { refresh() }

    private var center: ExtensionsCenter { .shared }

    private func build() {
        body = SettingsBody()
        shown = []
        addCard()
        let installed = center.installed
        if installed.isEmpty {
            body.card(ExtensionsEmptyCard(), rows: [(view: NSView(), terms: ["no extensions"])])
        } else {
            body.heading(Self.heading(installed.count), terms: [])
            let made = installed.map(model(for:))
            let cards = made.map { ExtensionCardView($0.model) }
            shown = zip(installed, cards).map { (id: $0.id, card: $1) }
            body.card(ExtensionCardGrid(cards: cards), rows: zip(cards, made).map { (view: $0, terms: $1.terms) })
        }
        body.filter(query)
        install(body.view)
    }

    private func install(_ stack: NSView) {
        for subview in container.subviews { subview.removeFromSuperview() }
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
    }

    private static func heading(_ count: Int) -> NSView {
        let label = NSTextField(labelWithString: count == 1
            ? String(localized: "1 extension")
            : String(localized: "\(count) extensions"))
        label.font = Tokens.TypeScale.settingsRow
        label.textColor = Tokens.Text.secondary
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    // MARK: - Adding

    private func addCard() {
        let choose = SettingsPushButton(title: String(localized: "Choose…"), isDestructive: false)
        let file = SettingsRow.accessory(
            String(localized: "From a folder or file"),
            subtitle: nil,
            accessory: choose
        )
        choose.onActivate = { [weak self, weak file] in
            Task { @MainActor in
                let outcome = await ExtensionInstaller.chooseFile(for: self?.container.window)
                if case let .failed(reason) = outcome { Self.alert(reason, on: file?.window) }
            }
        }
        body.card(String(localized: "Add an extension"), [
            (view: addField, terms: ["chrome web store", "install", "add", "link"]),
            (view: file, terms: ["folder", "file", "zip", "crx", "unpacked", "install", "add"])
        ])
    }

    /// A folder that is not an extension is rare enough, and far enough from
    /// any field, that a sheet is the right place to say so.
    private static func alert(_ reason: String, on window: NSWindow?) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Luna couldn’t add that extension")
        alert.informativeText = reason
        if let window { alert.beginSheetModal(for: window) } else { alert.runModal() }
    }

    // MARK: - One extension

    private func model(for info: ExtensionInfo) -> (model: ExtensionCardView.Model, terms: [String]) {
        let name = info.details?.name ?? info.id
        let here = center.session?.activeSpaceID
        let hereName = here.flatMap { center.session?.space($0)?.name } ?? String(localized: "this Space")
        let model = ExtensionCardView.Model(
            info: info,
            isPinned: center.isPinned(info.id),
            isOnHere: here.map(info.enabledSpaces.contains) ?? true,
            hereName: hereName,
            setOnHere: { isOn in
                guard let here else { return }
                Task { try? await ExtensionsCenter.shared.setEnabled(isOn, info.id, inSpace: here) }
            },
            blocker: ExtensionCompatibility.shortBlocker(for: info.id),
            showDetails: { [weak self] anchor in self?.showDetails(info.id, from: anchor) },
            moreMenu: { [weak self] in self?.moreMenu(for: info.id) ?? NSMenu() },
            setPinned: { ExtensionsCenter.shared.setPinned($0, info.id) }
        )
        let terms = [name, info.details?.summary ?? "", "pin", "space", "details", "remove", "reload"]
        return (model: model, terms: terms)
    }

    /// Read when it is asked for, not when the card was built: a card is
    /// updated in place, and the menu has to say what is true now.
    private func current(_ id: String) -> ExtensionInfo? {
        center.installed.first { $0.id == id }
    }

    /// Everything the card leaves out, in a popover under its Details button.
    private func showDetails(_ id: String, from anchor: NSView) {
        guard let info = current(id) else { return }
        details?.close()
        let view = ExtensionDetailsView(ExtensionDetailsView.Model(
            info: info,
            spaces: center.session?.spaces ?? [],
            blocker: ExtensionCompatibility.blocker(for: id),
            setOn: { isOn, space in
                Task { try? await ExtensionsCenter.shared.setEnabled(isOn, id, inSpace: space) }
            },
            actions: actions(for: info)
        ))
        let controller = NSViewController()
        controller.view = view
        let popover = NSPopover()
        popover.contentViewController = controller
        popover.behavior = .transient
        // Below, for `SpacesSection`'s reason: there is always pane under a
        // card's foot, and not always screen above it.
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        details = popover
    }

    private func actions(for info: ExtensionInfo) -> [ExtensionDetailsView.Action] {
        var actions: [ExtensionDetailsView.Action] = []
        switch info.source {
        case .webStore:
            actions.append(.init(title: String(localized: "Chrome Web Store"), isDestructive: false) { [weak self] in
                self?.details?.close()
                Self.openStorePage(info.id)
            })
        case .local:
            actions.append(.init(title: String(localized: "Reload"), isDestructive: false) {
                Task { await ExtensionsCenter.shared.reload(info.id) }
            })
        }
        actions.append(.init(title: String(localized: "Remove…"), isDestructive: true) { [weak self] in
            self?.details?.close()
            self?.remove(info.id)
        })
        return actions
    }

    /// The card's ⋯: everything the card has no button for, with Details at
    /// the head (`ExtensionCardView` puts it there).
    private func moreMenu(for id: String) -> NSMenu {
        let menu = NSMenu()
        guard let info = current(id) else { return menu }
        let spaces = center.session?.spaces ?? []
        if spaces.count > 1 {
            if info.enabledSpaces.count < spaces.count {
                menu.addItem(MenuAction.item(String(localized: "Turn On in Every Space")) {
                    Self.setEverywhere(true, id, spaces: spaces)
                })
            }
            if !info.enabledSpaces.isEmpty {
                menu.addItem(MenuAction.item(String(localized: "Turn Off in Every Space")) {
                    Self.setEverywhere(false, id, spaces: spaces)
                })
            }
            menu.addItem(.separator())
        }
        switch info.source {
        case .webStore:
            menu.addItem(MenuAction.item(String(localized: "Open in Chrome Web Store")) { Self.openStorePage(id) })
        case .local:
            menu.addItem(MenuAction.item(String(localized: "Reload from Its Folder")) {
                Task { await ExtensionsCenter.shared.reload(id) }
            })
        }
        menu.addItem(.separator())
        let name = info.details?.name ?? id
        menu.addItem(MenuAction.item(String(localized: "Remove “\(name)”…")) { [weak self] in self?.remove(id) })
        return menu
    }

    private static func setEverywhere(_ isOn: Bool, _ id: String, spaces: [Space]) {
        Task {
            for space in spaces { try? await ExtensionsCenter.shared.setEnabled(isOn, id, inSpace: space.id) }
        }
    }

    /// In a Luna tab: the listing is where its reviews, its changelog and its
    /// developer are, none of which the manifest carries.
    private static func openStorePage(_ id: String) {
        guard let url = URL(string: "https://chromewebstore.google.com/detail/\(id)") else { return }
        SettingsHost.open(url)
    }

    private func remove(_ id: String) {
        let name = current(id)?.details?.name ?? id
        guard SettingsHost.confirm(
            String(localized: "Remove “\(name)”?"),
            String(localized: "It is removed from every Space, with everything it stored."),
            action: String(localized: "Remove")
        ) else { return }
        Task { try? await ExtensionsCenter.shared.uninstall(id) }
    }
}

/// A menu item that runs a closure. The item keeps it alive through
/// `representedObject`, since an item's `target` is weak.
@MainActor
final class MenuAction: NSObject {
    private let run: () -> Void

    private init(_ run: @escaping () -> Void) { self.run = run }

    @objc private func fire() { run() }

    static func item(_ title: String, _ run: @escaping () -> Void) -> NSMenuItem {
        let action = MenuAction(run)
        let item = NSMenuItem(title: title, action: #selector(fire), keyEquivalent: "")
        item.target = action
        item.representedObject = action
        return item
    }
}
