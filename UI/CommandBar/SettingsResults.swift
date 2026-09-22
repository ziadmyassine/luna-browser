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
            guard let match = match(tokens, for: entry) else { return nil }
            return CommandBarResult(
                source: match.source,
                title: entry.title,
                subtitle: opens,
                action: .openSettings(entry.id),
                score: match.score,
                symbolName: entry.symbolName
            )
        }
    }

    /// Nil when the section does not answer at all, and otherwise which tier
    /// it answers in and how squarely.
    ///
    /// Token-AND over the title and the keywords, the same rule
    /// `CommandBarRanking.matches` uses on a tab. The tier is the first
    /// question: a section whose own name said nothing sits below the search
    /// row (`.keywordSettings`), because the word that found it is one the row
    /// does not show.
    ///
    /// What the number says, in order: a title the query starts beats one it
    /// does not — so "se" offers Search before General, which "restore
    /// session" is a keyword of; between two of those, the one the query
    /// covers more of; below them, the more of the query the title itself
    /// answered; and last, the shorter title.
    private static func match(_ tokens: [String], for entry: SettingsEntry) -> (source: CommandBarSource, score: Double)? {
        let title = entry.title.lowercased()
        let found = tokens.allSatisfy { token in
            title.contains(token) || entry.keywords.contains { $0.contains(token) }
        }
        guard found else { return nil }
        // The shorter title, between two that answered as much.
        let tieBreak = 1 / Double(title.count + 1)
        let inTitle = Double(tokens.count { title.contains($0) }) / Double(tokens.count)
        guard inTitle > 0 else { return (.keywordSettings, tieBreak) }
        // A title the query starts, ranked by how much of it the query covers:
        // "gene" is the whole front of General, and "ge" less of it.
        let query = tokens.joined(separator: " ")
        if title.hasPrefix(query) { return (.settings, 2 + Double(query.count) / Double(title.count)) }
        // Otherwise, how much of the query the title itself answered — the rest
        // came from the keywords.
        return (.settings, inTitle + tieBreak)
    }
}
