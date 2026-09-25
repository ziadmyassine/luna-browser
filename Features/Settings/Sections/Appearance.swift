//
//  Appearance.swift
//  Luna
//
//  §23.1 §3.2, and the §7 glass row it exists for.
//
//  The preview tile is the point of this section. On the machine §7 was
//  measured on — 1920 × 1080 at one point to one physical pixel — the
//  difference between `.clear` and tinted `.regular` is the difference between
//  chrome that reads as glass and chrome that reads as a smear. A setting you
//  can only judge by closing the window is a setting nobody tunes, so the tile
//  is rebuilt from `Glass.previewTile(size:optimised:)` on the same runloop
//  turn as the segment change.
//
//  Favicons are no longer a setting. §3.2 listed a switch; the sidebar has
//  drawn them since M1 and nobody turns them off. A preference whose only
//  honest default is "on" is one more row to read past.
//
//  Two rows answer only to the sidebar layout — where its search bar sits and
//  which side it stands on — and are removed, not dimmed, under the top bar,
//  whose tabs always start at its leading edge.
//

import AppKit

@MainActor
final class AppearanceSection: NSObject, SettingsSection {

    static let id = "appearance"
    static let title = "Appearance"
    static let symbolName = "circle.lefthalf.filled"
    static let keywords = ["theme", "dark mode", "light mode", "glass", "transparency", "chrome layout", "corners"]

    // MARK: Keys and typed accessors

    /// §3.2's theme. `auto` is `NSApp.appearance = nil`, which is what makes
    /// Luna follow System Settings live; the other two pin it.
    enum Theme: String, Sendable, CaseIterable {
        case auto
        case light
        case dark

        var title: String {
            switch self {
            case .auto: "Auto"
            case .light: "Light"
            case .dark: "Dark"
            }
        }

        var appearance: NSAppearance? {
            switch self {
            case .auto: nil
            case .light: NSAppearance(named: .aqua)
            case .dark: NSAppearance(named: .darkAqua)
            }
        }
    }

    static let themeKey = "appearance.theme"

    static var theme: Theme {
        UserDefaults.standard.string(forKey: themeKey).flatMap(Theme.init(rawValue:)) ?? .auto
    }

    /// Reads `appearance.theme` back onto the app.
    ///
    /// `NSApp.appearance` is process-wide and starts at nil, so a stored Light
    /// or Dark choice is lost unless something re-applies it — and opening the
    /// Settings window must not be the prerequisite for a theme. One line in
    /// `applicationDidFinishLaunching`.
    ///
    /// The glass setting needs no equivalent: `Glass.optimisation` loads itself
    /// from `appearance.glassOptimisation` on first access (agent D), so this
    /// section only ever assigns it.
    static func applyStoredTheme() {
        NSApp.appearance = theme.appearance
    }

    // MARK: The §7 preview tile

    /// §3.2: "a 160 × 72 sample of the real material".
    ///
    /// The one length in B's four sections that is not a `Tokens.Metric`.
    /// It is a §23.1 number with no row in §1's table and `Design/` is agent
    /// D's; the report asks for `Tokens.Metric.glassPreviewTile` so this can
    /// become a reference. Nothing else here writes a literal length.
    static let previewTileSize = NSSize(width: 160, height: 72)

    // MARK: Section

    private let body = SettingsBody()
    /// §3.2b's row, held so the layout row above can take it away — see
    /// `refreshSearchBarRow`.
    private var searchBarHost: NSView?
    /// Holds whichever tile is current. Rebuilt, not mutated: the material is
    /// chosen when the glass view is constructed.
    private let tileHost = NSView()
    /// The sidebar-side row, held for the same reason as `searchBarHost`.
    private var sideHost: NSView?

    var view: NSView { body.view }
    var searchIndex: [String] { body.searchIndex }
    func filter(_ query: String) { body.filter(query) }

    override init() {
        super.init()
        tileHost.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            tileHost.widthAnchor.constraint(equalToConstant: Self.previewTileSize.width),
            tileHost.heightAnchor.constraint(equalToConstant: Self.previewTileSize.height)
        ])

        body.card(nil, [
            (themeRow(), ["theme", "appearance", "auto", "light", "dark"]),
            (chromeLayoutRow(), ["layout", "chrome", "sidebar", "top bar", "tabs"]),
            (searchBarRow(), ["search bar", "address bar", "url bar", "on the page", "top of the page"]),
            (sideRow(), ["sidebar side", "tabs", "tab position", "sidebar position", "left", "right"]),
            (cornersRow(), ["corners", "rounded corners", "round", "radius", "window shape"])
        ])
        body.card("Glass", [
            (glassRow(), ["optimise glass for this display", "optimize glass", "liquid glass", "retina", "1x", "blur"]),
            (SettingsRow.accessory("Preview", subtitle: nil, accessory: tileHost),
             ["preview", "optimise glass for this display"])
        ])
        rebuildTile()

        // §7: the scale factor belongs to the window's current screen, so a
        // window dragged between displays re-resolves. Both notifications,
        // because a backing change and a screen-arrangement change are
        // different events and only one of them fires per move.
        let centre = NotificationCenter.default
        for name in [NSWindow.didChangeBackingPropertiesNotification,
                     NSApplication.didChangeScreenParametersNotification] {
            centre.addObserver(self, selector: #selector(displayChanged), name: name, object: nil)
        }
    }

    @objc private func displayChanged() {
        rebuildTile()
    }

    private func themeRow() -> NSView {
        let options = Theme.allCases
        return SettingsRow.segmented(
            "Theme",
            options: options.map(\.title),
            selected: options.firstIndex(of: Self.theme) ?? 0
        ) { index in
            let theme = options[index]
            UserDefaults.standard.set(theme.rawValue, forKey: Self.themeKey)
            // Nil is meaningful: it hands the choice back to System Settings.
            NSApp.appearance = theme.appearance
        }
    }

    private func glassRow() -> NSView {
        let options: [GlassOptimisation] = [.auto, .on, .off]
        return SettingsRow.segmented(
            "Optimise glass for this display",
            options: ["Auto", "On", "Off"],
            selected: options.firstIndex(of: Glass.optimisation) ?? 0
        ) { [weak self] index in
            // Assigning re-skins every live glass view in the app, including
            // the browser window's, and persists the key. This section does not
            // re-detect anything and must not.
            Glass.optimisation = options[index]
            self?.rebuildTile()
        }
    }

    /// Rebuilt rather than mutated: a glass view's material is chosen when it is
    /// constructed. `Glass.previewTile` marks it decorative for VoiceOver (§8) —
    /// the segmented control above it carries the meaning.
    private func rebuildTile() {
        let optimised = Glass.isOptimised(for: tileHost.window)
        let tile = Glass.previewTile(size: Self.previewTileSize, optimised: optimised)
        tile.translatesAutoresizingMaskIntoConstraints = false
        let swap = {
            self.tileHost.subviews.forEach { $0.removeFromSuperview() }
            self.tileHost.addSubview(tile)
            NSLayoutConstraint.activate([
                tile.leadingAnchor.constraint(equalTo: self.tileHost.leadingAnchor),
                tile.trailingAnchor.constraint(equalTo: self.tileHost.trailingAnchor),
                tile.topAnchor.constraint(equalTo: self.tileHost.topAnchor),
                tile.bottomAnchor.constraint(equalTo: self.tileHost.bottomAnchor)
            ])
        }
        // §5 gives this row `layoutSwitch`; under Reduce Motion `animate` runs
        // the same change at zero duration.
        Tokens.Motion.animate(Tokens.Motion.layoutSwitch) { _ in swap() }
    }

    /// The window's corner: Luna's own, or the one macOS gives its windows.
    private func cornersRow() -> NSView {
        SettingsRow.toggle(
            "Match macOS corners",
            value: Settings.macWindowCorners
        ) { matches in
            // The setter posts `Settings.didChange`, and every window's root
            // view and content pane follow it.
            Settings.macWindowCorners = matches
        }
    }

    /// Which chrome the window wears — and the reason `⌘S` could stop meaning
    /// "swap the layout". Revealing the sidebar is a reflex performed several
    /// times a minute; choosing between the two layouts is a preference taken
    /// once. The reflex kept `⌘S`; the preference moved here.
    ///
    /// A picture of each layout rather than two words: the picture shows
    /// where the tabs go before the user has to try it (`SettingsLayoutPicker`).
    private func chromeLayoutRow() -> NSView {
        let picker = SettingsLayoutPicker(selected: Settings.chromeLayout)
        picker.onChoose = { [weak self] layout in
            // The setter posts `Settings.didChange`; `AppDelegate` is listening
            // and re-anchors the running window. Nothing here reaches for it.
            Settings.chromeLayout = layout
            // The two rows below exist only for the sidebar.
            self?.refreshSearchBarRow()
        }
        return SettingsRow.accessory("Layout", subtitle: nil, accessory: picker)
    }

    /// §3.2b. Where the address pill goes within the sidebar layout: at the
    /// head of the column as §3.2 built it, or on a bar across the top of the
    /// page, taking §3.1's back and reload with it.
    ///
    /// Gone under the top bar, not dimmed. §4 has no search bar anywhere — its
    /// tabs open the address — so under that layout this is not a question
    /// with a greyed-out answer — it is not a question. A dimmed row is for a control
    /// that has an answer Luna cannot honour yet (§30.4); this one has none to
    /// have.
    private func searchBarRow() -> NSView {
        let places = SearchBarPlacement.allCases
        let row = SettingsRow.segmented(
            "Search bar",
            options: places.map(\.title),
            selected: places.firstIndex(of: Settings.searchBarPlacement) ?? 0
        ) { index in
            guard places.indices.contains(index) else { return }
            Settings.searchBarPlacement = places[index]
        }
        searchBarHost = row
        row.isHidden = Settings.chromeLayout != .sidebar
        return row
    }

    private func refreshSearchBarRow() {
        searchBarHost?.isHidden = Settings.chromeLayout != .sidebar
        sideHost?.isHidden = Settings.chromeLayout != .sidebar
    }

    /// §3's sidebar side.
    private func sideRow() -> NSView {
        let sides = TabsPosition.allCases
        let row = SettingsRow.segmented(
            String(localized: "Sidebar side"),
            options: sides.map(\.title),
            selected: sides.firstIndex(of: Settings.tabsPosition) ?? 0
        ) { index in
            guard sides.indices.contains(index) else { return }
            Settings.tabsPosition = sides[index]
        }
        sideHost = row
        row.isHidden = Settings.chromeLayout != .sidebar
        return row
    }
}
