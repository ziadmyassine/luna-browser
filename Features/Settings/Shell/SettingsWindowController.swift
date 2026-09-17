//
//  SettingsWindowController.swift
//  Luna
//
//  §1/§2's window: a separate `NSWindow`, 720 × 520, resizable, with the
//  section list on the left and an opaque detail pane on the right.
//
//  **A window, not a sheet and not a `luna://` page** (§1's three decisions): a
//  sheet blocks the window you are trying to preview a setting against, and an
//  internal page cannot host `NSGlassEffectView`, so it could not look like the
//  rest of Luna.
//
//  **`NSWindow.minSize` is not used.** It is documented as ignored once the
//  content view uses Auto Layout — verbatim in `NSWindow.h`, and the browser
//  window learned it in M0 — so §1's 640 × 420 floor is a pair of
//  `greaterThanOrEqualToConstant`s on the root view instead.
//
//  **Every command here arrives through `MainMenu`.** Luna installs no
//  `NSEvent` monitor and overrides no `performKeyEquivalent` (§22.5); the four
//  `@objc` actions at the bottom are ordinary nil-targeted menu actions that
//  reach this controller because an `NSWindowController` sits in its key
//  window's responder chain. That is measured, not assumed — see the comment
//  on `switchToSpace(_:)`.
//

import AppKit

/// §2's match rule, in one place.
///
/// Deliberately the *same* rule agents B and C implement in their own
/// `filter(_:)` — one trimmed, lowercased needle, matched as a substring. A
/// window that dimmed a section on a different rule than the one that hides its
/// rows would show a bright section with nothing in it.
enum SettingsSearch {

    static func normalise(_ query: String) -> String {
        query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// An empty query matches everything — that is how "clear the search"
    /// restores the window.
    static func matches(_ query: String, in terms: [String]) -> Bool {
        let needle = normalise(query)
        guard !needle.isEmpty else { return true }
        return terms.contains { $0.lowercased().contains(needle) }
    }
}

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate, NSSearchFieldDelegate {

    private let sections: [any SettingsSection]
    private let list: SettingsSectionList
    private let detail = SettingsDetailPane()
    private let search = NSSearchField()
    private var selected = 0

    convenience init() {
        // Built up front, all nine: §2's search has to know what is inside a
        // section the user has not opened, and `searchIndex` is an instance
        // property. Nine stacks of AppKit controls cost a few milliseconds
        // once, and every later query is then a string comparison.
        let sections = SettingsSectionRegistry.all.map { $0.init() }
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: SettingsMetrics.contentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        self.init(sections: sections, window: window)
    }

    private init(sections: [any SettingsSection], window: NSWindow) {
        self.sections = sections
        list = SettingsSectionList(
            titles: SettingsSectionRegistry.all.map { $0.title },
            symbols: SettingsSectionRegistry.all.map { $0.symbolName }
        )
        super.init(window: window)

        window.title = String(localized: "Luna Settings")
        // **The window has to be non-opaque or the glass column dies.**
        // `NSGlassEffectView` composites what is behind the *window*, so on an
        // opaque one the section list has nothing to sample and reads as a flat
        // plate. Measured by Martin on his own first Settings window; the
        // detail pane still paints `Surface.base` over its own half, so only
        // the column is see-through.
        window.isOpaque = false
        window.backgroundColor = .clear
        // §1: the standard traffic lights, with no custom layout manager. This
        // window is a form; the browser window is the one that is a shape.
        window.isReleasedWhenClosed = false
        // §1: "not restorable into a browser window". Without this, AppKit
        // encodes the window into the app's saved state and reopens it on
        // launch — with `⌘,` as the only way in, that is never what was meant.
        window.isRestorable = false
        window.delegate = self
        window.center()
        windowFrameAutosaveName = "LunaSettingsWindow"

        window.contentView = buildContent()
        show(SettingsSectionRegistry.index(ofID: SettingsDefaults.lastSection), animated: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    // MARK: - Presentation

    /// `⌘,`: opens the window, or brings the one that is already open forward.
    /// There is exactly one, for the life of the app.
    func present() {
        let wasVisible = window?.isVisible ?? false
        showWindow(self)
        window?.makeKeyAndOrderFront(self)
        NSApp.activate()
        // Opening animates; focusing a window that is already up does not —
        // re-playing an entrance on a `⌘,` that only meant "come forward" is a
        // flinch, not a transition.
        if !wasVisible { animateIn() }
    }

    /// §5's `commandBarIn`: scale 0.96 → 1.0 plus a fade, the same entrance the
    /// Command Bar uses. Reduce Motion degrades it with no second code path —
    /// `springAnimation` returns nil and `Motion.animate` runs at zero duration.
    private func animateIn() {
        guard let window, let root = window.contentView else { return }
        // Lay out before animating, the same order `CommandBarPanel` uses: a
        // scale animation applied to a tree that has not had its first pass
        // scales whatever geometry it happens to have.
        root.layoutSubtreeIfNeeded()
        root.wantsLayer = true
        guard let scale = Tokens.Motion.commandBarIn.springAnimation(keyPath: "transform.scale") else {
            window.alphaValue = 1
            return
        }
        scale.fromValue = 0.96
        scale.toValue = 1.0
        root.layer?.add(scale, forKey: "commandBarIn")
        window.alphaValue = 0
        Tokens.Motion.animate(Tokens.Motion.commandBarIn) { _ in
            window.animator().alphaValue = 1
        }
    }

    // MARK: - Content

    private func buildContent() -> NSView {
        let root = NSView()
        let column = buildColumn()
        column.translatesAutoresizingMaskIntoConstraints = false
        detail.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(column)
        root.addSubview(detail)
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            column.topAnchor.constraint(equalTo: root.topAnchor),
            column.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            // §1: fixed, and deliberately not `sidebarWidth` — that one is
            // user-dragged and this one is not.
            column.widthAnchor.constraint(equalToConstant: SettingsMetrics.listWidth),

            detail.leadingAnchor.constraint(equalTo: column.trailingAnchor),
            detail.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            detail.topAnchor.constraint(equalTo: root.topAnchor),
            detail.bottomAnchor.constraint(equalTo: root.bottomAnchor),

            // §1's floor. `NSWindow.minSize` is ignored under Auto Layout.
            root.widthAnchor.constraint(greaterThanOrEqualToConstant: SettingsMetrics.minWidth),
            root.heightAnchor.constraint(greaterThanOrEqualToConstant: SettingsMetrics.minHeight)
        ])
        return root
    }

    /// The left column: §2's search field over §2's section list, on the same
    /// `.sidebar` glass as the browser's sidebar.
    private func buildColumn() -> NSView {
        let column = NSView()
        Glass.apply(.sidebar, to: column)

        search.placeholderString = String(localized: "Search settings")
        search.delegate = self
        search.sendsWholeSearchString = false
        search.setAccessibilityLabel(String(localized: "Search settings"))
        search.translatesAutoresizingMaskIntoConstraints = false
        list.onSelect = { [weak self] index in self?.show(index, animated: true) }
        list.translatesAutoresizingMaskIntoConstraints = false

        column.addSubview(search)
        column.addSubview(list)
        let inset = Tokens.Metric.rowInset
        NSLayoutConstraint.activate([
            // Below the traffic lights, which this window draws in the standard
            // place — the title bar is real here.
            search.topAnchor.constraint(equalTo: column.topAnchor, constant: SettingsMetrics.paneInset),
            search.leadingAnchor.constraint(equalTo: column.leadingAnchor, constant: inset),
            search.trailingAnchor.constraint(equalTo: column.trailingAnchor, constant: -inset),
            search.heightAnchor.constraint(equalToConstant: SettingsMetrics.searchHeight),

            list.topAnchor.constraint(equalTo: search.bottomAnchor, constant: SettingsMetrics.controlRowGap),
            list.leadingAnchor.constraint(equalTo: column.leadingAnchor),
            list.trailingAnchor.constraint(equalTo: column.trailingAnchor),
            list.bottomAnchor.constraint(lessThanOrEqualTo: column.bottomAnchor, constant: -SettingsMetrics.paneInset)
        ])
        return column
    }

    // MARK: - Sections

    /// §2: exactly one section selected, always, and the choice survives a
    /// relaunch in `settings.lastSection`.
    private func show(_ index: Int, animated: Bool) {
        guard sections.indices.contains(index) else { return }
        selected = index
        list.select(index)
        let section = sections[index]
        detail.show(section.view, title: type(of: section).title, animated: animated)
        detail.highlight(SettingsSearch.normalise(search.stringValue))
        detail.setEmpty(emptyMessage(for: section))
        SettingsDefaults.lastSection = type(of: section).id
    }

    // MARK: - §2's search

    func controlTextDidChange(_ obj: Notification) {
        applySearch()
    }

    /// §2: the search filters **controls**, not sections. Every section is
    /// filtered, not only the visible one, so switching sections with a live
    /// query lands on an already-filtered pane; a section with no matches is
    /// dimmed in the list rather than removed, because removing rows makes the
    /// list jump under the pointer.
    private func applySearch() {
        let query = SettingsSearch.normalise(search.stringValue)
        for section in sections { section.filter(query) }
        list.setDimmed(sections.map { !SettingsSearch.matches(query, in: $0.searchIndex) })
        detail.highlight(query)
        detail.setEmpty(emptyMessage(for: sections[selected]))
        detail.staggerVisibleRows()
    }

    private func emptyMessage(for section: any SettingsSection) -> String? {
        let query = SettingsSearch.normalise(search.stringValue)
        guard !query.isEmpty, !SettingsSearch.matches(query, in: section.searchIndex) else { return nil }
        return String(localized: "Nothing in \(type(of: section).title) matches “\(search.stringValue)”.")
    }

    // MARK: - §22.5's commands, all of them menu items

    /// `⌘F`. Declared in `MainMenu` under Window ▸ Settings; nil-targeted, so it
    /// is dimmed everywhere except here.
    @objc func focusSettingsSearch(_ sender: Any?) {
        window?.makeFirstResponder(search)
    }

    /// `⌘W`. The File menu's "Close Tab" is the first `⌘W` in menu order and
    /// AppKit stops at the first match, so the only way this window closes on
    /// `⌘W` is by claiming that selector while it is key. Implementing it here
    /// rather than branching inside `AppDelegate.closeTab` keeps the browser
    /// command exactly as it was.
    @objc func closeTab(_ sender: Any?) {
        close()
    }

    /// `⌘1…⌘9`, arriving by the Spaces menu.
    ///
    /// **Measured, and it is the reason this method exists at all.** AppKit's
    /// key-equivalent search stops at the *first* item whose key equivalent
    /// matches, in menu order, and swallows the event there whether that item
    /// is enabled, disabled, or has no target at all (probed against macOS 26.5:
    /// a disabled first match returns `true` from `performKeyEquivalent` and the
    /// enabled second match never runs). The Spaces menu is built before the
    /// Window menu and already owns `⌘1…⌘N`, so `⌘1` inside Settings can only be
    /// reached by claiming `switchToSpace(_:)` — which is safe, because it only
    /// resolves here while this window is key.
    @objc func switchToSpace(_ sender: Any?) {
        goToSettingsSection(sender)
    }

    /// `⌘(N+1)…⌘9` — the section items the Spaces menu does not shadow — and
    /// every click on Window ▸ Settings ▸ <section>.
    @objc func goToSettingsSection(_ sender: Any?) {
        guard let item = sender as? NSMenuItem else { return }
        show(item.tag, animated: true)
    }
}
