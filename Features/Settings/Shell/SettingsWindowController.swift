//
//  SettingsWindowController.swift
//  Luna
//
//  §1/§2's window: an `NSWindow`, 720 × 520, resizable, with the section list
//  on the left and an opaque detail pane on the right.
//
//  A window, not a sheet and not a `luna://` page (§1's three decisions): a
//  sheet blocks the window you are trying to preview a setting against, and an
//  internal page cannot host `NSGlassEffectView`, so it could not look like the
//  rest of Luna. But not a free-standing one either: it is a child of the
//  browser window it was opened from, so it opens over that window, travels
//  with it, and goes into its fullscreen Space rather than onto the desktop.
//
//  `NSWindow.minSize` is not used. It is documented as ignored once the
//  content view uses Auto Layout — verbatim in `NSWindow.h`, and the browser
//  window learned it in M0 — so §1's 640 × 480 floor is a pair of
//  `greaterThanOrEqualToConstant`s on the root view instead.
//
//  Every command here arrives through `MainMenu`. Luna installs no `NSEvent`
//  monitor and overrides no `performKeyEquivalent` (§22.5); the `@objc` actions
//  at the bottom are ordinary nil-targeted menu actions that reach this
//  controller because an `NSWindowController` sits in its key window's
//  responder chain.
//
//  It used to claim `switchToSpace(_:)` as well, to take `⌘1…⌘9` back from the
//  Spaces menu. SPACES-SPEC §13.2 moved Spaces to `⌃1…⌃9`, at which point that
//  shim made `⌃1` navigate sections instead of switching Space whenever this
//  window was key. `⌘1…⌘9` now arrives from `AppDelegate.goToSidebarItem(_:)`.
//

import AppKit

/// §2's match rule, in one place — the same one every section's `filter(_:)`
/// uses. A window that dimmed a section on a different rule than the one that
/// hides its rows would show a bright section with nothing in it.
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
final class SettingsWindowController: NSWindowController, NSWindowDelegate {

    private let sections: [any SettingsSection]
    private let list: SettingsSectionList
    private let detail = SettingsDetailPane()
    private let search = SettingsSearchField()
    private var selected = 0
    /// §1's back and forward: the order the sections were actually visited in,
    /// which the list cannot show. `cursor` is where in it we are standing, so
    /// going back and then picking a new section truncates the rest — the same
    /// rule a browser's own history has.
    private var visited: [Int] = []
    private var cursor = 0

    /// Held for its lifetime: it re-applies the placement AppKit undoes on
    /// every resize, which is the whole reason the class exists.
    private var lights: TrafficLightLayoutManager?
    /// Observes the browser window this one is attached to, so that closing it
    /// takes Settings with it rather than leaving it standing over nothing.
    private var hostClosing: NSObjectProtocol?

    convenience init() {
        // All nine up front: §2's search has to know what is inside a section
        // the user has not opened, and every later query is then a string
        // comparison.
        let sections = SettingsSectionRegistry.all.map { $0.init() }
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: SettingsMetrics.contentSize),
            // `.fullSizeContentView`, so the glass column runs the window's full
            // height and the traffic lights sit on it.
            // Not `.miniaturizable`: it goes to the Dock with the browser
            // window it belongs to, and a yellow light that sent it there on
            // its own would be the one way to pull the two apart.
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
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
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        // Non-opaque, or the glass column dies. `NSGlassEffectView`
        // composites what is behind the window, so on an opaque one the
        // section list has nothing to sample and reads as a flat plate. The
        // detail pane paints `Surface.base` over its own half, so only the
        // column is see-through.
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isReleasedWhenClosed = false
        // §1: not restorable. Without this AppKit reopens it on launch, which
        // with `⌘,` as the only way in is never what was meant.
        window.isRestorable = false
        window.delegate = self
        window.center()
        windowFrameAutosaveName = "LunaSettingsWindow"

        window.contentView = buildContent()
        // §7.7: the one owner of a window button's frame, here so Settings'
        // lights sit at the same inset as the sidebar's rather than AppKit's.
        lights = TrafficLightLayoutManager(pinningLightsIn: window)
        // §2's search is where a `⌘,` lands: the alternative is AppKit picking
        // the first thing that accepts first responder, which is a disabled
        // row (§4 keeps those in the key loop).
        window.initialFirstResponder = search
        show(SettingsSectionRegistry.index(ofID: SettingsDefaults.lastSection), animated: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    // MARK: - Presentation

    /// `⌘,`: opens the window, or brings the one that is already open forward.
    /// There is exactly one, for the life of the app.
    ///
    /// - Parameters:
    ///   - section: a `SettingsSection.id` to land on, for the callers that are
    ///     asking a specific question — §3.2's site menu sends "Advanced
    ///     Settings" here. nil keeps whichever section the user was last on.
    ///   - host: the browser window it was asked for from. nil when there is
    ///     none, and then it stands on its own in the middle of the screen.
    func present(section: String? = nil, over host: NSWindow? = nil) {
        let wasVisible = window?.isVisible ?? false
        if let section, let index = sections.firstIndex(where: { type(of: $0).id == section }) {
            show(index, animated: wasVisible)
        }
        let placed = attach(to: host, wasVisible: wasVisible)
        showWindow(self)
        window?.makeKeyAndOrderFront(self)
        // Again, because the first time did not stick: a window coming on
        // screen through its controller is put where AppKit's cascade wants it,
        // measured at the middle of the screen, over the frame set a line ago.
        if let placed { window?.setFrame(placed, display: false) }
        NSApp.activate()
        // Opening animates; focusing a window that is already up does not —
        // re-playing an entrance on a `⌘,` that only meant "come forward" is a
        // flinch, not a transition.
        if !wasVisible { animateIn() }
    }

    /// Makes Settings a child of `host`, centred over it.
    ///
    /// A child window moves when its parent is dragged, stays in front of it
    /// when the parent is clicked, and follows it into and out of its
    /// fullscreen Space — which a free-standing window does not: from a
    /// fullscreen browser it opened on the desktop, a swipe away from the page
    /// it was changing.
    ///
    /// Re-centred only when it arrives: a `⌘,` over the window it is already on
    /// means "come forward", and leaves it wherever it was dragged to.
    ///
    /// - Returns: the frame it was given, for `present` to give it again once it
    ///   is on screen. nil when it stays where it is, or has no window to sit on.
    private func attach(to host: NSWindow?, wasVisible: Bool) -> NSRect? {
        guard let window else { return nil }
        let arriving = !wasVisible || window.parent !== host
        if window.parent !== host { detach() }
        guard let host else {
            if arriving { window.center() }
            return nil
        }
        // Before it is ordered in as well as after: the link to the host has to
        // exist by then, or a fullscreen host's Space is left for the desktop.
        let placed = arriving ? Self.frame(for: window.frame.size, over: host.frame) : nil
        if let placed { window.setFrame(placed, display: false) }
        if window.parent !== host {
            host.addChildWindow(window, ordered: .above)
            hostClosing = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: host,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.close() }
            }
        }
        return placed
    }

    private func detach() {
        if let hostClosing { NotificationCenter.default.removeObserver(hostClosing) }
        hostClosing = nil
        guard let window, let parent = window.parent else { return }
        parent.removeChildWindow(window)
    }

    /// Centred over `host`, and no bigger than it — down to §1's floor, which
    /// wins over a browser window smaller than that.
    nonisolated static func frame(for size: CGSize, over host: NSRect) -> NSRect {
        let width = max(min(size.width, host.width), SettingsMetrics.minWidth)
        let height = max(min(size.height, host.height), SettingsMetrics.minHeight)
        return NSRect(
            x: (host.midX - width / 2).rounded(),
            y: (host.midY - height / 2).rounded(),
            width: width,
            height: height
        )
    }

    /// Closed on its own, it lets go of the window it was on, so the next `⌘,`
    /// from anywhere arrives fresh.
    func windowWillClose(_ notification: Notification) {
        detach()
    }

    /// §5's `commandBarIn`: scale 0.96 → 1.0 plus a fade, the same entrance the
    /// Command Bar uses. Reduce Motion degrades it with no second code path.
    private func animateIn() {
        guard let window, let root = window.contentView else { return }
        // Lay out first: a scale applied to a tree that has not had its first
        // pass scales whatever geometry it happens to have.
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
        // The same shape the browser window is cut to. A Luna window has one
        // radius, and Settings was wearing the system's instead.
        let root = WindowRootView()
        let column = buildColumn()
        column.translatesAutoresizingMaskIntoConstraints = false
        detail.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(column)
        root.addSubview(detail)
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            column.topAnchor.constraint(equalTo: root.topAnchor),
            column.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            column.widthAnchor.constraint(equalToConstant: SettingsMetrics.listWidth),

            detail.leadingAnchor.constraint(equalTo: column.trailingAnchor),
            detail.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            detail.topAnchor.constraint(equalTo: root.topAnchor),
            detail.bottomAnchor.constraint(equalTo: root.bottomAnchor),

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

        search.onChange = { [weak self] _ in self?.applySearch() }
        search.translatesAutoresizingMaskIntoConstraints = false
        list.onSelect = { [weak self] index in self?.show(index, animated: true) }
        detail.nav.onBack = { [weak self] in self?.step(-1) }
        detail.nav.onForward = { [weak self] in self?.step(1) }
        list.translatesAutoresizingMaskIntoConstraints = false

        column.addSubview(search)
        column.addSubview(list)
        let inset = Tokens.Metric.rowInset
        NSLayoutConstraint.activate([
            // Clear of the traffic lights, which sit on this column now.
            search.topAnchor.constraint(
                equalTo: column.topAnchor,
                constant: Tokens.Metric.trafficLightInset + SettingsMetrics.groupGap
            ),
            search.leadingAnchor.constraint(equalTo: column.leadingAnchor, constant: inset),
            search.trailingAnchor.constraint(equalTo: column.trailingAnchor, constant: -inset),
            search.heightAnchor.constraint(equalToConstant: SettingsMetrics.searchHeight),

            list.topAnchor.constraint(equalTo: search.bottomAnchor, constant: SettingsMetrics.controlRowGap),
            list.leadingAnchor.constraint(equalTo: column.leadingAnchor),
            list.trailingAnchor.constraint(equalTo: column.trailingAnchor)
        ])
        // The list stands at its own height — twelve rows at the sidebar's pitch —
        // and keeps `paneInset` off the bottom of the column if it can.
        // Not required: `settingsMinHeight` is sized so it always can, and a
        // required constraint here would be one AppKit breaks, with a console
        // full of it, the moment anything else moved.
        let floor = list.bottomAnchor.constraint(
            lessThanOrEqualTo: column.bottomAnchor,
            constant: -SettingsMetrics.paneInset
        )
        floor.priority = .defaultHigh
        floor.isActive = true
        return column
    }

    // MARK: - Sections

    /// §2: exactly one section selected, always, and the choice survives a
    /// relaunch in `settings.lastSection`.
    private func show(_ index: Int, animated: Bool) {
        guard sections.indices.contains(index) else { return }
        record(index)
        present(index, animated: animated)
    }

    /// Pushes `index` onto the visited list, dropping whatever was ahead of the
    /// cursor. Re-picking the section you are already on is not a visit.
    private func record(_ index: Int) {
        guard visited.isEmpty || visited[cursor] != index else { return }
        if !visited.isEmpty { visited.removeSubrange((cursor + 1)...) }
        visited.append(index)
        cursor = visited.count - 1
    }

    /// Moves the cursor without recording anything — `offset` is -1 or +1.
    private func step(_ offset: Int) {
        let next = cursor + offset
        guard visited.indices.contains(next) else { return }
        cursor = next
        present(visited[next], animated: true)
    }

    private func present(_ index: Int, animated: Bool) {
        guard sections.indices.contains(index) else { return }
        selected = index
        detail.nav.update(canGoBack: cursor > 0, canGoForward: cursor + 1 < visited.count)
        list.select(index)
        let section = sections[index]
        section.willAppear()
        detail.show(section.view, title: type(of: section).title, animated: animated)
        detail.highlight(SettingsSearch.normalise(search.stringValue))
        detail.setEmpty(emptyMessage(for: section))
        SettingsDefaults.lastSection = type(of: section).id
    }

    // MARK: - §2's search

    /// §2: the search filters controls, not sections, and filters every
    /// section rather than only the visible one — so switching sections with a
    /// live query lands on an already-filtered pane.
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

    /// `⌘W`. "Close Tab" is the first `⌘W` in menu order and AppKit stops at
    /// the first match, so the only way this window closes on `⌘W` is to claim
    /// that selector while it is key.
    @objc func closeTab(_ sender: Any?) {
        close()
    }

    /// Every click on Window ▸ Settings ▸ <section>, and `⌘1…⌘9` — which
    /// arrives from `AppDelegate.goToSidebarItem(_:)`, not from an item of this
    /// menu's own. See `MainMenu.setSidebarItems`: AppKit erases a duplicate
    /// ⌘-number rather than shadowing it, so only one family in the whole bar
    /// can carry one and View ▸ Sidebar Items is it.
    @objc func goToSettingsSection(_ sender: Any?) {
        guard let item = sender as? NSMenuItem else { return }
        show(item.tag, animated: true)
    }
}
