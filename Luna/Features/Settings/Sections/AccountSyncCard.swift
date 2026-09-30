//
//  AccountSyncCard.swift
//  Luna
//
//  The iCloud page's Sync card: the master switch with what it is for, the
//  five zones as a checklist under it, and the status with Sync Now at its
//  foot. One card rather than three, because they are one decision: whether
//  to sync, what, and how it is going.
//
//  The zones are checks, not five more switches: a column of six switches
//  read as six equal decisions, where five of them are parts of the first.
//

import AppKit
import BrowserKit

@MainActor
final class AccountSyncCard: NSView {

    let header = NSView()
    let syncSwitch: SystemSwitch
    private(set) var zoneRows: [SyncZoneCheckRow] = []
    let footer = NSView()
    let syncNow = SettingsPushButton(title: String(localized: "Sync Now"), isDestructive: false)
    let statusLine = NSTextField(labelWithString: "")
    private let dot = NSView()
    private let zones = NSStackView()
    private weak var sync: SyncSettings?
    /// What the user just set the switch to, until sync says the same. The
    /// status moves ("Syncing…") before the zones are written, and an update
    /// read in between would throw the switch back mid-animation.
    private var pending: Bool?
    private var pendingExpiry: Task<Void, Never>?

    init(sync: SyncSettings) {
        self.sync = sync
        syncSwitch = SystemSwitch(isOn: sync.isOn)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        syncSwitch.setAccessibilityLabel(String(localized: "Sync with iCloud"))
        syncSwitch.onChange = { [weak self, sync] on in
            self?.expect(on)
            sync.setEnabled(on)
        }
        buildHeader()

        zoneRows = SyncZone.switched.map { zone in
            let row = SyncZoneCheckRow(title: zone.title, detail: "", isOn: false)
            row.onChange = { [sync] on in sync.setZone(zone, on) }
            return row
        }
        syncNow.onActivate = { [sync] in sync.syncNow() }
        buildFooter()

        let caption = NSTextField(labelWithString: String(localized: "What syncs"))
        caption.font = Tokens.TypeScale.settingsCaption
        caption.textColor = Tokens.Text.secondary
        zones.setViews(zoneRows, in: .top)
        zones.orientation = .vertical
        zones.spacing = 0
        update(animated: false)

        lay(caption: caption, zones: zones)
    }

    /// Header, rule, caption, checklist and footer, top to bottom. The rule
    /// runs to the card's edges; the checklist sits half an inset in, so a
    /// check's plate has room round it and its disc lines up with the text.
    private func lay(caption: NSView, zones: NSView) {
        let inset = SettingsMetrics.cardInset
        let parts: [(NSView, CGFloat)] = [(header, inset), (SettingsRuleView(), 0), (caption, inset), (zones, inset / 2), (footer, inset)]
        for (view, _) in parts {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        var constraints: [NSLayoutConstraint] = []
        for (view, side) in parts {
            constraints += [
                view.leadingAnchor.constraint(equalTo: leadingAnchor, constant: side),
                view.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -side)
            ]
        }
        let rule = parts[1].0
        constraints += zoneRows.map { $0.widthAnchor.constraint(equalTo: zones.widthAnchor) } + [
            header.topAnchor.constraint(equalTo: topAnchor, constant: inset),
            rule.topAnchor.constraint(equalTo: header.bottomAnchor, constant: inset),
            caption.topAnchor.constraint(equalTo: rule.bottomAnchor, constant: inset),
            zones.topAnchor.constraint(equalTo: caption.bottomAnchor, constant: Tokens.Metric.chromeGap / 2),
            footer.topAnchor.constraint(equalTo: zones.bottomAnchor, constant: Tokens.Metric.chromeGap),
            footer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -inset)
        ]
        NSLayoutConstraint.activate(constraints)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    /// How far the checklist fades while sync is off: still legible, so the
    /// user can see what turning it on would sync.
    static let restingAlpha: CGFloat = 0.45

    private func buildHeader() {
        let tile = SettingsSymbolTile(symbolName: "icloud", style: .symbol(Tokens.Tile.blue), side: Tokens.Metric.settingsCardTile)
        let title = NSTextField(labelWithString: String(localized: "Sync with iCloud"))
        title.font = Tokens.TypeScale.settingsHeading
        title.textColor = Tokens.Text.primary
        let line = NSTextField(labelWithString: String(localized: "Keep Luna the same on every Mac you use."))
        line.font = Tokens.TypeScale.settingsCaption
        line.textColor = Tokens.Text.secondary
        line.lineBreakMode = .byTruncatingTail
        let words = NSStackView(views: [title, line])
        words.orientation = .vertical
        words.alignment = .leading
        words.spacing = 2
        for view in [tile, words, syncSwitch] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            header.addSubview(view)
        }
        NSLayoutConstraint.activate([
            tile.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            tile.topAnchor.constraint(equalTo: header.topAnchor),
            tile.bottomAnchor.constraint(equalTo: header.bottomAnchor),
            words.leadingAnchor.constraint(equalTo: tile.trailingAnchor, constant: SettingsMetrics.controlInset),
            words.centerYAnchor.constraint(equalTo: tile.centerYAnchor),
            words.trailingAnchor.constraint(lessThanOrEqualTo: syncSwitch.leadingAnchor, constant: -SettingsMetrics.controlRowGap),
            syncSwitch.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            syncSwitch.centerYAnchor.constraint(equalTo: tile.centerYAnchor)
        ])
    }

    private func buildFooter() {
        let side = Tokens.Metric.settingsStatusDot
        dot.wantsLayer = true
        dot.layer?.cornerRadius = side / 2
        let line = statusLine
        line.font = Tokens.TypeScale.settingsCaption
        line.textColor = Tokens.Text.secondary
        line.lineBreakMode = .byTruncatingTail
        line.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        for view in [dot, line, syncNow] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            footer.addSubview(view)
        }
        NSLayoutConstraint.activate([
            dot.leadingAnchor.constraint(equalTo: footer.leadingAnchor),
            dot.centerYAnchor.constraint(equalTo: syncNow.centerYAnchor),
            dot.widthAnchor.constraint(equalToConstant: side),
            dot.heightAnchor.constraint(equalToConstant: side),
            line.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: Tokens.Metric.chromeGap),
            line.centerYAnchor.constraint(equalTo: syncNow.centerYAnchor),
            line.trailingAnchor.constraint(lessThanOrEqualTo: syncNow.leadingAnchor, constant: -SettingsMetrics.controlRowGap),
            syncNow.trailingAnchor.constraint(equalTo: footer.trailingAnchor),
            syncNow.topAnchor.constraint(equalTo: footer.topAnchor),
            syncNow.bottomAnchor.constraint(equalTo: footer.bottomAnchor)
        ])
    }

    // MARK: - State

    /// Brings the card to what sync says now, in place: the switch is never
    /// rebuilt under the user's finger, which is what made it stutter.
    func update(animated: Bool = true) {
        guard let sync else { return }
        if let pending, pending == sync.isOn { self.pending = nil }
        let isOn = pending ?? sync.isOn
        let available = sync.status != .needsSignedBuild
        syncSwitch.isEnabled = available
        syncSwitch.toolTip = available ? nil : sync.status.line()
        if syncSwitch.isOn != isOn { syncSwitch.isOn = isOn }

        for (zone, row) in zip(SyncZone.switched, zoneRows) {
            // While the switch is on its way, the checks show what turning it
            // on does: every zone, as `setEnabled` asks for.
            let chosen = pending == true ? true : sync.zones.contains(zone)
            let needsSpaces = zone == .history && !(pending == true || sync.zones.contains(.spaces))
            row.setOn(chosen && !needsSpaces)
            row.isEnabled = isOn && !needsSpaces
            row.detail.stringValue = zone.detail(needsSpaces: isOn && needsSpaces)
        }
        let alpha = isOn ? 1 : Self.restingAlpha
        if animated, !Tokens.Motion.reduceMotion {
            Tokens.Motion.animate(Tokens.Motion.controlHover) { _ in self.zones.animator().alphaValue = alpha }
        } else {
            zones.alphaValue = alpha
        }

        syncNow.isEnabled = sync.isOn
        statusLine.stringValue = sync.status.line()
        effectiveAppearance.performAsCurrentDrawingAppearance {
            self.dot.layer?.backgroundColor = sync.status.dotColour.cgColor
        }
    }

    /// The switch was moved to `on`: show it at once, and give sync a few
    /// seconds to agree before the card goes back to what sync says.
    private func expect(_ on: Bool) {
        pending = on
        update()
        pendingExpiry?.cancel()
        pendingExpiry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.pendingPatience))
            guard !Task.isCancelled else { return }
            self?.pending = nil
            self?.update()
        }
    }

    /// How long a flip of the switch is shown before sync has answered it.
    /// Turning sync on writes the zones and asks iCloud once; a few seconds
    /// covers that on a slow connection, and a failure then shows as off.
    static let pendingPatience: TimeInterval = 5

    /// The line under the card: what never leaves this Mac, with a lock.
    static func cookieNote(_ text: String) -> NSView {
        let lock = NSImageView(image: NSImage(systemSymbolName: "lock.fill", accessibilityDescription: nil) ?? NSImage())
        lock.symbolConfiguration = .init(pointSize: Tokens.TypeScale.settingsCaption.pointSize, weight: .medium)
        lock.contentTintColor = Tokens.Text.tertiary
        let label = NSTextField(labelWithString: text)
        label.font = Tokens.TypeScale.settingsCaption
        label.textColor = Tokens.Text.tertiary
        let host = NSView()
        for view in [lock, label] {
            view.translatesAutoresizingMaskIntoConstraints = false
            host.addSubview(view)
        }
        NSLayoutConstraint.activate([
            lock.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            lock.centerYAnchor.constraint(equalTo: label.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: lock.trailingAnchor, constant: Tokens.Metric.chromeGap / 2),
            label.trailingAnchor.constraint(lessThanOrEqualTo: host.trailingAnchor),
            label.topAnchor.constraint(equalTo: host.topAnchor),
            label.bottomAnchor.constraint(equalTo: host.bottomAnchor)
        ])
        return host
    }
}

/// One zone of the Sync card: a check disc, the zone's name, and why it is
/// off when that is not the user's doing.
///
/// A row in a card, not a list row in the sidebar's sense: the plate washes
/// under the pointer and the press, and the disc, which is the thing being
/// set, swells under the press (CLAUDE.md, "Buttons answer").
@MainActor
final class SyncZoneCheckRow: NSView {

    var onChange: ((Bool) -> Void)?

    private(set) var isOn: Bool
    var isEnabled = true { didSet { refresh() } }

    let disc = NSView()
    private let tick = NSImageView()
    private let title: NSTextField
    let detail: NSTextField
    private var isHovering = false { didSet { if isHovering != oldValue { refresh() } } }
    private var isPressed = false {
        didSet {
            guard isPressed != oldValue else { return }
            refresh()
            Tokens.Motion.swell(disc, to: isPressed ? Tokens.Motion.pressSwell : 1)
        }
    }

    init(title: String, detail: String, isOn: Bool) {
        self.isOn = isOn
        self.title = NSTextField(labelWithString: title)
        self.detail = NSTextField(labelWithString: detail)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.cornerRadius = Tokens.Metric.settingsControlCorner

        let side = Tokens.Metric.settingsCheckDisc
        disc.wantsLayer = true
        disc.layer?.cornerRadius = side / 2
        tick.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)
        tick.symbolConfiguration = .init(pointSize: side / 2, weight: .bold)
        tick.contentTintColor = Tokens.Accent.onTint
        disc.addSubview(tick)
        self.title.font = Tokens.TypeScale.settingsRow
        self.detail.font = Tokens.TypeScale.settingsCaption
        self.detail.textColor = Tokens.Text.tertiary

        for view in [disc, tick, self.title, self.detail] {
            view.translatesAutoresizingMaskIntoConstraints = false
        }
        for view in [disc, self.title, self.detail] { addSubview(view) }
        let inset = SettingsMetrics.cardInset / 2
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: Tokens.Metric.settingsControl + inset / 2),
            disc.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            disc.centerYAnchor.constraint(equalTo: centerYAnchor),
            disc.widthAnchor.constraint(equalToConstant: side),
            disc.heightAnchor.constraint(equalToConstant: side),
            tick.centerXAnchor.constraint(equalTo: disc.centerXAnchor),
            tick.centerYAnchor.constraint(equalTo: disc.centerYAnchor),
            self.title.leadingAnchor.constraint(equalTo: disc.trailingAnchor, constant: SettingsMetrics.controlInset),
            self.title.centerYAnchor.constraint(equalTo: centerYAnchor),
            self.detail.leadingAnchor.constraint(greaterThanOrEqualTo: self.title.trailingAnchor, constant: inset),
            self.detail.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            self.detail.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        setAccessibilityElement(true)
        setAccessibilityRole(.checkBox)
        setAccessibilityLabel(title)
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    private func refresh() {
        setAccessibilityValue(isOn)
        setAccessibilityEnabled(isEnabled)
        tick.isHidden = !isOn
        title.textColor = isEnabled ? Tokens.Text.primary : Tokens.Text.disabled
        let fill: NSColor? = !isEnabled ? nil : (isPressed ? Tokens.Surface.selected : (isHovering ? Tokens.Surface.hover : nil))
        effectiveAppearance.performAsCurrentDrawingAppearance {
            self.disc.layer?.backgroundColor = self.isOn ? Tokens.Accent.tint.cgColor : nil
            self.disc.layer?.borderWidth = self.isOn ? 0 : 1.5
            self.disc.layer?.borderColor = Tokens.Text.tertiary.cgColor
            Tokens.Motion.wash(self.layer, to: fill)
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refresh()
    }

    // MARK: - Pointer

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let superview, bounds.contains(convert(point, from: superview)) else { return nil }
        return self
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where area.owner === self { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) { isHovering = true }
    override func mouseExited(with event: NSEvent) { isHovering = false }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        isPressed = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard isEnabled else { return }
        isPressed = bounds.contains(convert(event.locationInWindow, from: nil))
    }

    override func mouseUp(with event: NSEvent) {
        let inside = isPressed
        isPressed = false
        if inside { toggle() }
    }

    override func accessibilityPerformPress() -> Bool {
        guard isEnabled else { return false }
        toggle()
        return true
    }

    /// Set from sync, not by the user: `onChange` is not called.
    func setOn(_ on: Bool) {
        guard on != isOn else { return }
        isOn = on
        refresh()
    }

    private func toggle() {
        isOn.toggle()
        refresh()
        onChange?(isOn)
    }

    override var mouseDownCanMoveWindow: Bool { false }
}

private extension SyncStatus {

    /// Green when it is working, amber while it is on its way or waiting for
    /// a connection, grey when there is nothing to report, red when the user
    /// has something to fix.
    var dotColour: NSColor {
        switch self {
        case .synced: Tokens.Accent.secure
        case .syncing, .offline: .systemOrange
        case .off, .needsSignedBuild: Tokens.Text.tertiary
        case .noAccount, .unavailable, .switchedAccount, .storageFull, .removedElsewhere: Tokens.Accent.danger
        }
    }
}

extension SyncZone {

    var title: String {
        switch self {
        case .spaces: String(localized: "Spaces, tabs and Favorites")
        case .sites: String(localized: "Site settings")
        case .settings: String(localized: "Settings and shortcuts")
        case .history: String(localized: "Typed history")
        case .devices: String(localized: "Tabs on other Macs")
        case .meta: ""
        }
    }

    /// The quiet words at a zone's trailing end: where its result shows, or
    /// what it is waiting for.
    func detail(needsSpaces: Bool) -> String {
        if needsSpaces { return String(localized: "Needs Spaces") }
        return self == .devices ? String(localized: "In the History menu") : ""
    }
}
