//
//  ExtensionDetailsView.swift
//  Luna
//
//  One installed extension in full, opened from its card's Details button:
//  everything it says it does, everything it may reach, a switch for each
//  Space, and what else can be done with it. The card is a glance, and two
//  lines of description and one line of access are what a glance leaves out.
//
//  A switch per Space, where the card had a button reading "Off everywhere"
//  that opened a menu of ticks. A tick in a menu is a state you read by
//  opening it; a row of switches is the site settings pop-out's answer to the
//  same question, and it can be read at once.
//

import AppKit
import BrowserKit

@MainActor
final class ExtensionDetailsView: NSView {

    struct Model {
        let info: ExtensionInfo
        let spaces: [Space]
        /// Why it cannot work in Luna, in full — see `ExtensionCompatibility`.
        let blocker: String?
        let setOn: (Bool, UUID) -> Void
        let actions: [Action]
    }

    struct Action {
        let title: String
        let isDestructive: Bool
        let run: () -> Void
    }

    /// Internal so tests can reach them.
    private(set) var switches: [UUID: SystemSwitch] = [:]
    private(set) var buttons: [SettingsPushButton] = []

    private let column = NSStackView()
    private var textWidth: CGFloat { Tokens.Metric.siteSettingsPanel - 2 * SettingsMetrics.cardInset }

    init(_ model: Model) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let pad = SettingsMetrics.cardInset
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = Tokens.Metric.chromeGap
        column.edgeInsets = NSEdgeInsets(top: pad, left: pad, bottom: pad, right: pad)
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Tokens.Metric.siteSettingsPanel),
            column.leadingAnchor.constraint(equalTo: leadingAnchor),
            column.trailingAnchor.constraint(equalTo: trailingAnchor),
            column.topAnchor.constraint(equalTo: topAnchor),
            column.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        add(head(model.info))
        let details = model.info.details
        add(paragraph(
            details.map { $0.summary.isEmpty ? String(localized: "No description.") : $0.summary }
                ?? String(localized: "Luna couldn’t read this extension’s files."),
            colour: Tokens.Text.secondary
        ))
        if let blocker = model.blocker { add(paragraph(blocker, colour: Tokens.Accent.danger)) }

        section(String(localized: "Can"))
        for line in Self.access(model.info) { add(paragraph(line, colour: Tokens.Text.primary)) }
        if let unsupported = details?.unsupportedPermissions, !unsupported.isEmpty {
            add(paragraph(
                String(localized: "Also asks for \(unsupported.joined(separator: ", ")), which Luna doesn’t support."),
                colour: Tokens.Text.tertiary
            ))
        }

        if !model.spaces.isEmpty {
            section(String(localized: "On in"))
            for space in model.spaces { add(spaceRow(space, model: model)) }
        }

        if !model.actions.isEmpty {
            column.setCustomSpacing(Tokens.Metric.chromeGapWide, after: column.arrangedSubviews.last ?? column)
            add(actionRow(model.actions))
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    // MARK: - Pieces

    private func add(_ view: NSView) {
        column.addArrangedSubview(view)
        view.widthAnchor.constraint(equalToConstant: textWidth).isActive = true
    }

    private func head(_ info: ExtensionInfo) -> NSView {
        let icon = NSImageView()
        icon.image = info.details?.iconData.flatMap(NSImage.init(data:)) ?? ExtensionsSymbol.image
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.contentTintColor = Tokens.Text.secondary
        let name = NSTextField(wrappingLabelWithString: info.details?.name ?? info.id)
        name.font = Tokens.TypeScale.settingsHeading
        name.textColor = Tokens.Text.primary
        let detail = NSTextField(labelWithString: ExtensionCardView.detail(info))
        detail.font = Tokens.TypeScale.settingsCaption
        detail.textColor = Tokens.Text.secondary
        let words = NSStackView(views: [name, detail])
        words.orientation = .vertical
        words.alignment = .leading
        words.spacing = Tokens.Metric.rowGap
        let row = NSStackView(views: [icon, words])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = Tokens.Metric.chromeGap + Tokens.Metric.rowGap
        let side = Tokens.Metric.extensionCardIcon
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: side),
            icon.heightAnchor.constraint(equalToConstant: side)
        ])
        name.preferredMaxLayoutWidth = textWidth - side - row.spacing
        return row
    }

    private func paragraph(_ string: String, colour: NSColor) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: string)
        label.font = Tokens.TypeScale.settingsCaption
        label.textColor = colour
        label.isSelectable = false
        label.preferredMaxLayoutWidth = textWidth
        return label
    }

    /// A hairline, then the section's name: the popover's groups are ruled
    /// the way a card's rows are.
    private func section(_ title: String) {
        column.setCustomSpacing(Tokens.Metric.chromeGapWide / 2 + Tokens.Metric.rowGap, after: column.arrangedSubviews.last ?? column)
        add(SettingsRuleView())
        let label = NSTextField(labelWithString: title)
        label.font = Tokens.TypeScale.settingsCaption
        label.textColor = Tokens.Text.tertiary
        add(label)
    }

    private func spaceRow(_ space: Space, model: Model) -> NSView {
        let glyph = NSImageView()
        glyph.image = NSImage(systemSymbolName: space.symbolName, accessibilityDescription: nil)
        glyph.contentTintColor = Tokens.Text.secondary
        let name = NSTextField(labelWithString: space.name)
        name.font = Tokens.TypeScale.settingsRow
        name.textColor = Tokens.Text.primary
        name.lineBreakMode = .byTruncatingTail
        name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let toggle = SystemSwitch(isOn: model.info.enabledSpaces.contains(space.id))
        toggle.setAccessibilityLabel(String(localized: "On in \(space.name)"))
        toggle.onChange = { isOn in model.setOn(isOn, space.id) }
        switches[space.id] = toggle
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow - 1, for: .horizontal)
        let row = NSStackView(views: [glyph, name, spacer, toggle])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = Tokens.Metric.chromeGap
        glyph.widthAnchor.constraint(equalToConstant: Tokens.Metric.faviconSize).isActive = true
        return row
    }

    private func actionRow(_ actions: [Action]) -> NSView {
        // The one that removes stands apart at the far end, as the quit
        // sheet's permanent answer does: it is not one of the ordinary ones.
        let ordinary = actions.filter { !$0.isDestructive }.map(button)
        let destructive = actions.filter(\.isDestructive).map(button)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow - 1, for: .horizontal)
        let row = NSStackView(views: ordinary + [spacer] + destructive)
        row.orientation = .horizontal
        row.spacing = Tokens.Metric.chromeGap
        return row
    }

    private func button(_ action: Action) -> SettingsPushButton {
        let button = SettingsPushButton(title: action.title, isDestructive: action.isDestructive)
        button.onActivate = action.run
        buttons.append(button)
        return button
    }

    // MARK: - Words

    /// Everything it may do, in the install prompt's sentences, from what the
    /// user granted rather than what it asked for.
    static func access(_ info: ExtensionInfo) -> [String] {
        guard let details = info.details else { return [String(localized: "Nothing while it isn’t running.")] }
        let granted = info.grants.values.first
        let patterns = granted.map { Array($0.grantedPatterns) } ?? details.hostPatterns
        let permissions = granted.map { Array($0.grantedPermissions) } ?? details.permissions
        let lines = ExtensionPermissionText.lines(permissions: permissions.sorted(), hostPatterns: patterns.sorted())
        return lines.isEmpty ? [String(localized: "Nothing that needs your permission.")] : lines
    }
}
