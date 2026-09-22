//
//  ShortcutResults.swift
//  Luna
//
//  §9.2's shortcut rows: the menu bar's own commands, offered by name, with
//  the keystroke that fires them printed where a page row prints its address.
//
//  Two things this is for. A command you know the name of but not the key —
//  "copy link" finds Copy URL and says ⇧⌘C, which is how you learn it — and a
//  command with no key at all, like Duplicate Tab, which otherwise lives three
//  levels into a menu.
//
//  Pure, like `SettingsResults` beside it: the entries are plain values
//  `BrowserCommand.commandBarEntries` hands in, so the ranker never sees a
//  `Selector`, an `NSMenuItem` or the responder chain.
//

import Foundation

/// One menu command, flattened to what a row needs.
struct ShortcutEntry: Sendable, Hashable {
    /// `BrowserCommand.id` — what `AppDelegate` looks the selector back up by.
    var id: String
    var title: String
    var symbolName: String
    /// The keystroke as the user sees it, `⇧⌘C`, or empty for a command that
    /// has none. Resolved when the bar opens, so a rebound key is the one
    /// printed.
    var shortcut: String
    /// What should find it besides its title, lowercased.
    var keywords: [String]
}

enum ShortcutResults {

    /// Rows for the commands `tokens` names.
    ///
    /// Empty for an empty query — `⌘T`'s opening list is for getting
    /// somewhere, not for reading the menu bar.
    static func rows(tokens: [String], entries: [ShortcutEntry]) -> [CommandBarResult] {
        guard !tokens.isEmpty else { return [] }
        return entries.compactMap { entry in
            guard let score = score(tokens, for: entry) else { return nil }
            return CommandBarResult(
                source: .shortcut,
                title: entry.title,
                subtitle: entry.shortcut,
                action: .runCommand(entry.id),
                score: score,
                symbolName: entry.symbolName
            )
        }
    }

    /// Nil when the command does not answer, and otherwise how squarely.
    ///
    /// Token-AND over the title and the keywords, the same rule everything
    /// else in the list is matched by. What the number says, in order: a title
    /// the query starts beats one it does not; between two of those, the one
    /// the query covers more of; below them, the more of the query the title
    /// itself answered rather than the keywords; and last, the shorter title.
    private static func score(_ tokens: [String], for entry: ShortcutEntry) -> Double? {
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
