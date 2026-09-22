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
    /// Token-AND over the title and the keywords, the same rule
    /// `CommandBarRanking.matches` uses on a tab. What the number says, in
    /// order: a title the query starts beats one it does not — so "se" offers
    /// Search before General, which "restore session" is a keyword of; between
    /// two of those, the one the query covers more of; below them, the more of
    /// the query the title itself answered; and last, the shorter title.
    private static func score(_ tokens: [String], for entry: SettingsEntry) -> Double? {
        let title = entry.title.lowercased()
        let found = tokens.allSatisfy { token in
            title.contains(token) || entry.keywords.contains { $0.contains(token) }
        }
        guard found else { return nil }
        // A title the query starts, ranked by how much of it the query covers:
        // "new" is the whole front of New Window and a third of New Private
        // Window, and the shorter one is what was meant.
        let query = tokens.joined(separator: " ")
        if title.hasPrefix(query) { return 2 + Double(query.count) / Double(title.count) }
        // Otherwise, how much of the query the title itself answered — the rest
        // came from the keywords — and, between two that answered as much, the
        // shorter title. "copy link" is half a title match for both Copy URL
        // and Copy URL as Markdown, and Copy URL is the one being asked for.
        let inTitle = Double(tokens.count { title.contains($0) }) / Double(tokens.count)
        return inTitle + 1 / Double(title.count + 1)
    }
}
