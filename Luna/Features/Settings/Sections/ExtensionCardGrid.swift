//
//  ExtensionCardGrid.swift
//  Luna
//
//  Settings ▸ Extensions' cards two to a row, and what the pane shows when
//  there are none.
//

import AppKit

/// Two cards a row, `settingsListGap` apart both ways — the gap a run of
/// cards of one kind keeps in a column (§3.7's Spaces). A row's two cards are
/// one height, so their controls, which stand on each card's foot, line up.
/// A last card on its own keeps half the width rather than stretching into a
/// banner that reads as something else.
@MainActor
final class ExtensionCardGrid: NSView {

    init(cards: [NSView]) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let gap = Tokens.Metric.settingsListGap
        let rows: [NSView] = stride(from: 0, to: cards.count, by: 2).map { start in
            let pair = Array(cards[start ..< min(start + 2, cards.count)])
            let row = NSStackView(views: pair.count == 2 ? pair : pair + [NSView()])
            row.orientation = .horizontal
            row.distribution = .fillEqually
            row.alignment = .top
            row.spacing = gap
            row.translatesAutoresizingMaskIntoConstraints = false
            if pair.count == 2 { pair[0].heightAnchor.constraint(equalTo: pair[1].heightAnchor).isActive = true }
            return row
        }
        let column = NSStackView(views: rows)
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = gap
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: leadingAnchor),
            column.trailingAnchor.constraint(equalTo: trailingAnchor),
            column.topAnchor.constraint(equalTo: topAnchor),
            column.bottomAnchor.constraint(equalTo: bottomAnchor)
        ] + rows.map { $0.widthAnchor.constraint(equalTo: column.widthAnchor) })
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }
}

/// No extensions yet: the puzzle piece, one line saying so, one saying where
/// they come from — the card above is how.
@MainActor
final class ExtensionsEmptyCard: NSView {

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let card = SettingsCardView()
        let glyph = NSImageView()
        glyph.image = NSImage(systemSymbolName: ExtensionsSymbol.name, accessibilityDescription: nil)
        glyph.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: Tokens.Metric.extensionCardIcon, weight: .light)
        glyph.contentTintColor = Tokens.Text.tertiary
        let title = NSTextField(labelWithString: String(localized: "No extensions yet"))
        title.font = Tokens.TypeScale.settingsHeading
        title.textColor = Tokens.Text.primary
        let text = NSTextField(wrappingLabelWithString: String(localized: """
        Paste a link from the Chrome Web Store above, or choose one you have on this Mac. \
        It runs in the Space you are in; pin it to put its button on the bar.
        """))
        text.font = Tokens.TypeScale.settingsCaption
        text.textColor = Tokens.Text.secondary
        text.alignment = .center
        let stack = NSStackView(views: [glyph, title, text])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = Tokens.Metric.chromeGap
        stack.setCustomSpacing(Tokens.Metric.chromeGapWide / 2 + Tokens.Metric.chromeGap / 2, after: glyph)
        for view in [card, stack] as [NSView] { view.translatesAutoresizingMaskIntoConstraints = false }
        addSubview(card)
        card.addSubview(stack)
        let inset = Tokens.Metric.settingsGroupGap
        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: leadingAnchor),
            card.trailingAnchor.constraint(equalTo: trailingAnchor),
            card.topAnchor.constraint(equalTo: topAnchor),
            card.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: inset),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -inset),
            stack.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            text.widthAnchor.constraint(lessThanOrEqualTo: card.widthAnchor, constant: -2 * inset)
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel(title.stringValue + ". " + text.stringValue)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }
}
