//
//  ExtensionsPanelRow.swift
//  Luna
//
//  One extension in §16.4's pop-out: its icon, its name, its badge, a pin, and
//  the switch that turns it on or off in the window's Space.
//
//  The switch is where §3.2's site settings keep theirs — the row's end, with
//  the same inset — so the two pop-outs answer "is this on here?" in one place.
//  The pin stands just before it. Pinned, it stays, lit; unpinned it is an
//  offer, and only comes out under the pointer, so a list of switches is not
//  also a column of grey pins. Off, the row has nothing to pin and no action to
//  run, and its icon steps back as a closed tab's does (§3.4b).
//
//  The row is a list row, not a button (`CLAUDE.md`): the panel's one pill
//  slides onto it and it does not swell. The pin is `RowGlyphView`, the chip a
//  tab's close glyph is, and the switch is the system's.
//

import AppKit

@MainActor
final class ExtensionsPanelRow: NSView {

    var onHover: ((Bool) -> Void)?
    var onChoose: (() -> Void)?
    var onPin: ((Bool) -> Void)?
    var onSwitch: ((Bool) -> Void)?
    private(set) var isUnderPointer = false {
        didSet { if isUnderPointer != oldValue { showPin() } }
    }

    private(set) var item: ExtensionShelfItem
    let pin = RowGlyphView()
    let toggle: SystemSwitch
    private let icon = NSImageView()
    private let title = NSTextField(labelWithString: "")
    private let badge = ExtensionBadgeView()

    init(item: ExtensionShelfItem) {
        self.item = item
        toggle = SystemSwitch(isOn: item.isOn)
        super.init(frame: .zero)
        icon.contentTintColor = Tokens.Text.secondary
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.setAccessibilityElement(false)
        title.font = Tokens.TypeScale.sidebarRow
        title.lineBreakMode = .byTruncatingTail
        title.setAccessibilityElement(false)
        pin.onActivate = { [weak self] in
            guard let self else { return }
            onPin?(!self.item.isPinned)
        }
        toggle.translatesAutoresizingMaskIntoConstraints = true
        toggle.onChange = { [weak self] isOn in self?.onSwitch?(isOn) }
        for view in [icon, title, badge, pin, toggle] { addSubview(view) }
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        dress()
    }

    /// The same extension with something about it changed. In place, because
    /// the change is usually this row's own switch: a row built afresh while
    /// the switch was still sliding showed the new one already at its end,
    /// and turning an extension off read as a flash.
    func update(_ item: ExtensionShelfItem) {
        self.item = item
        if toggle.isOn != item.isOn { toggle.isOn = item.isOn }
        dress()
        needsLayout = true
    }

    private func dress() {
        icon.image = item.icon ?? ExtensionsSymbol.image
        icon.alphaValue = item.isOn ? 1 : Tokens.Metric.dormantIconOpacity
        title.stringValue = item.name
        title.textColor = item.isOn ? Tokens.Text.primary : Tokens.Text.secondary
        badge.text = item.isOn ? item.badge : ""
        pin.configure(
            symbolName: item.isPinned ? "pin.fill" : "pin",
            label: item.isPinned ? String(localized: "Unpin from the Bar") : String(localized: "Pin to the Bar")
        )
        pin.tint = item.isPinned ? Tokens.Text.primary : Tokens.Text.tertiary
        toggle.setAccessibilityLabel(String(localized: "\(item.name) on in this Space"))
        showPin()
        // Known not to work here: the row says why under the pointer, and
        // Settings says it on the card.
        toolTip = ExtensionCompatibility.blocker(for: item.id)
        setAccessibilityLabel(item.badge.isEmpty ? item.name : "\(item.name), \(item.badge)")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    private func showPin() {
        pin.isHidden = !item.isOn || !(item.isPinned || isUnderPointer)
    }

    override func layout() {
        super.layout()
        Tokens.Motion.immediately { placeContents() }
    }

    private func placeContents() {
        let size = Tokens.Metric.faviconSize
        icon.frame = NSRect(x: SiteSettingsMetrics.glyphX, y: (bounds.height - size) / 2, width: size, height: size)

        // `SiteSettingsRow`'s switch, to the point.
        let switchSize = toggle.intrinsicContentSize
        let switchInset = (Tokens.Metric.rowPillHeight - switchSize.height) / 2
        let switchX = bounds.width - Tokens.Metric.rowInset - switchInset - switchSize.width
        toggle.frame = NSRect(
            x: switchX,
            y: (bounds.height - switchSize.height) / 2,
            width: switchSize.width,
            height: switchSize.height
        ).integral

        let chip = Tokens.Metric.rowTrailingChip
        let chipX = switchX - Tokens.Metric.rowIconGap / 2 - chip.width
        pin.frame = NSRect(x: chipX, y: (bounds.height - chip.height) / 2, width: chip.width, height: chip.height).integral
        var end = chipX - Tokens.Metric.rowIconGap / 2

        if !badge.isHidden {
            let badgeSize = badge.intrinsicContentSize
            badge.frame = NSRect(
                x: end - badgeSize.width,
                y: (bounds.height - badgeSize.height) / 2,
                width: badgeSize.width,
                height: badgeSize.height
            ).integral
            end = badge.frame.minX - Tokens.Metric.rowIconGap / 2
        }

        let height = title.intrinsicContentSize.height
        title.frame = NSRect(
            x: SiteSettingsMetrics.titleX,
            y: (bounds.height - height) / 2,
            width: max(end - SiteSettingsMetrics.titleX, 0),
            height: height
        ).integral
    }

    /// Runs it when it is on. Off, there is nothing to run, and the row does
    /// what its switch would: turns it on.
    func choose() {
        guard item.isOn else {
            toggle.isOn = true
            onSwitch?(true)
            return
        }
        onChoose?()
    }

    // MARK: - Menu

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        if item.isOn {
            let pinItem = NSMenuItem(
                title: item.isPinned ? String(localized: "Unpin from the Bar") : String(localized: "Pin to the Bar"),
                action: #selector(togglePin),
                keyEquivalent: ""
            )
            pinItem.target = self
            menu.addItem(pinItem)
        }
        let power = NSMenuItem(
            title: item.isOn ? String(localized: "Turn Off in This Space") : String(localized: "Turn On in This Space"),
            action: #selector(flip),
            keyEquivalent: ""
        )
        power.target = self
        menu.addItem(power)
        return menu
    }

    @objc private func togglePin() { onPin?(!item.isPinned) }
    @objc private func flip() { onSwitch?(!item.isOn) }

    // MARK: - Pointer

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let superview, frame.contains(point) else { return nil }
        let local = convert(point, from: superview)
        if toggle.frame.contains(local) { return toggle }
        if !pin.isHidden, pin.frame.contains(local) { return pin }
        return self
    }

    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        choose()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where area.owner === self { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        isUnderPointer = true
        onHover?(true)
    }

    override func mouseExited(with event: NSEvent) {
        isUnderPointer = false
        onHover?(false)
    }

    override func accessibilityPerformPress() -> Bool {
        choose()
        return true
    }
}
