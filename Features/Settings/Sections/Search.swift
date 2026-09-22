//
//  Search.swift
//  Luna
//
//  §23.1 §3.4. The section that actually removes a hard-coded value: the engine
//  was a constant inside `CommandBarURL.search(for:)` and is now
//  `SearchSettings`, which the §3.2 URL pill and the §9.2 Command Bar both
//  commit through — so they still cannot disagree about what a query means.
//
//  §9.7 is the constraint that shaped the storage, not this file. The
//  local-results path runs synchronously inside `controlTextDidChange` at a
//  measured 9.6 ms median, and it must not acquire a `UserDefaults` read on the
//  way. `SearchSettings` therefore holds the resolved value in memory behind a
//  `Mutex` and this section writes through it: the in-memory half first, the
//  persisted half second. Nothing here is on the keystroke path.
//
//  Suggestions are built, and default on. They fetch from the engine that
//  is already chosen here and from nowhere else — see `SearchSuggestions`,
//  which owns the one network call in the query path and states exactly what
//  leaves the Mac.
//
//  A broken custom URL is reported by the field itself rather than by a
//  sentence under it: red text means Luna is not using what is typed there.
//

import AppKit

@MainActor
final class SearchSection: SettingsSection {

    static let id = "search"
    static let title = "Search"
    static let symbolName = "magnifyingglass"
    static let keywords = ["engine", "duckduckgo", "google", "bing", "kagi", "suggestions", "address bar"]

    private let body = SettingsBody()
    private let custom: SettingsTextField

    var view: NSView { body.view }
    var searchIndex: [String] { body.searchIndex }
    func filter(_ query: String) { body.filter(query) }

    init() {
        // Re-sync in case `SettingsDefaults.restoreAll()` removed the keys
        // while nothing was watching. Once, on open — never per keystroke.
        SearchSettings.reload()
        custom = SettingsTextField(string: SearchSettings.current.customTemplate)
        body.card(nil, [
            (engineRow(), ["search engine", "duckduckgo", "google", "bing", "kagi", "custom"]),
            (customRow(), ["custom engine url", "search engine", "%s", "placeholder"]),
            (suggestionsRow(), ["search suggestions", "autocomplete", "complete"]),
            (settingsResultsRow(), ["settings in search results", "command bar", "sections", "open in settings"])
        ])
        refreshValidity()
    }

    // MARK: Rows

    private func engineRow() -> NSView {
        let options = SearchEngine.allCases
        return SettingsRow.popup(
            "Search engine",
            options: options.map(\.title),
            selected: options.firstIndex(of: SearchSettings.current.engine) ?? 0
        ) { [weak self] index in
            var setting = SearchSettings.current
            setting.engine = options[index]
            SearchSettings.apply(setting)
            self?.refreshValidity()
        }
    }

    /// Always editable, whichever engine is selected: `SearchEngineSetting` only
    /// consults the template when `.custom` is chosen, and a user who types
    /// their engine before picking it in the popup gets the order they expected
    /// rather than a dead field.
    private func customRow() -> NSView {
        custom.placeholderString = "https://example.com/search?q=\(SearchEngineSetting.placeholder)"
        custom.cell?.sendsActionOnEndEditing = true
        custom.widthAnchor.constraint(equalToConstant: Tokens.Metric.urlPill.width).isActive = true
        let action = SettingsAction { [weak self] sender in
            var setting = SearchSettings.current
            setting.customTemplate = (sender as? NSTextField)?.stringValue ?? ""
            SearchSettings.apply(setting)
            self?.refreshValidity()
        }
        custom.target = action
        custom.action = #selector(SettingsAction.fire(_:))
        return SettingsRow
            .accessory("Custom engine URL", subtitle: nil, accessory: custom)
            .retaining(action)
    }

    private func suggestionsRow() -> NSView {
        SettingsRow.toggle("Search suggestions", value: SearchSettings.current.suggestions) { on in
            var setting = SearchSettings.current
            setting.suggestions = on
            SearchSettings.apply(setting)
        }
    }

    /// §9.2's settings rows. On, and the one switch here that sends nothing
    /// anywhere: the index it searches is ten section titles and their
    /// keywords, compiled into the app. Off for anyone who wants the bar to
    /// answer with pages and nothing else.
    private func settingsResultsRow() -> NSView {
        SettingsRow.toggle("Settings in search results", value: SearchSettings.current.settingsResults) { on in
            var setting = SearchSettings.current
            setting.settingsResults = on
            SearchSettings.apply(setting)
        }
    }

    // MARK: Validity

    /// §3.4's "validated", as the field's own ink.
    ///
    /// A sentence under the row spelled out which engine searches went to and
    /// what the custom URL needed, which is three lines to say what the popup
    /// one row up already says. What it could not be replaced by is nothing:
    /// a custom template without `%s` is silently ignored and searches fall
    /// back to DuckDuckGo, so the field has to admit when Luna is not using it.
    private func refreshValidity() {
        let setting = SearchSettings.current
        let broken = setting.engine == .custom
            && !setting.customTemplate.isEmpty
            && !SearchEngineSetting.isUsable(setting.customTemplate)
        custom.warns = broken
        custom.setAccessibilityHelp(
            broken
                ? "Not in use: needs an http or https URL containing \(SearchEngineSetting.placeholder)."
                : nil
        )
    }
}
