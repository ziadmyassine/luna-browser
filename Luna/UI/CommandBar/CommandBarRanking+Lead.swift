//
//  CommandBarRanking+Lead.swift
//  Luna
//
//  The row that leads when what was typed is the start of a site the user
//  has been to: `it` → itslearning.com, completed inline (§9.4) and opened by
//  Return, with the search row second. Apart from the tier order because it
//  overrides it — Firefox's origin autofill and Safari's top hit work the
//  same way — and because it is the one decision Return depends on.
//
//  Left to the tiers, the top row went to any open or closed tab holding the
//  two letters anywhere, there was nothing to complete, and the search led:
//  the site came first for 15 of 30 typed pages (docs/PERF.md, §9.3).
//

import BrowserKit
import Foundation

extension CommandBarRanking {

    /// The lead, or nil when the query is not the start of a visited site.
    ///
    /// In order: a page the adaptive table learned for exactly these letters;
    /// the best site whose host starts with them; the best site whose
    /// registrable domain does (`itslearning` → `sdu.itslearning.com`). A
    /// lesson learned for a longer string does not count — `gi` had learned one
    /// GitHub repository through `git`, and every other GitHub page the user
    /// wanted lost to it.
    ///
    /// Only the first two complete inline. A host that starts further in
    /// cannot be a selected suffix of what was typed, so that row leads with
    /// the field left as typed.
    static func leadRow(query: String, sources: CommandBarSources) -> CommandBarResult? {
        guard !query.isEmpty, !query.contains(where: \.isWhitespace) else { return nil }
        let needle = query.lowercased()

        let lesson = sources.adaptive
            .filter { $0.typed.lowercased() == needle && starts(needle, CommandBarURL.displayForm(of: $0.url)) }
            .max { $0.useCount < $1.useCount }
        if let lesson { return adaptiveRow(lesson, sources: sources) }

        let typed = needle.utf8
        let byHost = sources.sites.first { site in
            site.host.utf8.starts(with: typed) && completes(needle, CommandBarURL.displayForm(of: site.url))
        }
        if let byHost { return siteRow(byHost) }

        let byDomain = sources.sites.first { site in
            guard let domain = site.domain, domain.utf8.count > typed.count else { return false }
            return domain.utf8.starts(with: typed)
        }
        return byDomain.map(siteRow)
    }

    /// The lead, then the search, then everything else in tier order. Rows for
    /// the lead's own page stay in the list for `dedupe` to fold onto it.
    /// A quick answer keeps the very top: `5+5` is a sum before it is anything.
    static func leading(_ lead: CommandBarResult, in rows: [CommandBarResult]) -> [CommandBarResult] {
        let answers = rows.prefix { $0.source == .answer }
        let rest = rows.dropFirst(answers.count)
        let search = rest.filter { $0.source == .search }
        return Array(answers) + [lead] + search + rest.filter { $0.source != .search }
    }

    private static func siteRow(_ site: VisitedSite) -> CommandBarResult {
        let address = CommandBarURL.displayForm(of: site.url)
        return CommandBarResult(
            source: .history,
            title: site.title.isEmpty ? address : site.title,
            subtitle: address,
            action: .open(site.url),
            url: site.url,
            score: site.score,
            symbolName: "clock"
        )
    }

    private static func starts(_ needle: String, _ address: String) -> Bool {
        address.lowercased().hasPrefix(needle)
    }

    /// Starts with it and goes further — the shape §9.4 can complete. A host
    /// typed out in full is left to its direct-address row.
    private static func completes(_ needle: String, _ address: String) -> Bool {
        address.count > needle.count && starts(needle, address)
    }

    // MARK: - Matching a word's start

    /// Every token begins a word somewhere in `haystack`: at its start, or after
    /// a character that is not a letter or a digit, which covers a title's
    /// words and an address's labels and path segments alike.
    static func matchesWordStarts(_ tokens: [String], _ haystack: String) -> Bool {
        let folded = haystack.lowercased()
        return tokens.allSatisfy { beginsAWord($0, in: folded) }
    }

    private static func beginsAWord(_ token: String, in text: String) -> Bool {
        var from = text.startIndex
        while let found = text.range(of: token, range: from..<text.endIndex) {
            if found.lowerBound == text.startIndex { return true }
            let before = text[text.index(before: found.lowerBound)]
            if !before.isLetter, !before.isNumber { return true }
            from = text.index(after: found.lowerBound)
        }
        return false
    }
}
