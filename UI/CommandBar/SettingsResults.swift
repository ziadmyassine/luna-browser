//
//  SettingsResults.swift
//  Luna
//
//  §9.2's settings rows: type the name of a Settings section into the bar and
//  the section is offered, with its own symbol and `Open in Settings` under it.
//
//  Ten sections is already more than anyone holds in their head, and §2's own
//  search only helps once the window is open — which is the half of the problem
//  that needed a keystroke to reach. So the register is offered here as well.
//
//  Pure, like the rest of `CommandBarRanking`'s inputs: the entries are plain
//  values the controller hands in, so a section's title and symbol reach the
//  ranker without any of this file knowing what a `SettingsSection` is.
//

import Foundation

/// One §3 section of the Settings window, flattened to what a row needs.
struct SettingsEntry: Sendable, Hashable {
    /// `SettingsSection.id` — what `AppDelegate.showSettings(section:)` takes.
    var id: String
    var title: String
    var symbolName: String
    /// What should find the section besides its title, lowercased. "cookies"
    /// has to reach Privacy & Blocking; nobody types the section's name when
    /// they already know the name of the switch they are after.
    var keywords: [String]
}

enum SettingsResults {

    /// The subtitle every one of these rows carries, in the slot a tab row
    /// uses for `Switch to tab`: the row does not load a page, and the list it
    /// is standing in is otherwise entirely pages.
    static let opens = String(localized: "Open in Settings")

    /// Rows for the sections `tokens` names, unranked between themselves
    /// beyond `score` — `CommandBarRanking.order` sorts the tier.
    ///
    /// Empty for an empty query, exactly as commands are: `⌘T`'s opening list
    /// is for getting somewhere, not for browsing an index of Settings.
    static func rows(tokens: [String], entries: [SettingsEntry]) -> [CommandBarResult] {
        guard !tokens.isEmpty, SearchSettings.current.settingsResults else { return [] }
        return entries.compactMap { entry in
            guard let score = score(tokens, for: entry) else { return nil }
            return CommandBarResult(
                source: .settings,
                title: entry.title,
                subtitle: opens,
                action: .openSettings(entry.id),
                score: score,
                symbolName: entry.symbolName
            )
        }
    }

    /// Nil when the section does not answer at all, and otherwise how squarely.
    ///
    /// The title outranks the keywords, and a title the query starts outranks
    /// one it merely appears inside — so "se" offers Search before Spaces,
    /// which "session" happens to be a keyword of. Token-AND over both, the
    /// same rule `CommandBarRanking.matches` uses on a tab.
    private static func score(_ tokens: [String], for entry: SettingsEntry) -> Double? {
        let title = entry.title.lowercased()
        let found = tokens.allSatisfy { token in
            title.contains(token) || entry.keywords.contains { $0.contains(token) }
        }
        guard found else { return nil }
        if title.hasPrefix(tokens.joined(separator: " ")) { return 2 }
        return tokens.allSatisfy(title.contains) ? 1 : 0
    }
}
