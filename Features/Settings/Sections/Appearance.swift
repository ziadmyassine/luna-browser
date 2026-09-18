//
//  Appearance.swift
//  Luna
//
//  §23.1 §3.2, and the §7 glass row it exists for.
//
//  **The preview tile is the point of this section.** On the machine §7 was
//  measured on — 1920 × 1080, "UI Looks like 1920 × 1080", one point to one
//  physical pixel — the difference between `.clear` and tinted `.regular` is
//  the difference between chrome that reads as glass and chrome that reads as
//  a smear. A setting whose effect you can only judge by closing the window
//  and looking at the sidebar is a setting nobody tunes, so the tile is
//  rebuilt from `Glass.previewTile(size:optimised:)` on the same runloop turn
//  as the segment change.
//
//  Two of §3.2's four rows are disabled, for different reasons:
//    · **Sidebar position** — §3.2 already declares it disabled; the right-hand
//      sidebar is not built.
//    · **Show tab favicons** — §3.2 lists it as wired to "sidebar row model",
//      but the only chokepoint is `SidebarIcons.favicon(for:)`, which this
//      milestone does not own. The accessor below is published so wiring it is
//      one `guard`; until that guard exists the row is dimmed rather than
//      silently inert (§30.4).
//

import AppKit

@MainActor
final class AppearanceSection: NSObject, SettingsSection {

    static let id = "appearance"
    static let title = "Appearance"
    static let symbolName = "circle.lefthalf.filled"

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
    static let showFaviconsKey = "appearance.showFavicons"

    static var theme: Theme {
        UserDefaults.standard.string(forKey: themeKey).flatMap(Theme.init(rawValue:)) ?? .auto
    }

    /// Defaults on: the sidebar has drawn favicons since M1, and a setting that
    /// changes what the app looks like on first launch is a setting that has
    /// been misused. Read by `SidebarIcons.favicon(for:)`, the one chokepoint both the
    /// sidebar list and the Essentials grid route through.
    static var showFavicons: Bool {
        UserDefaults.standard.object(forKey: showFaviconsKey) as? Bool ?? true
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
    /// **The one length in B's four sections that is not a `Tokens.Metric`.**
    /// It is a §23.1 number with no row in §1's table and `Design/` is agent
    /// D's; the report asks for `Tokens.Metric.glassPreviewTile` so this can
    /// become a reference. Nothing else here writes a literal length.
    static let previewTileSize = NSSize(width: 160, height: 72)

    // MARK: Section

    private let body = SettingsBody()
    /// Holds whichever tile is current. Rebuilt, not mutated: the material is
    /// chosen when the glass view is constructed.
    private let tileHost = NSView()

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
            (chromeLayoutRow(), ["chrome layout", "sidebar", "top bar", "tabs", "layout"]),
            (faviconRow(), ["show tab favicons in the sidebar", "favicons", "icons"]),
            (sidebarPositionRow(), ["sidebar position", "left", "right"])
        ])
        body.card("Glass", [
            (glassRow(), ["optimise glass for this display", "optimize glass", "liquid glass", "retina", "1x", "blur"]),
            (SettingsRow.accessory("Preview", subtitle: nil, accessory: tileHost),
             ["preview", "optimise glass for this display"])
        ])
        rebuildTile()

        // §7: the scale factor belongs to the window's *current screen*, so a
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
            subtitle: "Thickens the material where one point is one pixel, so the specular rim survives.",
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

    /// Which chrome the window wears.
    ///
    /// This row is the reason `⌘S` could stop meaning "swap the layout".
    /// Revealing the sidebar is a reflex performed several times a minute;
    /// choosing between the two layouts is a preference taken once, and a
    /// keystroke that did both let the reflex silently change the preference.
    /// The reflex kept `⌘S`; the preference moved here.
    private func chromeLayoutRow() -> NSView {
        let layouts = ChromeLayoutPreference.allCases
        let current = Settings.chromeLayout
        return SettingsRow.segmented(
            "Chrome layout",
            subtitle: current.detail,
            options: layouts.map(\.title),
            selected: layouts.firstIndex(of: current) ?? 0
        ) { index in
            guard layouts.indices.contains(index) else { return }
            // The setter posts `Settings.didChange`; `AppDelegate` is listening
            // and re-anchors the running window. Nothing here reaches for it.
            Settings.chromeLayout = layouts[index]
        }
    }

    private func faviconRow() -> NSView {
        SettingsRow.toggle(
            "Show tab favicons in the sidebar",
            value: Self.showFavicons
        ) { value in
            UserDefaults.standard.set(value, forKey: Self.showFaviconsKey)
            // `SidebarIcons.favicon(for:)` is the one chokepoint — the sidebar
            // list and the Essentials grid both read through it — but nothing
            // re-reads it on its own, so the change has to be announced.
            SettingsHost.session?.notifyChange()
        }
    }

    private func sidebarPositionRow() -> NSView {
        SettingsRow.segmented(
            "Sidebar position",
            options: ["Left", "Right"],
            selected: 0,
            isEnabled: false,
            disabledReason: "A right-hand sidebar is not built yet."
        ) { _ in }
    }
}
