//
//  TopBarSpaceName.swift
//  Luna
//
//  §4's Space switcher: the Space's name, at the head of the plate that holds
//  its kept tabs.
//
//      [ Personal  ▢ ▢ ▢ ▢ ]
//
//  The name is the control, and it is on the plate because the kept tabs are
//  the Space's own — the name is the label on the shelf they stand on. Under
//  the pointer the name steps up and §3.5's dots come out beneath it, one per
//  Space, the column's own strip without its pill. A click on a dot goes there;
//  §30.9's two-finger swipe over the name goes to the next one, and the dots
//  read the gesture out while the fingers are down.
//
//  The dots are hidden at rest because a bar has words and no room: six dots
//  say less than the one name they stand for, until the moment the hand is
//  asking which of the others it can reach.
//
//  The name pops when it changes, because it is the only thing on the bar that
//  says the whole window has moved. Every other read-out of a Space switch is
//  the tabs redrawing, which looks like tabs redrawing.
//

import AppKit
import BrowserKit

/// An `NSControl` so a press on it stays its own — see `TopBarTabRow`.
@MainActor
final class TopBarSpaceName: NSControl, TopBarThemed {

    var onSwitch: ((UUID) -> Void)?
    var onSetGradient: ((UUID, GradientPair) -> Void)?
    var onEditSpaces: (() -> Void)?
    var onNewSpace: (() -> Void)?

    private let name = NSTextField(labelWithString: "")
    let dots = SpaceDotsView(framed: false)
    private let swipe = SpaceSwipeController()
    private var spaces: [Space] = []
    private var activeSpaceID: UUID?
    private var tracking: NSTrackingArea?
    private var isHovering = false
    private var isSwiping = false
    /// How far the name is pushed at a full Space of travel. A name that moved
    /// the whole width of the plate would be gone before the gesture had
    /// decided anything; this is far enough to read as "being pushed aside".
    private static let nameTravel: CGFloat = 12

    /// §6.6's lift is over the name, so the dots are out and each is a place
    /// the tab can go.
    var isAimedAt = false {
        didSet {
            guard isAimedAt != oldValue else { return }
            reveal()
        }
    }

    /// Whether the dots are out: under the pointer, under a swipe, or under a
    /// lift.
    var showsDots: Bool { isHovering || isSwiping || isAimedAt }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setAccessibilityElement(true)
        setAccessibilityRole(.group)

        name.lineBreakMode = .byTruncatingTail
        name.cell?.usesSingleLineMode = true
        name.alignment = .center
        addSubview(name)

        dots.alphaValue = 0
        dots.dotScale = TopBarMetrics.dotScale
        dots.onSwitch = { [weak self] id in self?.onSwitch?(id) }
        dots.onSetGradient = { [weak self] id, gradient in self?.onSetGradient?(id, gradient) }
        dots.onEditSpaces = { [weak self] in self?.onEditSpaces?() }
        dots.onNewSpace = { [weak self] in self?.onNewSpace?() }
        addSubview(dots)

        swipe.spaces = { [weak self] in (self?.spaces.map(\.id) ?? [], self?.activeSpaceID) }
        swipe.span = { [weak self] in max(self?.bounds.width ?? 0, TopBarMetrics.nameCeiling) }
        swipe.onUpdate = { [weak self] state in self?.read(state) }
        swipe.onFinish = { [weak self] state, _, committing in self?.settle(state, committing: committing) }

        applyTokens()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code")
    }

    func show(spaces: [Space], activeSpaceID: UUID) {
        let moved = self.activeSpaceID != nil && self.activeSpaceID != activeSpaceID
        self.spaces = spaces
        self.activeSpaceID = activeSpaceID
        dots.show(spaces: spaces, activeSpaceID: activeSpaceID)

        let title = spaces.first { $0.id == activeSpaceID }?.name ?? ""
        guard title != name.stringValue || moved else { return }
        name.stringValue = title
        name.toolTip = title
        setAccessibilityLabel(String(localized: "Space: \(title)"))
        invalidateIntrinsicContentSize()
        needsLayout = true
        guard moved else { return }
        pop()
    }

    /// The new name arriving: it flares out and settles, the way §3.3's light
    /// does, rather than growing in from nothing. A name is being replaced, not
    /// introduced, and a name that grows reads as a control resizing.
    private func pop() {
        guard !Tokens.Motion.reduceMotion else { return }
        name.wantsLayer = true
        name.alphaValue = 0
        Tokens.Motion.animate(Tokens.Motion.tabInsert) { context in
            context.allowsImplicitAnimation = true
            name.animator().alphaValue = 1
        }
        guard let scale = Tokens.Motion.tabInsert.springAnimation(keyPath: "transform.scale") else { return }
        scale.fromValue = 1.08
        scale.toValue = 1.0
        name.layer?.add(scale, forKey: "luna.space.pop")
    }

    // MARK: - §6.6: a tab carried to another Space

    /// The Space a dot at `point` stands for, with `point` in `space`'s
    /// coordinates. Nil anywhere but on a dot, and nil while the dots are
    /// not out — a drop must never land on a dot the hand cannot see.
    func space(at point: NSPoint, from space: NSView) -> UUID? {
        guard showsDots else { return nil }
        return dots.spaceID(at: point, from: space)
    }

    /// Whether `point`, in `space`'s coordinates, is over the name at all.
    func contains(_ point: NSPoint, from space: NSView) -> Bool {
        bounds.contains(convert(point, from: space))
    }

    /// The Space a lift is held over, marked on its dot.
    var dropTarget: UUID? {
        get { dots.highlightedSpaceID }
        set { dots.highlightedSpaceID = newValue }
    }

    // MARK: - The pointer

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        reveal()
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        reveal()
    }

    /// The name steps up and the dots come out under it, or the other way
    /// round, on §6's `controlHover` — the pointer's own curve.
    private func reveal() {
        let shown = showsDots
        guard !Tokens.Motion.reduceMotion, window != nil else {
            Tokens.Motion.immediately { placeContents() }
            return
        }
        Tokens.Motion.animate(Tokens.Motion.controlHover) { context in
            context.allowsImplicitAnimation = true
            name.animator().frame = nameFrame()
            dots.animator().alphaValue = shown ? 1 : 0
        }
    }

    // MARK: - §30.9's swipe

    override func scrollWheel(with event: NSEvent) {
        guard !swipe.scrollWheel(with: event) else { return }
        super.scrollWheel(with: event)
    }

    /// The live read-out: the dots follow the fingers, and the name is pushed
    /// the way they are going and fades as it goes, so the gesture says what
    /// it is doing before it does it.
    private func read(_ state: SpaceSwipe) {
        if !isSwiping {
            isSwiping = true
            reveal()
        }
        dots.travel = state.travel
        dots.creation = state.creation
        let reach = min(abs(state.travel), 1)
        Tokens.Motion.immediately {
            name.frame = nameFrame(pushedBy: -state.travel * Self.nameTravel)
            name.alphaValue = 1 - reach * 0.7
        }
    }

    private func settle(_ state: SpaceSwipe, committing: Bool) {
        defer {
            isSwiping = false
            dots.travel = 0
            dots.creation = 0
            Tokens.Motion.immediately {
                name.frame = nameFrame()
                name.alphaValue = 1
            }
            reveal()
        }
        guard committing else { return }
        guard !state.createsSpace else {
            onNewSpace?()
            return
        }
        guard let landing = state.landing, spaces.indices.contains(landing) else { return }
        onSwitch?(spaces[landing].id)
    }

    // MARK: - §6.2 and §8.2, from the one place a Space is visible on this bar

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let space = spaces.first(where: { $0.id == activeSpaceID }) else {
            return SidebarMenu.spaces(
                edit: { [weak self] in self?.onEditSpaces?() },
                new: { [weak self] in self?.onNewSpace?() }
            )
        }
        return SidebarMenu.colours(
            for: space,
            in: effectiveAppearance,
            setGradient: { [weak self] gradient in self?.onSetGradient?(space.id, gradient) },
            edit: { [weak self] in self?.onEditSpaces?() }
        )
    }

    // MARK: - Geometry

    /// The name, or the dots under it if they are wider, with a gap either
    /// side — and the same ceiling on the name a tab's title has, for the same
    /// reason: one long name must not spend the room the tabs need.
    override var intrinsicContentSize: NSSize {
        let title = min(name.fittingSize.width.rounded(.up), TopBarMetrics.nameCeiling)
        return NSSize(
            width: max(title, dotsWidth) + TopBarMetrics.gap * 2,
            height: TopBarMetrics.lineHeight
        )
    }

    /// The dots' run, end to end: `SpaceDotsView.width(forDots:)` at this
    /// bar's scale and without the pill's caps the column's strip adds.
    var dotsWidth: CGFloat {
        let scale = TopBarMetrics.dotScale
        let gaps = CGFloat(max(SpaceDotsView.shown(of: spaces.count) - 1, 0))
        return (Tokens.Metric.spaceDotPitch * gaps + Tokens.Metric.spaceDot) * scale
    }

    /// A dot's chip at this bar's scale — the height of the strip, and the
    /// slot each end dot keeps round it.
    private var chip: CGFloat { Tokens.Metric.spaceDotChip * TopBarMetrics.dotScale }

    override func layout() {
        super.layout()
        // A view moved under a resting pointer, or out from under one, is
        // told nothing by its tracking area — so the name asks where the
        // pointer is rather than keeping a hover it was never told had ended.
        if isHovering, let window {
            isHovering = bounds.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil))
        }
        Tokens.Motion.immediately { placeContents() }
    }

    private func placeContents() {
        name.frame = nameFrame()
        dots.alphaValue = showsDots ? 1 : 0
        // The column's strip, centred under the name. Its slots are a dot's
        // hover chip tall, which is what a click lands on.
        let width = dotsWidth + chip
        dots.frame = NSRect(
            x: ((bounds.width - width) / 2).rounded(),
            y: dotsBaseline,
            width: width,
            height: chip
        )
    }

    private var lineHeight: CGFloat {
        (name.font?.boundingRectForFont.height ?? Tokens.Metric.faviconSize).rounded(.up)
    }

    /// Where the dots stand: the name and the dots together centred on the
    /// plate, the dots underneath.
    private var dotsBaseline: CGFloat {
        ((bounds.height - lineHeight - chip) / 2).rounded()
    }

    private func nameFrame(pushedBy offset: CGFloat = 0) -> NSRect {
        let y = showsDots
            ? dotsBaseline + chip
            : ((bounds.height - lineHeight) / 2).rounded()
        return NSRect(
            x: TopBarMetrics.gap + offset,
            y: y,
            width: max(bounds.width - TopBarMetrics.gap * 2, 0),
            height: lineHeight
        )
    }

    /// §4: the name is not the bar, so a press on it does not move the window.
    /// Everything but a dot answers as the name, so the label and the dots'
    /// strip, which would say it may, are never what a press lands on.
    override var mouseDownCanMoveWindow: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        return hit is SpaceDotView ? hit : self
    }

    /// Kept, not passed on: the window is movable by its background, and a
    /// press nothing takes travels up the responder chain until the window
    /// takes it as the start of a move.
    override func mouseDown(with event: NSEvent) {}

    func applyTokens() {
        name.font = Tokens.TypeScale.topBarSpaceName
        name.textColor = Tokens.Text.primary
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyTokens()
    }
}
