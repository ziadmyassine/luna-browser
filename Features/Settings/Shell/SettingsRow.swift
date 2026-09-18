//
//  SettingsRow.swift
//  Luna
//
//  §4's shared row widgets. **Every** control in every §3 section comes from
//  here; no section hand-rolls one, which is what keeps nine sections looking
//  like one window and makes §2's search, §4's disabled rule and §8's labelling
//  decisions that were taken once.
//
//  The signatures are `SETTINGS-CONTRACT.md`'s, verbatim and frozen: agents B
//  and C compiled against them while this file was being written.
//
//  Controls are **stock AppKit** — `NSSwitch`, `NSSegmentedControl`,
//  `NSPopUpButton`, `NSTextField`, `NSButton`. §5 says never re-animate a system
//  control, and a hand-drawn switch would also have to re-earn every keyboard,
//  VoiceOver and Increase Contrast behaviour AppKit already ships.
//

import AppKit

@MainActor
enum SettingsRow {

    // MARK: - Controls

    static func toggle(
        _ title: String,
        subtitle: String? = nil,
        value: Bool,
        isEnabled: Bool = true,
        disabledReason: String? = nil,
        onChange: @escaping (Bool) -> Void
    ) -> NSView {
        let toggle = NSSwitch()
        toggle.state = value ? .on : .off
        let action = SettingsAction { sender in
            onChange((sender as? NSSwitch)?.state == .on)
        }
        toggle.target = action
        toggle.action = #selector(SettingsAction.fire(_:))
        return row(title, subtitle, toggle, isEnabled, disabledReason).retaining(action)
    }

    static func segmented(
        _ title: String,
        subtitle: String? = nil,
        options: [String],
        selected: Int,
        isEnabled: Bool = true,
        disabledReason: String? = nil,
        onChange: @escaping (Int) -> Void
    ) -> NSView {
        // `SettingsChoice`, not `NSSegmentedControl`: the latter paints its
        // selection as a solid accent-blue block, which is the one thing Luna's
        // chrome never does — selection here is the material.
        let control = SettingsChoice(labels: options)
        control.selectedIndex = clamp(selected, options.count)
        control.onSelect = onChange
        return row(title, subtitle, control, isEnabled, disabledReason, terms: options)
    }

    static func popup(
        _ title: String,
        subtitle: String? = nil,
        options: [String],
        selected: Int,
        isEnabled: Bool = true,
        disabledReason: String? = nil,
        onChange: @escaping (Int) -> Void
    ) -> NSView {
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.addItems(withTitles: options)
        popup.selectItem(at: clamp(selected, options.count))
        // **Bare, not bezelled.** AppKit's push bezel is a bright plate, and
        // six of them down a card turned the pane into a form on a grey
        // background — the reference puts the *value* on the right of the row
        // and nothing under it, so the card stays one surface. The menu, the
        // keyboard handling and the VoiceOver role are untouched.
        popup.isBordered = false
        popup.font = Tokens.TypeScale.settingsRow
        popup.contentTintColor = Tokens.Text.secondary
        let action = SettingsAction { sender in
            onChange((sender as? NSPopUpButton)?.indexOfSelectedItem ?? 0)
        }
        popup.target = action
        popup.action = #selector(SettingsAction.fire(_:))
        return row(title, subtitle, popup, isEnabled, disabledReason, terms: options).retaining(action)
    }

    /// Commits on Return **and** on losing focus.
    ///
    /// `NSCell.sendsActionOnEndEditing` is the second half: without it a user
    /// who types a custom engine and clicks straight back to the browser loses
    /// what they typed, which is the single most common way a settings text
    /// field is wrong.
    static func text(
        _ title: String,
        value: String,
        placeholder: String = "",
        isEnabled: Bool = true,
        disabledReason: String? = nil,
        onChange: @escaping (String) -> Void
    ) -> NSView {
        let field = SettingsTextField(string: value)
        field.placeholderString = placeholder
        field.cell?.sendsActionOnEndEditing = true
        field.widthAnchor.constraint(equalToConstant: Tokens.Metric.urlPill.width).isActive = true
        let action = SettingsAction { sender in
            onChange((sender as? NSTextField)?.stringValue ?? "")
        }
        field.target = action
        field.action = #selector(SettingsAction.fire(_:))
        return row(title, nil, field, isEnabled, disabledReason, terms: [placeholder]).retaining(action)
    }

    static func button(
        _ title: String,
        action: String,
        isDestructive: Bool = false,
        isEnabled: Bool = true,
        disabledReason: String? = nil,
        onTap: @escaping () -> Void
    ) -> NSView {
        let button = SettingsPushButton(title: action, isDestructive: isDestructive)
        button.onActivate = onTap
        return row(title, nil, button, isEnabled, disabledReason, terms: [action])
    }

    /// A row that is only a sentence — an empty state, a count, a line of
    /// status. **It is still a row**: the same card inset, the same minimum
    /// height and the same hairline above it as every other one. A bare
    /// `NSTextField` dropped into a card instead sat against the card's own
    /// edge and squashed the card to the height of one line of type, which is
    /// what "Sites with blocking turned off" looked like before this existed.
    static func status(_ text: String) -> NSView {
        SettingsRowView(
            title: text,
            subtitle: nil,
            control: nil,
            isEnabled: true,
            disabledReason: nil
        )
    }

    /// A row whose right-hand side is built by the section — a status line, a
    /// path control, a key-equivalent label.
    static func accessory(_ title: String, subtitle: String?, accessory: NSView) -> NSView {
        SettingsRowView(
            title: title,
            subtitle: subtitle,
            control: accessory,
            isEnabled: true,
            disabledReason: nil
        )
    }

    // MARK: - Prose and grouping

    /// §17.7's paragraph, and any other block of explanation.
    ///
    /// Plain text, not markdown: §4's sketch called the parameter
    /// `markdownish`, the contract settled on `text`, and no caller passes
    /// anything but a sentence. Named in the report rather than guessed at.
    static func note(_ text: String) -> NSView {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = Tokens.TypeScale.sidebarRow
        label.textColor = Tokens.Text.secondary
        label.isSelectable = true
        label.translatesAutoresizingMaskIntoConstraints = false

        let host = NSView()
        host.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: SettingsMetrics.controlRowGap),
            label.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -SettingsMetrics.controlRowGap),
            label.topAnchor.constraint(equalTo: host.topAnchor, constant: SettingsMetrics.controlRowGap),
            label.bottomAnchor.constraint(equalTo: host.bottomAnchor, constant: -SettingsMetrics.controlRowGap)
        ])
        return host
    }

    /// §1's glass-backed card of rows, with an optional label above it.
    static func group(_ title: String?, _ rows: [NSView]) -> NSView {
        SettingsRowGroupView(title: title, rows: rows)
    }

    // MARK: - Construction

    private static func row(
        _ title: String,
        _ subtitle: String?,
        _ control: NSView,
        _ isEnabled: Bool,
        _ disabledReason: String?,
        terms: [String] = []
    ) -> SettingsRowView {
        SettingsRowView(
            title: title,
            subtitle: subtitle,
            control: control,
            isEnabled: isEnabled,
            disabledReason: disabledReason,
            extraTerms: terms
        )
    }

    /// A `selected:` a section computed from a `firstIndex(of:) ?? 0` can still
    /// be out of range if the options list changed under it; AppKit throws for
    /// a bad segment index rather than ignoring it.
    private static func clamp(_ index: Int, _ count: Int) -> Int {
        guard count > 0 else { return 0 }
        return min(max(index, 0), count - 1)
    }
}

/// Turns an AppKit target/action pair back into the closure the caller passed.
///
/// `NSControl.target` is **weak**, so this is retained by the row it belongs to
/// — see `SettingsRowView.retain(_:)`. Without that the closure dies before the
/// first click and the control silently does nothing.
@MainActor
final class SettingsAction: NSObject {

    private let run: (NSObject) -> Void

    init(_ run: @escaping (NSObject) -> Void) {
        self.run = run
    }

    @objc func fire(_ sender: NSObject) { run(sender) }
}
