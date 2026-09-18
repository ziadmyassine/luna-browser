//
//  SettingsSection.swift
//  Luna
//
//  The contract every §3 section is built against, the §1 shape table, and the
//  register of the nine sections the window shows.
//
//  This file is published **first and frozen**: agents B and C compile against
//  the protocol below while the window around it is still being written, so the
//  signatures here are the ones in `SETTINGS-CONTRACT.md`, verbatim, whether or
//  not a better spelling exists.
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

/// §1's shape table.
///
/// **Every value is an existing `Tokens.Metric` where one exists.** The four
/// that do not exist yet are marked below and named in this agent's report —
/// `Design/` belongs to agent D, so a settings entry cannot be added to
/// `Tokens.Metric` from here. `CommandBarMetrics` set this precedent for the
/// same reason.
enum SettingsMetrics {

    // MARK: Window (§1) — now all tokens

    static let contentSize = CGSize(
        width: Tokens.Metric.settingsDefaultWidth,
        height: Tokens.Metric.settingsDefaultHeight
    )
    static let minWidth = Tokens.Metric.settingsMinWidth
    static let minHeight = Tokens.Metric.settingsMinHeight
    /// Deliberately *not* `sidebarWidth`, which is a `SpanMetric` because the
    /// user drags it. A nine-row list has nothing to drag for.
    static let listWidth = Tokens.Metric.settingsListWidth

    // MARK: Rows and panes (§1) — all derived

    static let rowHeight = Tokens.Metric.rowHeight
    static let rowCornerRadius = Tokens.Metric.rowCornerRadius
    static let rowGap = Tokens.Metric.rowGap
    static let paneInset = Tokens.Metric.chromeGapWide
    static let controlRowHeight = Tokens.Metric.capsuleHeight
    static let controlRowGap = Tokens.Metric.chromeGap
    static let searchHeight = Tokens.Metric.urlPill.height
    static let symbolSize = Tokens.Metric.faviconSize

    // MARK: The reference's shape (§1, re-measured)

    /// One row of the left column: its **pitch**, the gap the pill leaves to
    /// its neighbour, and what is left for the pill itself. The reference's
    /// list is on a fixed grid — the gap comes out of the row, not on top of it.
    static let sectionRowHeight = Tokens.Metric.settingsSectionRow
    static let sectionRowGap = Tokens.Metric.rowGap
    static let sectionPillHeight = Tokens.Metric.settingsSectionRow - Tokens.Metric.rowGap
    /// The tile's inset inside the row's own pill. Smaller than the pill's
    /// inset from the column, so the two insets add up to the reference's
    /// 14 pt from the glass edge to the tile.
    static let sectionRowInset = Tokens.Metric.rowInset - 2
    /// A control row inside a card, and the padding that holds it off the
    /// card's edges. **The row's own leading inset is the card's grid**: the
    /// separators between rows start there, and so does a group's header, so
    /// every piece of text in the pane lines up on one edge.
    static let cardRowHeight = Tokens.Metric.settingsCardRow
    static let cardInset = Tokens.Metric.chromeGapWide
    /// One card to the next, header included.
    static let groupGap = Tokens.Metric.settingsGroupGap
    /// The one corner the whole window is rounded to below the window itself:
    /// the search field, the nav capsule, and every plate a control sits on.
    static let fieldCorner = Tokens.Metric.settingsFieldCorner

    // MARK: Motion (§5) — reused, never invented

    /// §5's "staggered by index, capped at 6 rows". §5 names no stagger
    /// *interval*, so this borrows §4.1's — the only general-purpose one in
    /// `Tokens.Motion`.
    static let searchStagger = Tokens.Motion.layoutSwitchStagger
    static let searchStaggerCap = 6
}

/// §3's nine sections, in §2's order — which is also the `⌘1…⌘9` order.
@MainActor
enum SettingsSectionRegistry {

    /// The one list. `MainMenu` builds its section items from it, the window
    /// builds its list from it, and `SettingsDefaults` takes the first entry as
    /// the default `settings.lastSection`.
    static let all: [any SettingsSection.Type] = [
        GeneralSection.self,
        AppearanceSection.self,
        PrivacySection.self,
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
