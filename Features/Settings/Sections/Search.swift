//
//  Search.swift
//  Luna
//
//  §23.1 §3.4. The section that actually removes a hard-coded value: the
//  engine was a constant inside `CommandBarURL.search(for:)` and is now
//  `SearchSettings`, which the §3.2 URL pill and the §9.2 Command Bar both
//  commit through — so they still cannot disagree about what a query means.
//
//  **§9.7 is the constraint that shaped the storage, not this file.** The
//  local-results path runs synchronously inside `controlTextDidChange` at a
//  measured 9.6 ms median, and it must not acquire a `UserDefaults` read on the
//  way. `SearchSettings` therefore holds the resolved value in memory behind a
//  `Mutex` and this section writes *through* it: the in-memory half first, the
//  persisted half second. Nothing here is on the keystroke path.
//
//  **Suggestions ship disabled and would ship off.** §9.6's suggest endpoint
//  does not exist, and D16 says Luna collects nothing — a suggestions switch
//  sends every keystroke to a third party, which is the one thing the privacy
//  policy already written rules out. Default-off is not a nicety here; an
//  on-by-default suggest box would contradict a published document.
//

import AppKit

@MainActor
final class SearchSection: SettingsSection {

    static let id = "search"
    static let title = "Search"
    static let symbolName = "magnifyingglass"

    private let body = SettingsBody()
    private let validation = SettingsNoteHost()

    var view: NSView { body.view }
    var searchIndex: [String] { body.searchIndex }
    func filter(_ query: String) { body.filter(query) }

    init() {
        // Re-sync in case `SettingsDefaults.restoreAll()` removed the keys
        // while nothing was watching. Once, on open — never per keystroke.
        SearchSettings.reload()
        body.card("Search engine", [
            (engineRow(), ["search engine", "duckduckgo", "google", "bing", "kagi", "custom"]),
            (customRow(), ["custom engine url", "search engine", "%s", "placeholder"])
        ])
        body.loose(validation, terms: ["search engine", "custom engine url"])
        body.card("Suggestions", [
            (suggestionsRow(), ["search suggestions", "autocomplete", "privacy"])
        ])
        refreshValidation()
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
            self?.refreshValidation()
        }
    }

    /// Always editable, whichever engine is selected.
    ///
    /// The declared row API builds a control once and returns an opaque view,
    /// so a field that enabled itself when the popup reached "Custom" would have
    /// to be hand-rolled — which §4 forbids. Keeping it live costs nothing:
    /// `SearchEngineSetting` only consults the template when `.custom` is
    /// selected, and a user who types their engine before choosing it in the
    /// popup gets the order they expected rather than a dead field.
    private func customRow() -> NSView {
        SettingsRow.text(
            "Custom engine URL",
            value: SearchSettings.current.customTemplate,
            placeholder: "https://example.com/search?q=\(SearchEngineSetting.placeholder)"
        ) { [weak self] text in
            var setting = SearchSettings.current
            setting.customTemplate = text
            SearchSettings.apply(setting)
            self?.refreshValidation()
        }
    }

    private func suggestionsRow() -> NSView {
        SettingsRow.toggle(
            "Search suggestions",
            subtitle: "Would send every keystroke to the search engine.",
            value: false,
            isEnabled: false,
            disabledReason: "Luna has no suggestions endpoint, and it would default to off when it does."
        ) { _ in }
    }

    // MARK: Validation

    /// §3.4's "validated" — as a line the user can read, because the declared
    /// row API has nowhere to put an error badge and a field that silently
    /// discards what you typed is worse than one that explains itself.
    private func refreshValidation() {
        validation.setText(Self.validationText(SearchSettings.current))
    }

    static func validationText(_ setting: SearchEngineSetting) -> String {
        let token = SearchEngineSetting.placeholder
        guard setting.engine == .custom else {
            return "Searches go to \(setting.engine.title). The custom URL is kept, not used."
        }
        if setting.customTemplate.isEmpty {
            return "Enter a URL containing \(token) — Luna puts the query there."
        }
        guard SearchEngineSetting.isUsable(setting.customTemplate) else {
            return "Not in use: needs an http or https URL containing \(token). "
                + "Searching \(SearchEngine.fallback.title) until it does."
        }
        return "Searches go to your custom engine."
    }
}
