//
//  SearchSuggestions.swift
//  Luna
//
//  §3.4's search suggestions: the completions the chosen engine offers while
//  you are still typing.
//
//  This file exists so that `UI/CommandBar` still cannot reach the network.
//  §9.6 is enforced by `CommandBarPrivacyTests`, which greps every source under
//  `UI/CommandBar` for a networking symbol and fails if one appears. That test
//  is not worked around here — it is the reason the fetch lives in `Features/`
//  instead. The Command Bar asks for `[String]` and is handed `[String]`; it
//  never learns that a wire was involved.
//
//  What leaves the Mac, exactly. The query, to the engine already chosen in
//  §3.4, over https, with no cookies, no cache and no credentials (see
//  `session`). Nothing else: no identifier, no referrer, no history. Kagi and a
//  custom engine have no endpoint here and so send nothing at all — see
//  `SearchEngine.suggestTemplate`.
//
//  And how little of it. Keystrokes are not queries. A pass is held for
//  `debounce` before it is allowed to leave, and the one in flight is cancelled
//  the moment another keystroke arrives, so a typed word costs about one
//  request rather than one per letter. Answers are remembered for the life of
//  the window, which makes backspacing free.
//

import Foundation

/// The one suggestion fetcher. `@MainActor` because its whole job is to call
/// back into the Command Bar's list, and hopping actors to deliver a handful of
/// strings would buy nothing.
@MainActor
final class SearchSuggestions {

    static let shared = SearchSuggestions()

    /// Long enough that a fast typist sends one request per word, short enough
    /// that a pause reads as instant. §9.7's budget is not involved: nothing
    /// here is on the synchronous keystroke path.
    nonisolated static let debounce: Duration = .milliseconds(180)

    /// Five rows. The list shows eight in all and the local sources have the
    /// better claim on them — a suggestion is a guess, and an open tab is not.
    nonisolated static let limit = 5

    /// Whatever has already been answered, for as long as the app runs.
    /// Suggestions are not personal data about the user, but they are made of
    /// what the user typed, so they stay in memory and are never written down.
    private var cache: [String: [String]] = [:]
    private var inFlight: Task<Void, Never>?

    private init() {}

    /// Already known, or nil if nobody has asked yet. Synchronous, so the
    /// Command Bar can fill a repeated query without waiting.
    func cached(for query: String) -> [String]? {
        cache[Self.key(query)]
    }

    /// Asks the engine, after the debounce, and calls back on the main actor
    /// with the strings — once, and only if this pass was not superseded.
    ///
    /// Cancels the previous pass unconditionally: the user has moved on, and a
    /// late answer to an abandoned query is the thing §9.7 forbids putting on
    /// screen.
    func request(_ query: String, then deliver: @escaping ([String]) -> Void) {
        inFlight?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = SearchSettings.current.suggestURL(for: trimmed) else { return }
        if let hit = cached(for: trimmed) {
            deliver(hit)
            return
        }
        inFlight = Task { [weak self] in
            try? await Task.sleep(for: Self.debounce)
            guard !Task.isCancelled else { return }
            let phrases = await Self.fetch(url)
            guard !Task.isCancelled, let self else { return }
            self.cache[Self.key(trimmed)] = phrases
            deliver(phrases)
        }
    }

    /// Dropped on the way out of the window, so a closed Command Bar is not
    /// still waiting on an engine.
    func cancel() {
        inFlight?.cancel()
        inFlight = nil
    }

    // MARK: - The wire

    /// Ephemeral, and that is the point. A shared session would attach the
    /// cookies the browser has for the engine, turning every keystroke into a
    /// request the engine can tie to a signed-in account. This one has no
    /// cookie store, no cache and no credential store to attach.
    private nonisolated static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        // A suggestion that arrives after the user has finished typing is worth
        // nothing, so it is not worth waiting for either.
        configuration.timeoutIntervalForRequest = 3
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()

    /// Failure is silence. There is no error state to show: a browser whose
    /// address bar reported that a suggestion service was unreachable would be
    /// reporting it constantly, and the list below is complete without it.
    private nonisolated static func fetch(_ url: URL) async -> [String] {
        guard let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200
        else { return [] }
        return Array(parse(data).prefix(limit))
    }

    /// OpenSearch's suggestion array: `["what you typed", ["a", "b", …], …]`.
    /// All three engines that have an endpoint speak it.
    ///
    /// `internal` rather than private so it can be asserted against real
    /// payloads in `SearchSuggestionsTests` without a network call.
    nonisolated static func parse(_ data: Data) -> [String] {
        guard let top = try? JSONSerialization.jsonObject(with: data) as? [Any], top.count >= 2,
              let phrases = top[1] as? [Any]
        else { return [] }
        // Trimmed and de-duplicated, because an engine may answer with the same
        // phrase cased two ways and the list would show it twice.
        var seen = Set<String>()
        return phrases
            .compactMap { ($0 as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }

    /// The cache is case- and whitespace-insensitive: "GIT" and "git " are the
    /// same question, and asking twice would be a second request for an answer
    /// already held.
    private nonisolated static func key(_ query: String) -> String {
        query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
