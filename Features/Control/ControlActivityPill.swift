//
//  ControlActivityPill.swift
//  Luna
//
//  One agent session's newest call, in the page's bottom trailing corner
//  while it works: its app's icon, the session's name, the call in words,
//  and a chevron that opens the session's list (`ControlActivityController`).
//  The working capsule's glass and height, so the two read as one family at
//  the page's foot. Two sessions at work stand one above the other.
//

import AppKit

@MainActor
final class ControlActivityPill: NSButton {

    var onActivate: (() -> Void)?

    /// The working capsule's rim: the app's colour, and its spark while the
    /// agent works, so the pill reads as the same agent at the same work.
    private let rim = RowPillView(role: .folder)
    private let wash = NSView()
    private let icon = NSImageView()
    /// Which session: two pills of one app are otherwise the same pill.
    private let name = NSTextField(labelWithString: "")
    private let label = NSTextField(labelWithString: "")
    private let chevron = NSImageView()
    private(set) var shown: ControlActivity.Shown?
    var entry: ControlActivity.Entry? { shown?.entry }
    var agent: String? { shown?.agent }
    var isWorking: Bool { rim.isWorking }
    /// Its place in the stack, set by `ControlSurfaceView.stackActivityPills`.
    var stackBottom: NSLayoutConstraint?

    private var isHovering = false {
        didSet { if isHovering != oldValue { refreshWash() } }
    }
    private(set) var isPressed = false {
        didSet {
            guard isPressed != oldValue else { return }
            refreshWash()
            pivotOnCentre()
            Tokens.Motion.swell(self, to: isPressed ? Tokens.Motion.pressSwell : 1)
        }
    }

    /// A backing layer scales from its corner, which in the page's corner
    /// pushed the swell off towards the window's edge. Moved to the centre,
    /// keeping the frame where it is, as `PopoutPanelView` moves its own.
    private func pivotOnCentre() {
        guard let layer, layer.anchorPoint != CGPoint(x: 0.5, y: 0.5) else { return }
        let frame = layer.frame
        Tokens.Motion.immediately {
            layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            layer.position = CGPoint(x: frame.midX, y: frame.midY)
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
        layer.map { Tokens.Shadow.popover.apply(to: $0, in: effectiveAppearance) }
        rim.cornerRadius = height / 2
        rim.autoresizingMask = [.width, .height]
        addSubview(rim)
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
        // Gives way only to the width cap below, not to the button's own size.
        label.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        name.font = Tokens.TypeScale.settingsRow
        name.textColor = Tokens.Text.secondary
        name.lineBreakMode = .byTruncatingTail
        // The call is what changes; the name gives way first.
        name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let size = NSImage.SymbolConfiguration(pointSize: label.font?.pointSize ?? 13, weight: .semibold)
        chevron.image = NSImage(systemSymbolName: "chevron.up", accessibilityDescription: nil)?
            .withSymbolConfiguration(size)
        chevron.contentTintColor = Tokens.Text.secondary
        let row = NSStackView(views: [icon, name, label, chevron])
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

    func configure(_ shown: ControlActivity.Shown) {
        let entry = shown.entry
        rim.tint = Tokens.Agent.tint(forApp: entry.appID)
        rim.isWorking = shown.working
        self.shown = shown
        icon.image = entry.appID.flatMap(ControlAppIcon.image(for:))
            ?? NSImage(systemSymbolName: BrowserSession.controlFolderSymbol, accessibilityDescription: nil)
        name.stringValue = shown.name
        label.stringValue = entry.title
        setAccessibilityLabel(String(localized: "\(shown.name): \(entry.title). Show all activity"))
    }

    @objc private func fire() { onActivate?() }

    /// The row inside sets the size. `NSButton`'s own, from an empty title
    /// and its bezel, measured 72 × 38 pt against a 36 pt capsule and
    /// squeezed the call out of the label.
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

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

    override func layout() {
        super.layout()
        Tokens.Motion.immediately { rim.frame = bounds }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        layer.map { Tokens.Shadow.popover.apply(to: $0, in: effectiveAppearance) }
        label.textColor = Tokens.Text.primary
        name.textColor = Tokens.Text.secondary
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

    /// A pill per entry of `shown`, lowest first, each fading in and out as
    /// the working capsule does. Empty takes them all away.
    func showActivity(_ shown: [ControlActivity.Shown], onOpen: @escaping (String, NSView) -> Void) {
        let wanted = Set(shown.map(\.agent))
        for pill in activityPills where !wanted.contains(pill.agent ?? "") {
            Tokens.Motion.animate(Tokens.Motion.agentSheet) { _ in
                pill.animator().alphaValue = 0
            } completion: {
                MainActor.assumeIsolated { pill.removeFromSuperview() }
            }
        }
        let kept = Dictionary(
            activityPills.compactMap { pill in pill.agent.map { ($0, pill) } }, uniquingKeysWith: { first, _ in first }
        )
        activityPills = shown.enumerated().map { index, item in
            let pill = kept[item.agent] ?? makeActivityPill(at: index)
            pill.onActivate = { [weak pill] in pill.map { onOpen(item.agent, $0) } }
            if pill.shown != item {
                pill.configure(item)
            }
            return pill
        }
        stackActivityPills()
    }

    /// Lowest first, a gap between each. A pill whose place changed slides
    /// there: the one below it went, which is a state, not a resize.
    private func stackActivityPills() {
        var moved = false
        for (index, pill) in activityPills.enumerated() where pill.stackBottom?.constant != Self.pillBottom(at: index) {
            pill.stackBottom?.constant = Self.pillBottom(at: index)
            moved = true
        }
        guard moved else { return }
        Tokens.Motion.animate(Tokens.Motion.agentSheet) { context in
            context.allowsImplicitAnimation = true
            layoutSubtreeIfNeeded()
        }
    }

    private static func pillBottom(at index: Int) -> CGFloat {
        -Tokens.Metric.chromeGapWide - CGFloat(index) * (Tokens.Agent.capsuleHeight + Tokens.Metric.chromeGap)
    }

    private func makeActivityPill(at index: Int) -> ControlActivityPill {
        let pill = ControlActivityPill()
        pill.alphaValue = 0
        addSubview(pill)
        let gap = Tokens.Metric.chromeGapWide
        // Placed where it will stand before it fades in: it does not fly
        // from the corner to its place in the stack.
        let bottom = pill.bottomAnchor.constraint(equalTo: bottomAnchor, constant: Self.pillBottom(at: index))
        pill.stackBottom = bottom
        NSLayoutConstraint.activate([pill.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -gap), bottom])
        Tokens.Motion.immediately { layoutSubtreeIfNeeded() }
        Tokens.Motion.animate(Tokens.Motion.agentSheet) { _ in pill.animator().alphaValue = 1 }
        return pill
    }
}
