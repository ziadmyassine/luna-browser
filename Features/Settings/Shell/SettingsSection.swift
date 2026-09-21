//
//  SettingsSection.swift
//  Luna
//
//  The contract every §3 section is built against, the §1 shape table, and the
//  register of the nine sections the window shows.
//

import AppKit

/// One §3 section: a title, a symbol, a view, and the two halves of §2's search.
///
/// `init()` takes no arguments on purpose — a section that needs the running
/// app looks it up rather than being handed it, because the Settings window can
/// be open before `AppDelegate.startSession` has finished.
@MainActor
protocol SettingsSection: AnyObject {
    static var id: String { get }
    static var title: String { get }
    static var symbolName: String { get }
    init()
    var view: NSView { get }
    /// Every searchable label in this section, lowercased (§2's search).
    var searchIndex: [String] { get }
    /// Show only rows matching `query`; empty string restores all.
    func filter(_ query: String)
}

/// §1's shape table. Every value is an existing `Tokens.Metric`.
enum SettingsMetrics {

    static let contentSize = CGSize(
        width: Tokens.Metric.settingsDefaultWidth,
        height: Tokens.Metric.settingsDefaultHeight
    )
    static let minWidth = Tokens.Metric.settingsMinWidth
    static let minHeight = Tokens.Metric.settingsMinHeight
    static let listWidth = Tokens.Metric.settingsListWidth

    static let rowGap = Tokens.Metric.rowGap
    static let rowCornerRadius = Tokens.Metric.rowCornerRadius
    static let paneInset = Tokens.Metric.chromeGapWide
    static let controlRowGap = Tokens.Metric.chromeGap
    static let searchHeight = Tokens.Metric.urlPill.height
    static let symbolSize = Tokens.Metric.faviconSize

    /// The section list: the row's pitch, the gap between two pills, and what
    /// is left for the pill itself.
    ///
    /// The browser sidebar's own three numbers, not a set of its own that
    /// came close. They are aliased rather than spelled out so the equality is
    /// a fact of the code: retune a tab row and §2's list follows it.
    static let sectionRowHeight = Tokens.Metric.rowHeight
    static let sectionRowGap = Tokens.Metric.rowGap
    static let sectionPillHeight = Tokens.Metric.rowPillHeight

    /// A card row, and the inset that is the pane's whole text grid: the rules
    /// between rows start there and so does a group's header, so every piece of
    /// type in the pane lines up on one edge.
    static let cardRowHeight = Tokens.Metric.settingsCardRow
    static let cardInset = Tokens.Metric.chromeGapWide
    static let groupGap = Tokens.Metric.settingsGroupGap

    /// One height and one corner for every control in the pane.
    static let controlHeight = Tokens.Metric.settingsControl
    static let controlCorner = Tokens.Metric.settingsControlCorner
    static let controlInset = Tokens.Metric.settingsControlInset

    /// §5's search stagger — §5 names no interval, so this borrows §4.1's.
    static let searchStagger = Tokens.Motion.layoutSwitchStagger
    static let searchStaggerCap = 6
}

/// §3's ten sections, in §2's order — which is also the `⌘1…⌘9` order for
/// the first nine.
@MainActor
enum SettingsSectionRegistry {

    /// The one list. `MainMenu` builds its section items from it, the window
    /// builds its list from it, and `SettingsDefaults` takes the first entry as
    /// the default `settings.lastSection`.
    static let all: [any SettingsSection.Type] = [
        GeneralSection.self,
        AppearanceSection.self,
        PrivacySection.self,
        PasswordsSection.self,
        SearchSection.self,
        DownloadsSection.self,
        ShortcutsSection.self,
        SpacesSection.self,
        ExtensionsSection.self,
        AdvancedSection.self
    ]

    static var ids: [String] { all.map { $0.id } }

    /// The index `settings.lastSection` names, or 0. Never nil: §2 requires
    /// exactly one section to be selected, always.
    static func index(ofID id: String?) -> Int {
        guard let id, let found = ids.firstIndex(of: id) else { return 0 }
        return found
    }
}
