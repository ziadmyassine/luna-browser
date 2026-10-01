//
//  CommandBarRanking.swift
//  Luna
//
//  §9.3, and nothing else. Pure functions over value types: given a query and a
//  snapshot of every local source, produce the ordered, deduped list §9.2 asks
//  for. No AppKit, no actor, no I/O, so `CommandBarRankingTests` can
//  hand-compute an order and assert it.
//
//  Frecency is not reimplemented here: this file consumes `BrowserStore`'s
//  `HistoryHit.score` and never second-guesses it. What it adds is the half the
//  store cannot see: tier order across sources, dedupe, and adaptive input
//  history.
//
//  §9.7 is why this is pure: `merge` runs synchronously on the main actor inside
//  `controlTextDidChange`, so local results are on screen in the keystroke's own
//  frame. The store query is the only asynchronous part and merges in after.
//

import BrowserKit
import Foundation

/// One remembered (typed string → chosen URL) pair (§9.3).
struct AdaptiveEntry: Sendable, Hashable {
    /// The string the user had typed at the moment they chose `url`.
    var typed: String
    var url: URL
    /// Grows by `useCount * 0.9 + 1` per use, so it converges on 10.
    var useCount: Double
}

/// Everything local, snapshotted. Held by `CommandBarController` and refreshed on
/// `BrowserSession.onChange`, never rebuilt per keystroke (§9.7).
///
/// One Space's, all of it. The bar is opened from inside a Space and answers
/// with that Space's things — its tabs, its archive, its history, its lessons —
/// because the Space is the cookie jar (§9) and a row from the other one is a
/// page signed in as somebody else.
struct CommandBarSources: Sendable {
    /// The active Space's tabs, archived ones included — they are the
    /// same rows (§11.1: `archive` is a view over `tabs`, not a second table).
    var tabs: [Tab] = []
    var adaptive: [AdaptiveEntry] = []
    /// Filled by the asynchronous `BrowserStore.searchHistory` pass, empty on the
    /// synchronous one. Already scoped to the Space by the query.
    var history: [HistoryHit] = []
    var commands: [AppCommand] = AppCommand.allCases
    /// The registrable domain of the page in the active tab, or nil when it
    /// shows no site. Clear Cookies is offered only with one.
    var activeSite: String?
    /// §20.1's menu commands, as rows the bar can offer — see
    /// `ShortcutResults`. Snapshotted by the controller when the bar opens,
    /// because a binding can be rebound and a command can stop applying.
    var shortcuts: [ShortcutEntry] = []
    /// §2's Settings sections, as rows the bar can offer — see
    /// `SettingsResults`. Handed in by the controller from
    /// `SettingsSectionRegistry`, which is `@MainActor` and AppKit's; this
    /// file is neither.
    var settings: [SettingsEntry] = []
    /// §3.4's suggestions, already fetched and parsed by
    /// `Luna/Features/Search/SearchSuggestions`. Strings, not URLs: the engine
    /// template turns them into one here, exactly as it does for a typed query,
    /// so a suggestion cannot carry a destination Luna did not build.
    var suggestions: [String] = []
}

enum CommandBarRanking {

    /// §9.3's adaptive update: `use_count = use_count * 0.9 + 1`.
    ///
    /// The asymptote §9.3 quotes is the arithmetic, not a clamp — the recurrence's
    /// fixed point is `x = 0.9x + 1`, i.e. exactly 10 — so a count that starts
    /// below 10 approaches it and never passes it. Do not "add" a `min(_, 10)`:
    /// it would be dead code that hides the fact that the formula is self-limiting.
    static func bumped(_ useCount: Double) -> Double {
        useCount * 0.9 + 1
    }

    /// §9.7: "results must never reorder under the user's cursor while they are
    /// moving through them."
    ///
    /// Once the user has taken the highlight off the top row, a late-arriving
    /// merge may only add. Everything already on screen keeps its contents and
    /// its position, so the row under the highlight is still the row they were
    /// looking at — which is the whole of the guarantee, and is why the incoming
    /// list's own order is discarded for the rows that are already showing.
    static func appendingWithoutReordering(
        onScreen: [CommandBarResult],
        incoming: [CommandBarResult]
    ) -> [CommandBarResult] {
        let shown = Set(onScreen.map(\.id))
        return onScreen + incoming.filter { !shown.contains($0.id) }
    }

    /// §9.2 merged and deduped, §9.3 ordered.
    static func merge(query rawQuery: String, sources: CommandBarSources, limit: Int) -> [CommandBarResult] {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let tokens = query.lowercased().split(separator: " ").map(String.init)

        var rows: [CommandBarResult] = []
        if let answer = QuickAnswer.answer(for: query) {
            rows.append(answerRow(answer))
        }
        rows.append(contentsOf: adaptiveRows(query: query, sources: sources))
        if let url = CommandBarURL.direct(from: query) {
            rows.append(directRow(url))
        }
        rows.append(contentsOf: tabRows(tokens: tokens, sources: sources))
        rows.append(contentsOf: historyRows(sources: sources))
        rows.append(contentsOf: commandRows(tokens: tokens, sources: sources))
        rows.append(contentsOf: ShortcutResults.rows(tokens: tokens, entries: sources.shortcuts))
        rows.append(contentsOf: SettingsResults.rows(tokens: tokens, entries: sources.settings))
        let hasDirect = rows.contains { $0.source == .directURL }
        if let search = searchRow(query: query, hasDirectURL: hasDirect) {
            rows.append(search)
        }
        rows.append(contentsOf: suggestionRows(query: query, sources: sources))

        return Array(searchFirst(dedupe(order(rows), adoptingOpenTabs: !hasDirect), query: rawQuery).prefix(limit))
    }

    /// The search row on top whenever the query reads as a search, and the
    /// tiers below it in their own order.
    ///
    /// Left at its tier it was never seen on a query that history answers well:
    /// `apple ads` filled all eight rows with old visits — one of them a
    /// Google results page for the same words — and Return opened that page
    /// instead of searching. A query reads as an address only while §9.4 can
    /// complete it from the best page, as `gith` completes `github.com`; that
    /// page keeps the top row, or autofill would have nothing to complete from.
    ///
    /// An answer stays above it: the search is the second reading of `5+5`.
    private static func searchFirst(_ rows: [CommandBarResult], query: String) -> [CommandBarResult] {
        let answers = rows.prefix { $0.source == .answer }.count
        guard let index = rows.firstIndex(where: { $0.source == .search }), index > answers else { return rows }
        var rest = rows
        let search = rest.remove(at: index)
        guard autofill(query: query, results: Array(rest.dropFirst(answers))) == nil else { return rows }
        rest.insert(search, at: answers)
        return rest
    }

    /// §9.4's completion: the top URL-bearing row, if what the user typed is a
    /// prefix of its display form. Returns the whole completion; the field
    /// selects the part beyond `query`.
    ///
    /// Only the top row: autofilling from row 4 would put text in the field
    /// that nothing on screen is highlighting.
    ///
    /// `query` is used untrimmed, because the caller sets the field's text to
    /// what comes back and selects everything past `query.count`, so trimming
    /// would shift that selection by the whitespace. Whitespace anywhere in the
    /// query means it is a search rather than an address, so there is nothing
    /// to complete — which is what makes the untrimmed comparison safe.
    static func autofill(query: String, results: [CommandBarResult]) -> String? {
        guard !query.isEmpty, !query.contains(where: \.isWhitespace),
              let url = results.first?.url
        else { return nil }
        let completion = CommandBarURL.displayForm(of: url)
        guard completion.count > query.count, completion.lowercased().hasPrefix(query.lowercased()) else { return nil }
        // Keep the user's own casing for the part they typed; only the tail is ours.
        return query + completion.dropFirst(query.count)
    }

    // MARK: - Sources

    /// §9.3. Firefox's shape, and the right one: a remembered input matches while
    /// the user is still on the way to typing it, so learning "gh" → the repo
    /// pays off from the first keystroke.
    ///
    /// Skipped for an empty query — every remembered string starts with "", so
    /// `⌘T`'s opening list would be the entire adaptive table.
    private static func adaptiveRows(query: String, sources: CommandBarSources) -> [CommandBarResult] {
        guard !query.isEmpty else { return [] }
        let needle = query.lowercased()
        return sources.adaptive
            .filter { $0.typed.lowercased().hasPrefix(needle) }
            .map { entry in
                CommandBarResult(
                    source: .adaptive,
                    title: title(for: entry.url, sources: sources),
                    subtitle: CommandBarURL.displayForm(of: entry.url),
                    action: .open(entry.url),
                    url: entry.url,
                    score: entry.useCount,
                    symbolName: "arrow.up.forward"
                )
            }
    }

    private static func directRow(_ url: URL) -> CommandBarResult {
        CommandBarResult(
            source: .directURL,
            title: CommandBarURL.displayForm(of: url),
            subtitle: url.absoluteString,
            action: .open(url),
            url: url,
            symbolName: "globe"
        )
    }

    /// The Space's open tabs (§9.2), plus its archive — which is the same rows
    /// with an `archivedAt` (§11.1).
    private static func tabRows(tokens: [String], sources: CommandBarSources) -> [CommandBarResult] {
        sources.tabs.compactMap { tab -> CommandBarResult? in
            // Every tab the Space has, whether or not it has a page loaded. A
            // kept tab in a folder is dormant almost all of the time (§3.4b),
            // and §19.2 drops the page of all but the last few tabs anyway.
            // With dormant rows left out, a pinned `Google` answered to nothing
            // and typing its name reached every archived search but the tab.
            // The row opens the tab where it stands, as a click in the column
            // does. Archived is the real line: that row comes back as a reopen.
            let archived = tab.archivedAt != nil
            // §3.4a: a renamed tab is found and shown under the name the user gave it.
            // Its own title is deliberately not also in the haystack — a tab you renamed
            // "Invoices" should not keep answering to whatever the page calls itself.
            let haystack = "\(tab.listTitle) \(CommandBarURL.displayForm(of: tab.url))"
            guard matches(tokens, haystack) else { return nil }
            return CommandBarResult(
                source: archived ? .archive : .openTab,
                title: tab.listTitle.isEmpty ? CommandBarURL.displayForm(of: tab.url) : tab.listTitle,
                subtitle: archived ? Self.reopens : Self.switches,
                action: archived ? .unarchiveTab(tab.id) : .activateTab(tab.id),
                url: tab.url,
                // Most recently used first within the tier.
                score: (archived ? tab.archivedAt ?? tab.lastActiveAt : tab.lastActiveAt).timeIntervalSinceReferenceDate,
                symbolName: archived ? "archivebox" : "square.on.square"
            )
        }
    }

    /// What a tab row will do, in the subtitle's own slot — the same slot the
    /// search row uses to say `Search Google` rather than repeating the URL.
    /// Not the address: the title has already named the tab, and a line of
    /// title over a line of address looks like every row that loads a page, so
    /// the bar read as not offering the tab at all.
    ///
    /// Any open tab, whether or not its page is loaded: §19.2 drops cold pages
    /// and keeps the tabs, so "switch" means the row, not the process.
    static let switches = String(localized: "Switch to tab")
    /// §6.3's archive, which is the other half of the same list and the one
    /// answer here that is not a switch — there is no tab to go to yet.
    static let reopens = String(localized: "Reopen tab")

    /// `BrowserStore.searchHistory` has already matched and ranked these; matching
    /// them again here would only disagree with FTS5 about what a word is.
    private static func historyRows(sources: CommandBarSources) -> [CommandBarResult] {
        sources.history.map { hit in
            CommandBarResult(
                source: .history,
                title: hit.title.isEmpty ? CommandBarURL.displayForm(of: hit.url) : hit.title,
                subtitle: CommandBarURL.displayForm(of: hit.url),
                action: .open(hit.url),
                url: hit.url,
                score: hit.score,
                symbolName: "clock"
            )
        }
    }

    /// Commands answer a query, never an empty bar — `⌘T`'s opening list is for
    /// getting somewhere, not for browsing a command index.
    private static func commandRows(tokens: [String], sources: CommandBarSources) -> [CommandBarResult] {
        guard !tokens.isEmpty else { return [] }
        return sources.commands.compactMap { command in
            var subtitle = ""
            if command == .clearCookies {
                guard let site = sources.activeSite else { return nil }
                subtitle = site
            }
            let named = matches(tokens, command.title)
            guard named || command.keywords.contains(where: { matches(tokens, $0) }) else { return nil }
            return CommandBarResult(
                source: named ? .command : .keywordShortcut,
                title: command.title,
                subtitle: subtitle,
                action: .command(command),
                symbolName: command.symbolName
            )
        }
    }

    /// The answer on the row's first line, the question under it, and what
    /// Return does with it, so the row says it copies rather than opens.
    private static func answerRow(_ answer: QuickAnswer) -> CommandBarResult {
        CommandBarResult(
            source: .answer,
            title: answer.value,
            subtitle: "\(answer.question) — Return copies the answer",
            action: .copy(answer.value),
            symbolName: answer.isConversion ? "arrow.left.arrow.right" : "equal"
        )
    }

    /// The floor: whatever else happened, a non-empty query can always be
    /// searched. The engine lives in `CommandBarURL.search(for:)`, which §3.2's
    /// pill commits through as well.
    private static func searchRow(query: String, hasDirectURL: Bool) -> CommandBarResult? {
        guard !query.isEmpty, !hasDirectURL, let url = CommandBarURL.search(for: query) else { return nil }
        // `url:` is deliberately left nil while the action carries the URL: a
        // search row must not dedupe against a history hit for the same search
        // page, and §9.4 must never autofill the field with a search URL.
        return CommandBarResult(
            source: .search,
            title: query,
            subtitle: "Search \(SearchSettings.current.engine.title)",
            action: .open(url),
            symbolName: "magnifyingglass"
        )
    }

    /// §3.4's suggestions as rows, in the order the engine returned them —
    /// which is its ranking, and re-sorting it here would be Luna second-
    /// guessing the only party that has seen more than one user's query.
    /// `score` counts down so `order(_:)` preserves that within the tier.
    ///
    /// The engine's echo of the query is dropped: `searchRow` is already that
    /// row, one tier up, and two identical lines is what makes a suggestion
    /// list look broken.
    private static func suggestionRows(query: String, sources: CommandBarSources) -> [CommandBarResult] {
        guard !query.isEmpty else { return [] }
        let typed = query.lowercased()
        let setting = SearchSettings.current
        var rank = 0.0
        return sources.suggestions.compactMap { phrase in
            guard phrase.lowercased() != typed, let url = setting.url(searching: phrase) else { return nil }
            rank -= 1
            return CommandBarResult(
                source: .suggestion,
                title: phrase,
                subtitle: "Search \(setting.engine.title)",
                action: .open(url),
                score: rank,
                symbolName: "magnifyingglass"
            )
        }
    }

    // MARK: - Order and dedupe

    /// §9.3's tier order. `CommandBarSource` is `Comparable` by declaration order,
    /// so the tier lives with the cases rather than in a switch that can drift.
    /// Score only ever breaks ties within a tier — an adaptive `useCount` of 3
    /// and a frecency score of 340 are not the same unit and are never compared.
    private static func order(_ rows: [CommandBarResult]) -> [CommandBarResult] {
        rows.sorted { lhs, rhs in
            if lhs.source != rhs.source { return lhs.source < rhs.source }
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.id < rhs.id
        }
    }

    /// §9.2 "merged and deduped". The best-ranked row for a URL wins its place —
    /// and, unless the query is itself an address, it inherits the open tab's
    /// action when one exists, so a page that is both first by adaptive history
    /// and already open switches to the live tab instead of loading a second
    /// copy of it (§19.4).
    ///
    /// An address you typed is never answered with a tab you already have.
    /// `directURL`'s own tier says a guess must not outrank an instruction, and
    /// adoption did exactly that: typing `google.com` with google.com open put
    /// `Switch to tab` on the top row. Type the address and you get the page;
    /// type the tab's name — `google` — and the open tab answers, because a name
    /// is a search of what you have.
    ///
    /// One row per URL, flatly, because every row on offer is in one Space and
    /// one cookie jar. A bar that offered another Space would need a row per
    /// (URL, jar) again: zen#14371 was one row for a page open in two Spaces,
    /// switching to whichever the loop reached last.
    private static func dedupe(_ rows: [CommandBarResult], adoptingOpenTabs: Bool) -> [CommandBarResult] {
        var slot: [String: Int] = [:]
        /// URLs whose kept row already carries a live tab's action.
        var live: Set<String> = []
        var out: [CommandBarResult] = []
        for row in rows {
            // Only an open tab is worth inheriting. Adopting an archived one
            // turns every history hit for a page the user ever closed into
            // `Reopen tab`, which in a Space with a long archive is the whole
            // list.
            let isTab = row.source == .openTab
            guard let index = slot[row.id] else {
                slot[row.id] = out.count
                if isTab { live.insert(row.id) }
                out.append(row)
                continue
            }
            guard isTab, adoptingOpenTabs, !live.contains(row.id) else { continue }
            adopt(row, into: &out[index], marking: &live)
        }
        return out
    }

    /// A history or adaptive row that is also an open tab switches to the live
    /// tab instead of loading a second copy of it (§19.4), keeping its own rank.
    ///
    /// The subtitle comes with the action. A row that says an address and then
    /// switches tabs is the same mismatch `switches` exists to close, one tier
    /// further up.
    private static func adopt(_ tab: CommandBarResult, into row: inout CommandBarResult, marking live: inout Set<String>) {
        live.insert(row.id)
        row.action = tab.action
        row.symbolName = tab.symbolName
        row.subtitle = tab.subtitle
    }

    // MARK: - Matching

    /// Every token has to appear somewhere. Token-AND rather than substring so
    /// "luna todo" finds a tab titled "TODO — luna-browser".
    private static func matches(_ tokens: [String], _ haystack: String) -> Bool {
        guard !tokens.isEmpty else { return true }
        let folded = haystack.lowercased()
        return tokens.allSatisfy(folded.contains)
    }

    /// An adaptive entry stores a URL, not a title. Borrow one from whatever else
    /// knows the page rather than showing a bare URL twice.
    private static func title(for url: URL, sources: CommandBarSources) -> String {
        let key = CommandBarURL.dedupeKey(url)
        if let tab = sources.tabs.first(where: { CommandBarURL.dedupeKey($0.url) == key }), !tab.title.isEmpty {
            return tab.title
        }
        if let hit = sources.history.first(where: { CommandBarURL.dedupeKey($0.url) == key }), !hit.title.isEmpty {
            return hit.title
        }
        return CommandBarURL.displayForm(of: url)
    }
}
