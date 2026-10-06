//
//  OnboardingMappingView.swift
//  Luna — §23.2, §30.17
//
//  The import's mapping step: one row per kind of thing the browser keeps,
//  with how many there are and where in Luna they land. It only edits an
//  `ImportMapping`; the importer is what reads it.
//
//  Settings' own row, card and pick-one control rather than new ones: it is a
//  form, and those already answer the pointer and both appearances.
//

import AppKit
import BrowserKit

@MainActor
final class OnboardingMappingView: NSView {

    private(set) var mapping: ImportMapping
    var onChange: ((ImportMapping) -> Void)?
    private var card: SettingsRowGroupView?

    init(mapping: ImportMapping) {
        self.mapping = mapping
        super.init(frame: .zero)
        let rows = mapping.categories.map(row(for:))
        let card = SettingsRowGroupView(title: nil, rows: rows)
        addSubview(card)
        self.card = card
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(String(localized: "Where things go"))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    private func row(for category: ImportCategory) -> NSView {
        let destinations = category.destinations
        let choice = SettingsChoice(labels: destinations.map(\.title))
        choice.selectedIndex = destinations.firstIndex(of: mapping[category]) ?? 0
        choice.onSelect = { [weak self] index in
            guard let self else { return }
            mapping[category] = destinations[index]
            onChange?(mapping)
        }
        return SettingsRowView(
            title: category.title,
            subtitle: category.countLabel(mapping.counts[category] ?? 0),
            control: choice,
            isEnabled: true,
            disabledReason: nil
        )
    }

    /// As tall as its rows at `width`.
    func height(forWidth width: CGFloat) -> CGFloat {
        guard let card else { return 0 }
        card.frame.size.width = width
        card.layoutSubtreeIfNeeded()
        return ceil(card.fittingSize.height)
    }

    override func layout() {
        super.layout()
        Tokens.Motion.immediately { card?.frame = bounds }
    }
}

extension ImportCategory {
    var title: String {
        switch self {
        case .favorites: String(localized: "Favorites")
        case .pinnedFolders: String(localized: "Pinned folders")
        case .pinnedTabs: String(localized: "Pinned tabs")
        case .bookmarkBar: String(localized: "Bookmarks bar")
        case .bookmarkFolders: String(localized: "Bookmark folders")
        case .history: String(localized: "History")
        }
    }

    func countLabel(_ count: Int) -> String {
        if self == .history {
            return count == 1 ? String(localized: "1 visit") : String(localized: "\(count) visits")
        }
        return count == 1 ? String(localized: "1 site") : String(localized: "\(count) sites")
    }
}

extension ImportDestination {
    /// History's choice is whether, not where, so its answer is a verb.
    var title: String {
        switch self {
        case .favorites: String(localized: "Favorites")
        case .pinnedFolders: String(localized: "Pinned folders")
        case .history: String(localized: "Import")
        case .skip: String(localized: "Skip")
        }
    }
}
