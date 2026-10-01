//
//  HistoryDayHeaderView.swift
//  Luna
//
//  The label over one day's pages in §6.4's list (§11.3). Not a row: nothing
//  happens when it is clicked or hovered, the pill never lands on it, and it
//  is not counted among the pages.
//

import AppKit

@MainActor
final class HistoryDayHeaderView: NSView {

    private let label = NSTextField(labelWithString: "")

    /// Built empty and filled by `configure`, because `HistoryListView`
    /// recycles these as it does its rows.
    init() {
        super.init(frame: .zero)
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        // In line with the rows' favicons, and on the header's foot so the
        // `panelInset` above it is the gap from the day before.
        let inset = Tokens.Metric.rowInset + Tokens.Metric.panelInset
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -inset),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Tokens.Metric.rowGap)
        ])
        applyTokens()
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(accessibilityDisplayOptionsChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    var title: String { label.stringValue }

    func configure(_ day: String) {
        label.stringValue = day
        setAccessibilityLabel(day)
    }

    @objc private func accessibilityDisplayOptionsChanged() {
        applyTokens()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyTokens()
    }

    private func applyTokens() {
        label.font = Tokens.TypeScale.sectionLabel
        label.textColor = Tokens.Text.tertiary
    }

    /// The panel's scrim closes the pop-out on a press, and a press on a
    /// header is still a press inside the panel.
    override func mouseDown(with event: NSEvent) {}
}
