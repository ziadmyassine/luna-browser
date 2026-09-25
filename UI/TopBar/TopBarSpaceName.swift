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
//  The name pops when a click changes it, because it is the only thing on the
//  bar that says the whole window has moved. A swipe slides it instead: out of
//  the capsule with the tabs, and in from the other side after them. Either
//  way the capsule grows or shrinks to the new name rather than jumping to it
//  (`widthMorph`), and the bar beside it follows.
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
    /// Every frame of a swipe, held or settling: how far toward the next Space,
    /// in Spaces. §4's bar moves its tabs by it (`TopBarView`).
    var onTravel: ((CGFloat) -> Void)?
    /// A swipe has switched Spaces: which way the old run left (`+1` toward the
    /// next Space), and the spec it left on, so the new one can come in from
    /// the other side at the same pace.
    var onArrive: ((_ direction: CGFloat, _ spec: MotionSpec) -> Void)?

    private let name = NSTextField(labelWithString: "")
    let dots = SpaceDotsView(framed: false)
    private let swipe = SpaceSwipeController()
    private var spaces: [Space] = []
    private var activeSpaceID: UUID?
    private var tracking: NSTrackingArea?
    private var isHovering = false
    private var isSwiping = false
    private lazy var settling = SpaceSwipeSettle(host: self)
    /// The spec a swipe is switching Spaces on, while it switches: the new
    /// name slides in after the tabs (`slideNameIn`) rather than popping, and
    /// the capsule takes its new width on the same clock.
    private var swipeArrival: MotionSpec?
    /// A swipe is switching Spaces, so §4's run slides rather than
    /// cross-fading (`TopBarTabStrip.reload`).
    var arrivesBySwipe: Bool { swipeArrival != nil }

    /// How far the capsule has come from `widthFrom` to the width its name
    /// asks for: 0 is the old width, 1 the new. Read by
    /// `intrinsicContentSize` on every pass, so animating it resizes the
    /// capsule's glass for real, frame by frame, and moves everything Auto
    /// Layout stands beside it. The glass cannot be scaled or clipped into
    /// shape instead — `CommandBarPanel.morph` has the finding.
    @objc dynamic var widthMorph: CGFloat = 1 {
        didSet { invalidateIntrinsicContentSize() }
    }

    private var widthFrom: CGFloat = 0
    /// What the capsule is at or heading to — `morphWidth`.
    private var widthTo: CGFloat = 0

    override static func defaultAnimation(forKey key: NSAnimatablePropertyKey) -> Any? {
        key == "widthMorph" ? CABasicAnimation() : super.defaultAnimation(forKey: key)
    }

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
        // The name slides out of the capsule on a swipe and in from its other
        // side; outside it, it would be drawn over the bar.
        layer?.masksToBounds = true
        name.wantsLayer = true
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
        swipe.span = { [weak self] in self?.swipeSpan ?? 0 }
        swipe.onUpdate = { [weak self] state in self?.read(state) }
        swipe.onFinish = { [weak self] state, speed, committing in
            self?.settle(state, speed: speed, committing: committing)
        }

        applyTokens()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code")
    }

    func show(spaces: [Space], activeSpaceID: UUID) {
        let moved = self.activeSpaceID != nil && self.activeSpaceID != activeSpaceID
        let before = intrinsicContentSize.width
        defer { morphWidth(from: before) }
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
        guard moved, !arrivesBySwipe else { return }
        pop()
    }

    /// The capsule from `before` to the width it now asks for — a new name, a
    /// renamed one, or a dot more or fewer — on the swipe's spec when a swipe
    /// switched, and otherwise on the time §6 gives a Space switch that
    /// nothing is carrying.
    private func morphWidth(from before: CGFloat) {
        let after = naturalWidth
        // Already there, or on its way: a switch refreshes the bar more than
        // once, and each restart would begin the curve again from partway.
        guard abs(after - widthTo) > 0.5 else { return }
        // The first name the capsule shows is not a change of size.
        let changes = widthTo > 0
        widthTo = after
        guard changes, window != nil, !Tokens.Motion.reduceMotion else {
            widthFrom = after
            widthMorph = 1
            return
        }
        widthFrom = before
        widthMorph = 0
        Tokens.Motion.animate(swipeArrival ?? Tokens.Motion.spaceSettleSlowest) { context in
            context.allowsImplicitAnimation = true
            animator().widthMorph = 1
        }
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
        name.textColor = ink
        Tokens.Motion.animate(Tokens.Motion.controlHover) { context in
            context.allowsImplicitAnimation = true
            name.animator().frame = nameFrame()
            dots.animator().alphaValue = shown ? 1 : 0
        }
    }

    // MARK: - §6.2 and §8.2, from the one place a Space is visible on this bar

    /// A right-click opens the same pop-out a press does: the colours used
    /// to be a native menu of thirteen colour names here, the one surface in
    /// Luna a Space's colour was chosen from by reading.
    override func menu(for event: NSEvent) -> NSMenu? {
        presentSpaces()
        return nil
    }

    /// §4's Space pop-out, the one §3.5's pill opens in the column.
    func presentSpaces() {
        guard !spaces.isEmpty else { return }
        SpacePopout.present(from: self, content: SpacePanelContent(
            spaces: spaces,
            activeID: activeSpaceID ?? spaces[0].id,
            switchTo: { [weak self] id in self?.onSwitch?(id) },
            setGradient: { [weak self] id, gradient in self?.onSetGradient?(id, gradient) },
            edit: { [weak self] in self?.onEditSpaces?() },
            new: { [weak self] in self?.onNewSpace?() }
        ))
    }

    // MARK: - Geometry

    /// The name, or the dots under it if they are wider, with a gap either
    /// side — and the same ceiling on the name a tab's title has, for the same
    /// reason: one long name must not spend the room the tabs need.
    override var intrinsicContentSize: NSSize {
        let width = naturalWidth
        return NSSize(
            width: (widthFrom + (width - widthFrom) * widthMorph).rounded(),
            height: TopBarMetrics.lineHeight
        )
    }

    /// The width the name and dots ask for, with no morph in it.
    var naturalWidth: CGFloat {
        let title = min(name.fittingSize.width.rounded(.up), TopBarMetrics.nameCeiling)
        return max(title, dotsWidth) + TopBarMetrics.gap * 2
    }

    /// A Space of swipe, in points of hand: the name, or `nameCeiling` for a
    /// short one. The tabs travel the same distance, one point per point.
    var swipeSpan: CGFloat { max(bounds.width, TopBarMetrics.nameCeiling) }

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
        name.textColor = ink
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

    /// A press on the name opens the Space pop-out. A press that turned into
    /// a swipe never reaches here: the swipe is the scroll wheel's.
    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        presentSpaces()
    }

    func applyTokens() {
        name.font = Tokens.TypeScale.topBarSpaceName
        name.textColor = ink
    }

    /// The capsule's glyphs' rule, so the name reads as one of the bar's
    /// controls: `secondary` at rest, `primary` while it is being aimed at.
    private var ink: NSColor { showsDots ? Tokens.Text.primary : Tokens.Text.secondary }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyTokens()
    }
}

// MARK: - §30.9's swipe

extension TopBarSpaceName {

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
        show(state)
    }

    /// One frame of the swipe, held or settling — the same frame either way,
    /// for `SpaceSwipeSettle`'s reason.
    private func show(_ state: SpaceSwipe) {
        dots.travel = state.travel
        dots.creation = state.creation
        // The name goes the way the tabs go, the whole width of the capsule
        // for a Space of travel, so it leaves with them rather than nudging
        // aside and waiting for the switch to replace it.
        let reach = min(abs(state.travel), 1)
        Tokens.Motion.immediately {
            name.frame = nameFrame(pushedBy: -state.travel * bounds.width)
            name.alphaValue = 1 - reach
        }
        onTravel?(state.travel)
    }

    /// The release: the rest of the way on the speed the hand let go at, then
    /// the switch. It used to snap back to rest and switch in the same frame,
    /// which is two jumps where the column makes one movement.
    private func settle(_ state: SpaceSwipe, speed: CGFloat, committing: Bool) {
        var target = SpaceSwipe.rest
        var commit: (() -> Void)?
        if committing, state.createsSpace {
            commit = { [weak self] in self?.onNewSpace?() }
        } else if committing, let landing = state.landing, spaces.indices.contains(landing) {
            target.travel = state.travel > 0 ? 1 : -1
            let id = spaces[landing].id
            commit = { [weak self] in self?.onSwitch?(id) }
        }
        let spec = Tokens.Motion.spaceSettle(
            across: abs(target.travel - state.travel) * swipeSpan,
            at: abs(speed)
        )
        let direction = target.travel
        settling.run(from: state, to: target, on: spec) { [weak self] frame in
            self?.show(frame)
        } onArrival: { [weak self] in
            guard let self else { return }
            swipeArrival = direction != 0 ? spec : nil
            commit?()
            swipeArrival = nil
            isSwiping = false
            show(.rest)
            if direction != 0 {
                slideNameIn(from: direction, on: spec)
                onArrive?(direction, spec)
            }
            reveal()
        }
    }

    /// The new Space's name coming in from the side the old one did not leave
    /// by, with the tabs and on their spec.
    private func slideNameIn(from direction: CGFloat, on spec: MotionSpec) {
        guard let layer = name.layer, !Tokens.Motion.reduceMotion, spec.duration > 0 else { return }
        let slide = CABasicAnimation(keyPath: "transform.translation.x")
        slide.fromValue = direction * bounds.width
        slide.toValue = 0
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        let group = CAAnimationGroup()
        group.animations = [slide, fade]
        group.duration = spec.duration
        group.timingFunction = spec.timingFunction
        layer.add(group, forKey: "luna.space.slideIn")
    }
}
