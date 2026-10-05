//
//  ControlSurface.swift
//  Luna
//
//  Luna Control's layer over the page (docs/LUNA-CONTROL.md): the question an
//  agent is waiting on, dropping from the top edge of whatever page is in
//  front; the capsule at the foot of a page an agent is working on, with
//  Take Over; the agent's pointer where it last acted; the page toasts
//  (`PageToast`), which drop from the same edge; and §18.1's find field in
//  the top trailing corner (`FindBarView`). One view in the
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
        didSet {
            guard topInset != oldValue else { return }
            if findBar != nil { findBarTop?.constant = findBarTopConstant(shown: true) }
            guard let sheet, sliding == 0 else { return }
            sheetTop?.constant = topConstant(for: sheet, shown: true)
        }
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
    /// The sheet's top edge, which is what slides. Both it and the capsule
    /// are held centred by constraints rather than placed by frame: a frame
    /// set once from `bounds` has to be recomputed on every resize, and the
    /// views inside them are laid out by constraints that a zero-sized
    /// start put in conflict with the frame.
    private var sheetTop: NSLayoutConstraint?
    private var sliding = 0
    private(set) var capsule: ControlWorkingCapsule?
    /// The page toast on screen, its top edge, and the timer that sends it
    /// back up (`ControlSurfaceView+Toast`).
    var toast: PageToastView?
    var toastTop: NSLayoutConstraint?
    var toastDismissal: Task<Void, Never>?
    /// When the toast that is down goes back up, unless the pointer holds it.
    var toastDeadline: Date?
    /// §18.1's find field, and its top edge (`ControlSurfaceView+Find`).
    var findBar: FindBarView?
    var findBarTop: NSLayoutConstraint?
    /// Each agent session's newest call, stacked up from the bottom trailing
    /// corner, lowest first (`ControlActivityPill`).
    var activityPills: [ControlActivityPill] = []
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

    // MARK: - The question

    /// Shows `view`, sized already, dropping from the top edge; nil sends the
    /// one showing back up. A view replacing another takes its place without
    /// a second drop: it is the next question, not a new arrival.
    func showSheet(_ view: NSView?) {
        let old = sheet
        let oldTop = sheetTop
        sheet = view
        sheetTop = nil
        if let old {
            if view == nil, let oldTop {
                slide(old, along: oldTop, shown: false) { old.removeFromSuperview() }
            } else {
                old.removeFromSuperview()
            }
        }
        guard let view else { return }
        view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(view)
        let top = view.topAnchor.constraint(equalTo: topAnchor, constant: topConstant(for: view, shown: old != nil))
        sheetTop = top
        NSLayoutConstraint.activate([view.centerXAnchor.constraint(equalTo: centerXAnchor), top])
        Tokens.Motion.immediately { layoutSubtreeIfNeeded() }
        if old == nil { slide(view, along: top, shown: true) }
    }

    /// Running up under the bar by its own corner so only its lower corners
    /// show; hidden, wholly above the bar's lower edge.
    private func topConstant(for view: NSView, shown: Bool) -> CGFloat {
        shown ? topInset - ControlApprovalCardView.hiddenTop : topInset - view.fittingSize.height
    }

    private func slide(
        _ view: NSView, along top: NSLayoutConstraint, shown: Bool, then done: (@MainActor () -> Void)? = nil
    ) {
        sliding += 1
        let target = topConstant(for: view, shown: shown)
        Tokens.Motion.animate(Tokens.Motion.agentSheet) { _ in
            top.animator().constant = target
        } completion: { [weak self] in
            MainActor.assumeIsolated {
                done?()
                self?.slideEnded()
            }
        }
    }

    /// The bar may have moved while the sheet was on its way.
    private func slideEnded() {
        sliding -= 1
        guard sliding == 0, let sheet, let sheetTop else { return }
        sheetTop.constant = topConstant(for: sheet, shown: true)
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
            // Bottom-centre, a gap above the page's foot.
            NSLayoutConstraint.activate([
                made.centerXAnchor.constraint(equalTo: centerXAnchor),
                made.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Tokens.Metric.chromeGapWide)
            ])
            self.capsule = made
            return made
        }()
        let arriving = capsule.working == nil
        capsule.configure(working) { [weak self] in self?.onToggleWorking?() }
        Tokens.Motion.immediately { layoutSubtreeIfNeeded() }
        if arriving { fade(capsule, in: true) }
    }

    // MARK: - The agent's pointer

    /// Moves the agent's pointer to `point`, in this view's coordinates,
    /// gliding from where it last was.
    /// - Parameter clicks: the call presses there, and the ripple shows it
    ///   landing once the pointer has arrived.
    func point(at point: NSPoint, client: String, tint: NSColor, clicks: Bool = false) {
        pointer.configure(agent: client, tint: tint)
        let origin = NSPoint(x: point.x - ControlAgentPointer.tip.x, y: point.y - ControlAgentPointer.tip.y)
        guard pointer.alphaValue > 0, !Tokens.Motion.reduceMotion else {
            pointer.setFrameOrigin(origin)
            addSubview(pointer, positioned: .below, relativeTo: capsule ?? sheet)
            if clicks { pointer.pulse() }
            return fade(pointer, in: true)
        }
        Tokens.Motion.animate(Tokens.Motion.agentSheet) { _ in
            pointer.animator().setFrameOrigin(origin)
        } completion: { [weak self] in
            MainActor.assumeIsolated { if clicks { self?.pointer.pulse() } }
        }
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
    private(set) var button: ControlCapsuleButton?

    /// The gap round the button, which is also the difference between the
    /// two corners.
    private static var inset: CGFloat { (Tokens.Agent.capsuleHeight - SettingsMetrics.controlHeight) / 2 }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        let height = Tokens.Agent.capsuleHeight
        Glass.apply(.popover, to: self, cornerRadius: height / 2).pinToEdges()
        rim.cornerRadius = height / 2
        rim.autoresizingMask = [.width, .height]
        addSubview(rim)
        icon.imageScaling = .scaleProportionallyUpOrDown
        label.font = Tokens.TypeScale.settingsRow
        label.textColor = Tokens.Text.primary
        row.orientation = .horizontal
        row.spacing = Tokens.Metric.chromeGap
        row.alignment = .centerY
        row.edgeInsets = NSEdgeInsets(top: 0, left: height / 3, bottom: 0, right: Self.inset)
        row.translatesAutoresizingMaskIntoConstraints = false
        // As wide as what is in it, and no wider.
        row.setHuggingPriority(.defaultHigh, for: .horizontal)
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
        // Paused is the user at the wheel: the rover's face, and the way to
        // give the wheel back, with the keys that do it.
        icon.image = working.isPaused ? AgentGlyph.image(pointSize: Tokens.Metric.faviconSize)
            : working.appID.flatMap(ControlAppIcon.image(for:))
            ?? NSImage(systemSymbolName: BrowserSession.controlFolderSymbol, accessibilityDescription: nil)
        icon.contentTintColor = Tokens.Text.primary
        label.stringValue = working.isPaused
            ? String(localized: "You’re driving")
            : String(localized: "\(working.client) is working")
        let button = self.button ?? ControlCapsuleButton()
        button.title = working.isPaused ? String(localized: "Hand Back") : String(localized: "Take Over")
        button.shortcut = working.isPaused ? "⌘↩" : nil
        button.onActivate = onToggle
        watchHandBack(working.isPaused ? onToggle : nil)
        // The capsule is the material, so the capsule is what swells.
        button.onPressChange = { [weak self] pressed in
            guard let self else { return }
            Tokens.Motion.swell(self, to: pressed ? Tokens.Motion.pressSwell : 1)
        }
        self.button = button
        row.setViews([icon, label, button], in: .leading)
        setAccessibilityLabel(label.stringValue)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        layer.map { Tokens.Shadow.popover.apply(to: $0, in: effectiveAppearance) }
    }

    private var handBackMonitor: Any?

    /// `⌘↩` hands the page back while the user is driving, wherever the
    /// keyboard is in this window — the page has it, not the capsule.
    private func watchHandBack(_ handBack: (() -> Void)?) {
        if let handBackMonitor { NSEvent.removeMonitor(handBackMonitor) }
        handBackMonitor = nil
        guard let handBack else { return }
        handBackMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard let self, event.window === window, window != nil, modifiers == .command,
                  event.keyCode == 36 || event.keyCode == 76 else { return event }
            handBack()
            return nil
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { watchHandBack(nil) }
    }

    override func layout() {
        super.layout()
        Tokens.Motion.immediately { rim.frame = bounds }
    }
}

/// Take Over and Resume: a pill inside the capsule, its corner the capsule's
/// less the gap round it, so the two curves run together. The settings push
/// button it replaced, a squarer plate with a hairline, read as a control
/// dropped in from another window. It has no glass of its own and hands its
/// press up to the capsule, as the top bar's capsule items do.
@MainActor
final class ControlCapsuleButton: NSButton {

    var onActivate: (() -> Void)?
    var onPressChange: ((Bool) -> Void)?

    private var isHovering = false {
        didSet { if isHovering != oldValue { refreshFill() } }
    }
    private var isPressed = false {
        didSet {
            guard isPressed != oldValue else { return }
            refreshFill()
            onPressChange?(isPressed)
        }
    }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        isBordered = false
        target = self
        action = #selector(fire)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: SettingsMetrics.controlHeight).isActive = true
        refreshFill()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    @objc private func fire() { onActivate?() }

    override var title: String {
        didSet { if title != oldValue { applyTitle() } }
    }

    /// The keys that press it, set after the title in the secondary ink —
    /// Hand Back's `⌘↩`.
    var shortcut: String? {
        didSet { if shortcut != oldValue { applyTitle() } }
    }

    private func applyTitle() {
        let text = NSMutableAttributedString(string: title, attributes: [
            .font: Tokens.TypeScale.settingsRow,
            .foregroundColor: Tokens.Text.primary
        ])
        if let shortcut {
            text.append(NSAttributedString(string: "  " + shortcut, attributes: [
                .font: Tokens.TypeScale.settingsRow,
                .foregroundColor: Tokens.Text.secondary
            ]))
        }
        attributedTitle = text
        invalidateIntrinsicContentSize()
    }

    override var intrinsicContentSize: NSSize {
        var size = super.intrinsicContentSize
        size.width += 2 * SettingsMetrics.controlInset
        size.height = SettingsMetrics.controlHeight
        return size
    }

    override func layout() {
        super.layout()
        Tokens.Motion.immediately { layer?.cornerRadius = bounds.height / 2 }
    }

    /// Resting on §3.4's 6 %, so it reads as a button and not as more of the
    /// sentence beside it; the pointer and the press take it to 12 %.
    private func refreshFill() {
        let colour = isHovering || isPressed ? Tokens.Surface.selected : Tokens.Surface.hover
        effectiveAppearance.performAsCurrentDrawingAppearance {
            Tokens.Motion.wash(self.layer, to: colour)
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyTitle()
        refreshFill()
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

extension NSView {
    /// Holds a glass backing to its host's edges by constraints. A host that
    /// starts at `.zero` and is then sized left the backing's autoresizing at
    /// twice the host's size, reaching off its right and bottom edges: the
    /// Luna Control sheet looked twice as wide as its text and off centre.
    func pinToEdges() {
        guard let superview else { return }
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            leadingAnchor.constraint(equalTo: superview.leadingAnchor),
            trailingAnchor.constraint(equalTo: superview.trailingAnchor),
            topAnchor.constraint(equalTo: superview.topAnchor),
            bottomAnchor.constraint(equalTo: superview.bottomAnchor)
        ])
    }
}
