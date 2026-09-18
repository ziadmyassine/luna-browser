//
//  SettingsRow.swift
//  Luna
//
//  §4's shared row widgets. **Every** control in every §3 section comes from
//  here; no section hand-rolls one, which is what keeps nine sections looking
//  like one window and makes §2's search, §4's disabled rule and §8's labelling
//  decisions taken once.
//
//  The popup stays AppKit's: §5 says never re-animate a system control, and a
//  hand-drawn menu would have to re-earn every keyboard and VoiceOver behaviour
//  it already ships. The button, the text field and the picker are drawn here
//  because their AppKit bezels are the only bright plates in an otherwise dark
//  pane — and the switch is drawn because AppKit's is a fixed 54 × 24 and there
//  is no room for it (`SettingsSwitch`).
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
        // `SettingsSwitch`, not `NSSwitch`: AppKit's is 54 × 24 at every
        // `controlSize` — measured — which is twice what this pane's controls
        // are built to. See the view.
        let toggle = SettingsSwitch(isOn: value)
        toggle.onChange = onChange
        return row(title, subtitle, toggle, isEnabled, disabledReason)
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
        segmentedPair(
            title,
            subtitle: subtitle,
            options: options,
            selected: selected,
            isEnabled: isEnabled,
            disabledReason: disabledReason,
            onChange: onChange
        ).row
    }

    /// `segmented`, with the control handed back as well.
    ///
    /// Rows are opaque `NSView`s everywhere else on purpose — a section that can
    /// reach into its own row can drift from what `SettingsRow` guarantees. The
    /// one exception is a choice whose **answers** change while the window is
    /// open: §3.2's tab position offers a middle segment under the top bar and
    /// two under the sidebar, and the row that decides which sits directly
    /// above it.
    static func segmentedPair(
        _ title: String,
        subtitle: String? = nil,
        options: [String],
        selected: Int,
        isEnabled: Bool = true,
        disabledReason: String? = nil,
        onChange: @escaping (Int) -> Void
    ) -> (row: NSView, choice: SettingsChoice) {
        // `SettingsChoice`, not `NSSegmentedControl`: the latter paints its
        // selection as a solid accent-blue block, which Luna's chrome never does.
        let control = SettingsChoice(labels: options)
        control.selectedIndex = clamp(selected, options.count)
        control.onSelect = onChange
        return (row(title, subtitle, control, isEnabled, disabledReason, terms: options), control)
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
        // Bare, not bezelled: six push bezels down a card turned the pane into
        // a form on a grey background. The value sits at the right of the row
        // with nothing under it, so the card stays one surface. The menu, the
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

    /// Commits on Return **and** on losing focus — without
    /// `sendsActionOnEndEditing` a user who types a custom engine and clicks
    /// straight back to the browser loses what they typed.
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

    /// A row that is only a sentence — an empty state, a count, a status line.
    /// Still a row: the same inset, height and hairline as any other. A bare
    /// `NSTextField` in a card sat against the card's edge and squashed it to
    /// one line of type.
    static func status(_ text: String) -> SettingsRowView {
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
    static func accessory(_ title: String, subtitle: String?, accessory: NSView) -> SettingsRowView {
        SettingsRowView(
            title: title,
            subtitle: subtitle,
            control: accessory,
            isEnabled: true,
            disabledReason: nil
        )
    }

    // MARK: - Prose and grouping

    /// §17.7's paragraph, and any other block of explanation. Plain text, not
    /// markdown — no caller passes anything but a sentence.
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

    /// A `selected:` computed from `firstIndex(of:) ?? 0` can still be out of
    /// range if the options changed under it, and AppKit throws for a bad index.
    private static func clamp(_ index: Int, _ count: Int) -> Int {
        guard count > 0 else { return 0 }
        return min(max(index, 0), count - 1)
    }
}

/// Turns an AppKit target/action pair back into the closure the caller passed.
/// `NSControl.target` is weak, so the row retains this — see
/// `SettingsRowView.retaining(_:)`.
@MainActor
final class SettingsAction: NSObject {

    private let run: (NSObject) -> Void

    init(_ run: @escaping (NSObject) -> Void) {
        self.run = run
    }

    @objc func fire(_ sender: NSObject) { run(sender) }
}
