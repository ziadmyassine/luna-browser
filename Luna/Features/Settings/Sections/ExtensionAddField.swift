//
//  ExtensionAddField.swift
//  Luna
//
//  The Chrome Web Store row at the top of Settings ▸ Extensions: a field to
//  paste the extension's page into, and Add beside it. Return adds as well.
//
//  It was a button that opened an alert with a field in it — a dialog to type
//  one line into, standing in front of the pane that was already showing.
//  The field is the pane's own now, and what went wrong is said under it,
//  where the user is already looking.
//

import AppKit

@MainActor
final class ExtensionAddField: NSView, NSTextFieldDelegate {

    /// Installs from the typed text; what came of it is said under the field.
    var onAdd: ((String) async -> ExtensionInstaller.Outcome)?

    let field = SettingsTextField(string: "")
    let add = SettingsPushButton(title: String(localized: "Add"), isDestructive: false)
    private let glyph = NSImageView()
    private let status = NSTextField(wrappingLabelWithString: "")
    private var statusGap: NSLayoutConstraint?
    private var isWorking = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        glyph.image = NSImage(systemSymbolName: "link", accessibilityDescription: nil)
        glyph.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: Tokens.Metric.pillGlyphSize, weight: .regular)
        glyph.contentTintColor = Tokens.Text.secondary
        field.placeholderString = String(localized: "Paste a link from the Chrome Web Store")
        field.delegate = self
        field.target = self
        field.action = #selector(submit)
        field.setAccessibilityLabel(String(localized: "Chrome Web Store link"))
        add.onActivate = { [weak self] in self?.submit() }
        status.font = Tokens.TypeScale.settingsCaption
        status.maximumNumberOfLines = 2
        status.isHidden = true
        build()
        refreshButton()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    private func build() {
        for view in [glyph, field, add, status] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        let inset = SettingsMetrics.cardInset
        let pad = SettingsMetrics.controlRowGap
        let gap = status.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -pad)
        statusGap = gap
        NSLayoutConstraint.activate([
            glyph.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            glyph.centerYAnchor.constraint(equalTo: field.centerYAnchor),
            glyph.widthAnchor.constraint(equalToConstant: Tokens.Metric.faviconSize),
            field.leadingAnchor.constraint(equalTo: glyph.trailingAnchor, constant: pad),
            field.topAnchor.constraint(equalTo: topAnchor, constant: pad),
            field.trailingAnchor.constraint(equalTo: add.leadingAnchor, constant: -pad),
            add.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            add.centerYAnchor.constraint(equalTo: field.centerYAnchor),
            status.leadingAnchor.constraint(equalTo: field.leadingAnchor),
            status.trailingAnchor.constraint(equalTo: add.trailingAnchor),
            status.topAnchor.constraint(equalTo: field.bottomAnchor, constant: Tokens.Metric.rowGap * 2),
            field.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -pad).withPriority(.defaultHigh),
            gap
        ])
        gap.isActive = false
    }

    // MARK: - Doing

    func controlTextDidChange(_ notification: Notification) {
        refreshButton()
        if !isWorking { show(nil) }
    }

    private func refreshButton() {
        add.isEnabled = !isWorking && !field.stringValue.trimmingCharacters(in: .whitespaces).isEmpty
    }

    @objc private func submit() {
        let text = field.stringValue
        guard !isWorking, !text.trimmingCharacters(in: .whitespaces).isEmpty, let onAdd else { return }
        isWorking = true
        refreshButton()
        show(String(localized: "Getting it from the Chrome Web Store…"), isError: false)
        Task { [weak self] in
            let outcome = await onAdd(text)
            guard let self else { return }
            isWorking = false
            switch outcome {
            case let .installed(name):
                field.stringValue = ""
                show(String(localized: "Added “\(name)”."), isError: false)
            case .cancelled:
                show(nil)
            case let .failed(reason):
                show(reason, isError: true)
            }
            refreshButton()
        }
    }

    /// One line under the field, or none: the row keeps its height otherwise.
    private func show(_ text: String?, isError: Bool = false) {
        status.stringValue = text ?? ""
        status.textColor = isError ? Tokens.Accent.danger : Tokens.Text.secondary
        status.isHidden = text == nil
        statusGap?.isActive = text != nil
    }
}

private extension NSLayoutConstraint {
    func withPriority(_ priority: NSLayoutConstraint.Priority) -> NSLayoutConstraint {
        self.priority = priority
        return self
    }
}
