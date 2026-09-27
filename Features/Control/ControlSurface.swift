//
//  ControlSurface.swift
//  Luna
//
//  Luna Control's layer over the page (docs/LUNA-CONTROL.md): the question an
//  agent is waiting on, dropping from the top edge of whatever page is in
//  front; the capsule at the foot of a page an agent is working on, with
//  Take Over; and the agent's pointer where it last acted. One view in the
//  content card, above the page and under §3.2b's bar, so it is over every
//  tab without belonging to any of them.
//

import AppKit

@MainActor
final class ControlSurfaceView: NSView {

    /// Who is working on the page in front, for the capsule.
    struct Working: Equatable {
        var client: String
        var appID: String?
        var isPaused: Bool
        /// A call is running, or ended a moment ago: the rim's spark runs.
        var isActing: Bool
    }

    /// The capsule's Take Over or Resume.
    var onToggleWorking: (() -> Void)?

    /// How much of the card's top §3.2b's bar covers: the sheet drops from
    /// under it.
    var topInset: CGFloat = 0 {
        didSet { if topInset != oldValue { needsLayout = true } }
    }

    /// The colour of the page in front (`TabState.pageBackground`), which the
    /// layer takes its appearance from, as §3.2b's bar does: glass composites
    /// what is behind the window, not the page, so a dark app's white text on
    /// it vanished into a white site. Over a white page the sheet and the
    /// capsule are light glass with dark text.
    func setPageColour(_ colour: NSColor?) {
        let behind = colour ?? Tokens.Surface.base
        let dark = behind.wantsLightInk(in: (superview ?? self).effectiveAppearance)
        let wanted = NSAppearance(named: dark ? .darkAqua : .aqua)
        guard appearance?.name != wanted?.name else { return }
        appearance = wanted
    }

    private(set) var sheet: NSView?
    private var sliding = 0
    private(set) var capsule: ControlWorkingCapsule?
    private let pointer = ControlAgentPointer()

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        pointer.alphaValue = 0
        addSubview(pointer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    /// Only the sheet and the capsule take the pointer; the page gets the rest.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        if hit === self || hit === pointer || hit?.isDescendant(of: pointer) == true { return nil }
        return hit
    }

    override func layout() {
        super.layout()
        Tokens.Motion.immediately {
            if let sheet, sliding == 0 { sheet.frame = sheetFrame(sheet.frame.size, shown: true) }
            if let capsule { capsule.frame = capsuleFrame(capsule.fittingSize) }
        }
    }

    // MARK: - The question

    /// Shows `view`, sized already, dropping from the top edge; nil sends the
    /// one showing back up. A view replacing another takes its place without
    /// a second drop: it is the next question, not a new arrival.
    func showSheet(_ view: NSView?) {
        let old = sheet
        sheet = view
        if let old {
            if view == nil {
                slide(old, shown: false) { old.removeFromSuperview() }
            } else {
                old.removeFromSuperview()
            }
        }
        guard let view else { return }
        addSubview(view)
        view.frame = sheetFrame(view.frame.size, shown: old != nil)
        if old == nil { slide(view, shown: true) }
    }

    /// Top-centre, running up under the bar by its own corner so only its
    /// lower corners show; hidden, it is wholly above the bar's lower edge.
    private func sheetFrame(_ size: NSSize, shown: Bool) -> NSRect {
        let y = shown ? topInset - ControlApprovalCardView.hiddenTop : topInset - size.height
        return NSRect(x: ((bounds.width - size.width) / 2).rounded(), y: y, width: size.width, height: size.height)
    }

    private func slide(_ view: NSView, shown: Bool, then done: (@MainActor () -> Void)? = nil) {
        sliding += 1
        let target = sheetFrame(view.frame.size, shown: shown)
        Tokens.Motion.animate(Tokens.Motion.agentSheet) { _ in
            view.animator().frame = target
        } completion: { [weak self] in
            MainActor.assumeIsolated {
                self?.sliding -= 1
                done?()
                self?.needsLayout = true
            }
        }
    }

    // MARK: - Working

    /// The capsule for the agent working on the page in front, or nil.
    func showWorking(_ working: Working?) {
        guard working != capsule?.working else { return }
        guard let working else {
            if let capsule {
                self.capsule = nil
                fade(capsule, in: false) { capsule.removeFromSuperview() }
            }
            fade(pointer, in: false)
            return
        }
        let capsule = self.capsule ?? {
            let made = ControlWorkingCapsule()
            made.alphaValue = 0
            addSubview(made, positioned: .below, relativeTo: sheet)
            self.capsule = made
            return made
        }()
        let arriving = capsule.working == nil
        capsule.configure(working) { [weak self] in self?.onToggleWorking?() }
        capsule.frame = capsuleFrame(capsule.fittingSize)
        if arriving { fade(capsule, in: true) }
    }

    /// Bottom-centre, a gap above the page's foot.
    private func capsuleFrame(_ size: NSSize) -> NSRect {
        NSRect(
            x: ((bounds.width - size.width) / 2).rounded(), y: bounds.height - size.height - Tokens.Metric.chromeGapWide,
            width: size.width, height: size.height
        )
    }

    // MARK: - The agent's pointer

    /// Moves the agent's pointer to `point`, in this view's coordinates,
    /// gliding from where it last was.
    func point(at point: NSPoint, client: String, tint: NSColor) {
        pointer.configure(label: client, tint: tint)
        let origin = NSPoint(x: point.x - ControlAgentPointer.tip.x, y: point.y - ControlAgentPointer.tip.y)
        guard pointer.alphaValue > 0, !Tokens.Motion.reduceMotion else {
            pointer.setFrameOrigin(origin)
            addSubview(pointer, positioned: .below, relativeTo: capsule ?? sheet)
            return fade(pointer, in: true)
        }
        Tokens.Motion.animate(Tokens.Motion.agentSheet) { _ in pointer.animator().setFrameOrigin(origin) }
    }

    private func fade(_ view: NSView, in shown: Bool, then done: (@MainActor () -> Void)? = nil) {
        Tokens.Motion.animate(Tokens.Motion.agentSheet) { _ in
            view.animator().alphaValue = shown ? 1 : 0
        } completion: {
            MainActor.assumeIsolated { done?() }
        }
    }
}

/// The capsule at the foot of a page an agent is working on: the app's icon,
/// "working" or "paused", and Take Over or Resume. Its rim is the agent's
/// folder's, spark and all, so the two read as one thing.
@MainActor
final class ControlWorkingCapsule: NSView {

    private(set) var working: ControlSurfaceView.Working?
    private let rim = RowPillView(role: .folder)
    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let row = NSStackView()
    private var button: SettingsPushButton?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        let height = Tokens.Agent.capsuleHeight
        Glass.apply(.popover, to: self, cornerRadius: height / 2)
        rim.cornerRadius = height / 2
        rim.autoresizingMask = [.width, .height]
        addSubview(rim)
        icon.imageScaling = .scaleProportionallyUpOrDown
        label.font = Tokens.TypeScale.settingsRow
        label.textColor = Tokens.Text.primary
        row.orientation = .horizontal
        row.spacing = Tokens.Metric.chromeGap
        row.alignment = .centerY
        row.edgeInsets = NSEdgeInsets(top: 0, left: height / 3, bottom: 0, right: 4)
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: Tokens.Metric.faviconSize),
            icon.heightAnchor.constraint(equalToConstant: Tokens.Metric.faviconSize),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: height)
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    func configure(_ working: ControlSurfaceView.Working, onToggle: @escaping () -> Void) {
        self.working = working
        rim.tint = Tokens.Agent.tint(forApp: working.appID)
        rim.isWorking = working.isActing && !working.isPaused
        icon.image = working.appID.flatMap(ControlAppIcon.image(for:))
            ?? NSImage(systemSymbolName: BrowserSession.controlFolderSymbol, accessibilityDescription: nil)
        label.stringValue = working.isPaused
            ? String(localized: "\(working.client) is paused")
            : String(localized: "\(working.client) is working")
        // `SettingsPushButton`, which already answers hover and press
        // (`ButtonFeedbackTests`).
        let button = SettingsPushButton(
            title: working.isPaused ? String(localized: "Resume") : String(localized: "Take Over"), isDestructive: false
        )
        button.onActivate = onToggle
        self.button = button
        row.setViews([icon, label, button], in: .leading)
        setAccessibilityLabel(label.stringValue)
        layoutSubtreeIfNeeded()
        rim.frame = bounds
    }

    override var fittingSize: NSSize {
        NSSize(width: row.fittingSize.width, height: Tokens.Agent.capsuleHeight)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        layer.map { Tokens.Shadow.popover.apply(to: $0, in: effectiveAppearance) }
    }

    override func layout() {
        super.layout()
        Tokens.Motion.immediately { rim.frame = bounds }
    }
}

/// The agent's pointer: an arrow in its app's colour with its name beside
/// it, where it last clicked, hovered, typed or dragged. A picture only: it
/// takes no events, and the page never sees it.
@MainActor
final class ControlAgentPointer: NSView {

    /// Where in the view the arrow's tip is, which is what stands on the point.
    static let tip = NSPoint(x: 4, y: 3)

    private let arrow = NSImageView()
    private let nameTag = NSTextField(labelWithString: "")

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: NSRect(x: 0, y: 0, width: 160, height: 40))
        arrow.image = NSImage(systemSymbolName: "cursorarrow", accessibilityDescription: nil)
        arrow.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
        arrow.frame = NSRect(x: 0, y: 0, width: 22, height: 24)
        nameTag.font = Tokens.TypeScale.settingsCaption
        nameTag.wantsLayer = true
        nameTag.layer?.cornerRadius = 4
        nameTag.textColor = .white
        addSubview(arrow)
        addSubview(nameTag)
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    func configure(label: String, tint: NSColor) {
        arrow.contentTintColor = tint
        nameTag.stringValue = " \(label) "
        nameTag.layer?.backgroundColor = tint.cgColor
        nameTag.textColor = tint.brightnessComponentIfAvailable > 0.8 ? .black : .white
        nameTag.sizeToFit()
        nameTag.setFrameOrigin(NSPoint(x: 16, y: 20))
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private extension NSColor {
    /// White and the label colour on a dark sidebar want dark ink on them.
    var brightnessComponentIfAvailable: CGFloat {
        usingColorSpace(.sRGB)?.brightnessComponent ?? 0
    }
}
