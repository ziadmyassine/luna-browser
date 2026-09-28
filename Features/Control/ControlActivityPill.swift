//
//  ControlActivityPill.swift
//  Luna
//
//  The agent's newest call, in the page's bottom trailing corner while it
//  works: its app's icon, the call in words, and a chevron that opens the
//  whole list (`ControlActivityController`). The working capsule's glass and
//  height, so the two read as one family at the page's foot.
//

import AppKit

@MainActor
final class ControlActivityPill: NSButton {

    var onActivate: (() -> Void)?

    private let wash = NSView()
    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let chevron = NSImageView()
    private(set) var entry: ControlActivity.Entry?

    private var isHovering = false {
        didSet { if isHovering != oldValue { refreshWash() } }
    }
    private(set) var isPressed = false {
        didSet {
            guard isPressed != oldValue else { return }
            refreshWash()
            Tokens.Motion.swell(self, to: isPressed ? Tokens.Motion.pressSwell : 1)
        }
    }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        isBordered = false
        title = ""
        target = self
        action = #selector(fire)
        translatesAutoresizingMaskIntoConstraints = false
        let height = Tokens.Agent.capsuleHeight
        Glass.apply(.popover, to: self, cornerRadius: height / 2).pinToEdges()
        wash.wantsLayer = true
        wash.layer?.cornerRadius = height / 2
        wash.layer?.cornerCurve = .continuous
        addSubview(wash)
        wash.pinToEdges()
        buildRow(height: height)
        setAccessibilityRole(.button)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    private func buildRow(height: CGFloat) {
        icon.imageScaling = .scaleProportionallyUpOrDown
        label.font = Tokens.TypeScale.settingsRow
        label.textColor = Tokens.Text.primary
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let size = NSImage.SymbolConfiguration(pointSize: label.font?.pointSize ?? 13, weight: .semibold)
        chevron.image = NSImage(systemSymbolName: "chevron.up", accessibilityDescription: nil)?
            .withSymbolConfiguration(size)
        chevron.contentTintColor = Tokens.Text.secondary
        let row = NSStackView(views: [icon, label, chevron])
        row.orientation = .horizontal
        row.spacing = Tokens.Metric.chromeGap
        row.alignment = .centerY
        row.edgeInsets = NSEdgeInsets(top: 0, left: height / 3, bottom: 0, right: height / 3)
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: Tokens.Metric.faviconSize),
            icon.heightAnchor.constraint(equalToConstant: Tokens.Metric.faviconSize),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: height),
            // No wider than the list it opens, which stands on it.
            widthAnchor.constraint(lessThanOrEqualToConstant: Tokens.Metric.historyPanel.width)
        ])
    }

    func configure(_ entry: ControlActivity.Entry) {
        self.entry = entry
        icon.image = entry.appID.flatMap(ControlAppIcon.image(for:))
            ?? NSImage(systemSymbolName: BrowserSession.controlFolderSymbol, accessibilityDescription: nil)
        label.stringValue = entry.title
        setAccessibilityLabel(String(localized: "\(entry.client): \(entry.title). Show all activity"))
    }

    @objc private func fire() { onActivate?() }

    /// The whole pill is the button; the label and icons inside it are not
    /// targets of their own.
    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }

    /// Glass at rest, §3.4's washes over it on the pointer and the press.
    private func refreshWash() {
        let colour = isPressed ? Tokens.Surface.selected : isHovering ? Tokens.Surface.hover : NSColor.clear
        effectiveAppearance.performAsCurrentDrawingAppearance {
            Tokens.Motion.wash(self.wash.layer, to: colour)
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        label.textColor = Tokens.Text.primary
        refreshWash()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where area.owner === self { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) { isHovering = true }

    override func mouseExited(with event: NSEvent) { isHovering = false }

    /// Around `NSControl`'s tracking loop — see `TopBarButton.mouseDown`.
    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        isPressed = true
        super.mouseDown(with: event)
        isPressed = false
    }

    override func highlight(_ flag: Bool) {
        super.highlight(flag)
        isPressed = flag && isEnabled
    }
}

extension ControlSurfaceView {

    /// The pill for `entry`, in the bottom trailing corner, fading in and out
    /// as the working capsule does; nil takes it away.
    func showActivity(_ entry: ControlActivity.Entry?, onOpen: @escaping (NSView) -> Void) {
        guard let entry else {
            guard let pill = activityPill else { return }
            activityPill = nil
            Tokens.Motion.animate(Tokens.Motion.agentSheet) { _ in
                pill.animator().alphaValue = 0
            } completion: {
                MainActor.assumeIsolated { pill.removeFromSuperview() }
            }
            return
        }
        let pill = activityPill ?? makeActivityPill()
        pill.onActivate = { [weak pill] in pill.map(onOpen) }
        if pill.entry != entry {
            pill.configure(entry)
            Tokens.Motion.immediately { layoutSubtreeIfNeeded() }
        }
    }

    private func makeActivityPill() -> ControlActivityPill {
        let pill = ControlActivityPill()
        pill.alphaValue = 0
        addSubview(pill)
        let gap = Tokens.Metric.chromeGapWide
        NSLayoutConstraint.activate([
            pill.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -gap),
            pill.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -gap)
        ])
        activityPill = pill
        Tokens.Motion.immediately { layoutSubtreeIfNeeded() }
        Tokens.Motion.animate(Tokens.Motion.agentSheet) { _ in pill.animator().alphaValue = 1 }
        return pill
    }
}
