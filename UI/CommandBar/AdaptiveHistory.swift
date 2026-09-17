//
//  AdaptiveHistory.swift
//  Luna
//
//  §9.3's adaptive half, in memory and written through to `inputHistory`.
//
//  **Why in memory at all.** §9.7 gives the Command Bar one frame — 16 ms — to
//  put local results on screen, and adaptive matches are the rows that rank
//  *above* everything else, so they cannot arrive a frame late without the top of
//  the list visibly re-shuffling. The table is one row per string the user
//  actually typed *and* chose from, which is small enough to hold: this loads it
//  once and keeps it warm. Reads are synchronous; only the write is async.
//
//  `@MainActor` rather than an actor: the main actor is already the serialisation
//  domain every window's Command Bar shares, so an actor would buy a hop and no
//  safety. **One instance per `BrowserStore`** — hand the same one to every
//  window's `CommandBarController`, or two windows will bump divergent counts.
//

import BrowserKit
import Foundation

@MainActor
final class AdaptiveHistory {

    private struct Key: Hashable {
        var typed: String
        /// The normalised URL, so `https://x.com/` and `http://www.X.com` are one
        /// lesson rather than two.
        var url: String
    }

    private let store: BrowserStore
    private var entries: [Key: AdaptiveEntry] = [:]
    private var didLoad = false

    init(store: BrowserStore) {
        self.store = store
    }

    /// What `CommandBarRanking` reads, synchronously, on every keystroke.
    var snapshot: [AdaptiveEntry] {
        Array(entries.values)
    }

    /// Reads the table once. Safe to call on every `⌘T`; only the first does work.
    func loadIfNeeded() async {
        guard !didLoad else { return }
        didLoad = true
        // A failed read means "no lessons yet", never "no Command Bar". Adaptive
        // history is an accelerator; the bar is fully usable without it.
        guard let rows = try? await store.inputHistory() else { return }
        for row in rows {
            entries[Key(typed: row.typed, url: CommandBarURL.dedupeKey(row.url))] =
                AdaptiveEntry(typed: row.typed, url: row.url, useCount: row.useCount)
        }
    }

    /// §9.3: the user typed `typed` and chose `url`. Applies the bump in memory —
    /// so the next keystroke already ranks with it — and persists the result.
    ///
    /// Recording nothing for an empty query is the point of the feature: `⌘T` then
    /// return teaches nothing, because there was no string to associate.
    func record(typed rawTyped: String, url: URL) {
        let typed = rawTyped.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else { return }

        let key = Key(typed: typed, url: CommandBarURL.dedupeKey(url))
        let count = CommandBarRanking.bumped(entries[key]?.useCount ?? 0)
        entries[key] = AdaptiveEntry(typed: typed, url: url, useCount: count)

        Task { [store] in
            // A lost write costs one lesson, so it must not surface as an error the
            // user sees in the middle of a navigation.
            try? await store.setInputUseCount(typed: typed, url: url, useCount: count)
        }
    }
}
