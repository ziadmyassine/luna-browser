//
//  ExtensionCard.swift
//  Luna
//
//  One installed extension in Settings ▸ Extensions, as a small card: two
//  stand side by side, so a handful of extensions is a glance rather than a
//  scroll.
//
//  Headed by the extension's own face, as §3.7's Space card is headed by the
//  Space's gradient: a list of extensions is found by looking at it. Under the
//  head, what it says it does, what it can reach, and one line of controls —
//  Details, which opens the rest (`ExtensionDetailsView`), its pin, and a menu.
//  The switches and rows a card used to carry made each extension a page tall.
//

import AppKit
import BrowserKit

@MainActor
final class ExtensionCardView: NSView {

    struct Model {
        let info: ExtensionInfo
        let isPinned: Bool
        let isOnHere: Bool
        /// The name of the Space the front window shows, for the switch's label.
        let hereName: String
        let setOnHere: (Bool) -> Void
        /// Why it cannot work in Luna, in a few words, when that is known —
        /// the whole reason is in Details. See `ExtensionCompatibility`.
        let blocker: String?
        let showDetails: (NSView) -> Void
        let moreMenu: () -> NSMenu
        let setPinned: (Bool) -> Void
    }

    private let card = SettingsCardView()
    private let icon = NSImageView()
    private let name = NSTextField(labelWithString: "")
    private let detail = NSTextField(labelWithString: "")
    private let summary = NSTextField(wrappingLabelWithString: "")
    private let access = NSTextField(labelWithString: "")
    private let accessGlyph = NSImageView()
    /// On or off in the Space the front window shows — the pop-out's switch.
    /// Every other Space is in the Spaces menu on the card's foot.
    let toggle: SystemSwitch
    let detailsButton = ExtensionCardButton(symbol: "info.circle", title: String(localized: "Details"), label: String(localized: "Details"))
    let pin: ExtensionCardButton
    let more = ExtensionCardButton(symbol: "ellipsis", label: String(localized: "More"))

    init(_ model: Model) {
        toggle = SystemSwitch(isOn: model.isOnHere)
        pin = ExtensionCardButton(
            symbol: model.isPinned ? "pin.fill" : "pin",
            label: model.isPinned ? String(localized: "Unpin from the Bar") : String(localized: "Pin to the Bar")
        )
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        card.translatesAutoresizingMaskIntoConstraints = false
        addSubview(card)
        dress(model)
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    /// The same extension with something about it changed. In place, because
    /// the change is usually this card's own switch: a card built afresh while
    /// the switch was still sliding showed the new one already at its end, and
    /// turning an extension off read as a flash.
    func update(_ model: Model) {
        if toggle.isOn != model.isOnHere { toggle.isOn = model.isOnHere }
        pin.setSymbol(model.isPinned ? "pin.fill" : "pin")
        let pinLabel = model.isPinned ? String(localized: "Unpin from the Bar") : String(localized: "Pin to the Bar")
        pin.toolTip = pinLabel
        pin.setAccessibilityLabel(pinLabel)
        dress(model)
    }

    private func dress(_ model: Model) {
        let details = model.info.details
        icon.image = details?.iconData.flatMap(NSImage.init(data:)) ?? ExtensionsSymbol.image
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.contentTintColor = Tokens.Text.secondary
        // Off in this Space, the face steps back as a closed tab's does
        // (§3.4b): still there to turn on, not one of those running around you.
        icon.alphaValue = model.isOnHere ? 1 : Tokens.Metric.dormantIconOpacity
        name.stringValue = details?.name ?? model.info.id
        name.font = Tokens.TypeScale.settingsHeading
        name.textColor = Tokens.Text.primary
        name.lineBreakMode = .byTruncatingTail
        detail.stringValue = Self.detail(model.info)
        detail.font = Tokens.TypeScale.settingsCaption
        detail.textColor = Tokens.Text.secondary
        detail.lineBreakMode = .byTruncatingTail
        summary.stringValue = details.map { $0.summary.isEmpty ? String(localized: "No description.") : $0.summary }
            ?? String(localized: "Luna couldn’t read this extension’s files.")
        summary.font = Tokens.TypeScale.settingsCaption
        summary.textColor = Tokens.Text.secondary
        summary.maximumNumberOfLines = 2
        summary.lineBreakMode = .byWordWrapping
        summary.cell?.truncatesLastVisibleLine = true
        accessGlyph.image = NSImage(systemSymbolName: "globe", accessibilityDescription: nil)
        accessGlyph.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: Tokens.Metric.pillGlyphSize - 2, weight: .regular)
        accessGlyph.contentTintColor = Tokens.Text.tertiary
        access.stringValue = model.blocker ?? Self.access(model.info)
        access.font = Tokens.TypeScale.settingsCaption
        access.textColor = model.blocker == nil ? Tokens.Text.tertiary : Tokens.Accent.danger
        access.maximumNumberOfLines = 1
        access.lineBreakMode = .byTruncatingTail
        if model.blocker != nil {
            accessGlyph.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: nil)
            accessGlyph.contentTintColor = Tokens.Accent.danger
        }
        wire(model)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel([name.stringValue, detail.stringValue].joined(separator: ", "))
    }

    /// The controls on the card's head and foot.
    private func wire(_ model: Model) {
        toggle.onChange = model.setOnHere
        toggle.setAccessibilityLabel(String(localized: "On in \(model.hereName)"))
        toggle.toolTip = String(localized: "On in \(model.hereName)")
        detailsButton.onActivate = { [weak self] in
            guard let self else { return }
            model.showDetails(detailsButton)
        }
        pin.isOn = model.isPinned
        pin.onActivate = { model.setPinned(!model.isPinned) }
        more.menuBuilder = { [weak self] in
            let menu = model.moreMenu()
            guard let self else { return menu }
            let open = MenuAction.item(String(localized: "Details…")) { [weak self] in
                guard let self else { return }
                model.showDetails(detailsButton)
            }
            menu.insertItem(.separator(), at: 0)
            menu.insertItem(open, at: 0)
            return menu
        }
    }

    private func build() {
        let views: [NSView] = [icon, name, detail, summary, accessGlyph, access, toggle, detailsButton, pin, more]
        for view in views {
            view.translatesAutoresizingMaskIntoConstraints = false
            card.addSubview(view)
        }
        for label in [name, detail, summary, access] {
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        let inset = SettingsMetrics.cardInset
        let gap = Tokens.Metric.chromeGap
        let side = Tokens.Metric.extensionCardIcon
        let lineGap = Tokens.Metric.rowGap
        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: leadingAnchor),
            card.trailingAnchor.constraint(equalTo: trailingAnchor),
            card.topAnchor.constraint(equalTo: topAnchor),
            card.bottomAnchor.constraint(equalTo: bottomAnchor),

            icon.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: inset),
            icon.topAnchor.constraint(equalTo: card.topAnchor, constant: inset),
            icon.widthAnchor.constraint(equalToConstant: side),
            icon.heightAnchor.constraint(equalToConstant: side),
            name.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: gap + lineGap),
            name.trailingAnchor.constraint(lessThanOrEqualTo: toggle.leadingAnchor, constant: -gap),
            toggle.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -inset),
            toggle.centerYAnchor.constraint(equalTo: icon.centerYAnchor),
            name.bottomAnchor.constraint(equalTo: icon.centerYAnchor, constant: lineGap / 2),
            detail.leadingAnchor.constraint(equalTo: name.leadingAnchor),
            detail.trailingAnchor.constraint(lessThanOrEqualTo: toggle.leadingAnchor, constant: -gap),
            detail.topAnchor.constraint(equalTo: icon.centerYAnchor, constant: lineGap / 2),

            summary.leadingAnchor.constraint(equalTo: icon.leadingAnchor),
            summary.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -inset),
            summary.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: gap + lineGap),

            accessGlyph.leadingAnchor.constraint(equalTo: icon.leadingAnchor),
            accessGlyph.firstBaselineAnchor.constraint(equalTo: access.firstBaselineAnchor),
            accessGlyph.widthAnchor.constraint(equalToConstant: Tokens.Metric.pillGlyphSize),
            access.leadingAnchor.constraint(equalTo: accessGlyph.trailingAnchor, constant: lineGap * 2),
            access.trailingAnchor.constraint(lessThanOrEqualTo: card.trailingAnchor, constant: -inset),
            access.topAnchor.constraint(greaterThanOrEqualTo: summary.bottomAnchor, constant: gap),

            // The controls stand on the card's foot, so two cards side by side
            // line theirs up whatever their descriptions run to.
            detailsButton.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: inset - SettingsMetrics.controlInset / 2),
            detailsButton.topAnchor.constraint(equalTo: access.bottomAnchor, constant: gap),
            detailsButton.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -(inset - SettingsMetrics.controlInset / 2)),
            detailsButton.trailingAnchor.constraint(lessThanOrEqualTo: pin.leadingAnchor, constant: -lineGap),
            more.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -(inset - SettingsMetrics.controlInset / 2)),
            more.centerYAnchor.constraint(equalTo: detailsButton.centerYAnchor),
            pin.trailingAnchor.constraint(equalTo: more.leadingAnchor, constant: -lineGap),
            pin.centerYAnchor.constraint(equalTo: detailsButton.centerYAnchor)
        ])
    }

    /// "1.4 · Chrome Web Store". The number alone: with the word "Version"
    /// in front, the source was cut off on a card half the pane wide.
    static func detail(_ info: ExtensionInfo) -> String {
        let source = switch info.source {
        case .webStore: String(localized: "Chrome Web Store")
        case .local: String(localized: "From a file")
        }
        guard let version = info.details?.version, !version.isEmpty else { return source }
        return version + " · " + source
    }

    /// Where it can reach, from what the user granted at install.
    static func access(_ info: ExtensionInfo) -> String {
        guard let details = info.details else { return String(localized: "Not running") }
        let patterns = info.grants.values.first.map { Array($0.grantedPatterns) } ?? details.hostPatterns
        return ExtensionPermissionText.siteSummary(patterns.sorted())
    }
}
