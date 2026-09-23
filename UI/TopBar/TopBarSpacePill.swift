//
//  TopBarSpacePill.swift
//  Luna
//
//  §4's Space switcher, beside the traffic lights: one glass cylinder saying
//  which Space you are in, with an arrow at each end.
//
//      [‹]  Personal  [›]
//
//  The name is the control. §3.5's dot strip answers "which of these" and is
//  right at the foot of a column, where there is a strip of room and no words;
//  a bar has words and no room, and six identical dots on it say less than the
//  one name they stand for. The arrows are the dots' one advantage kept — a
//  Space is one click away — without spending a point per Space to offer it.
//
//  The name pops when it changes, because it is the only thing on the bar that
//  says the whole window has moved. Every other read-out of a Space switch is
//  the tabs redrawing, which looks like tabs redrawing.
//
//  §30.9's swipe is offered here too, with this control as its ruler: the
//  column measures the gesture against the page it slides, and nothing slides
//  here. While the fingers are down the name is pushed aside and fades, so the
//  gesture has a read-out before it commits.
//

import AppKit
import BrowserKit

@MainActor
final class TopBarSpacePill: NSView, TopBarThemed {

    var onSwitch: ((UUID) -> Void)?
    var onSetGradient: ((UUID, GradientPair) -> Void)?
    var onEditSpaces: (() -> Void)?
    var onNewSpace: (() -> Void)?

    private let name = NSTextField(labelWithString: "")
    // Dormant glass, so an arrow that is the drop target lights the way the
    // tab you are on does — see `dropTarget`.
    private let previous = TopBarButton(metric: TopBarMetrics.arrow, glass: .dormant)
    private let next = TopBarButton(metric: TopBarMetrics.arrow, glass: .dormant)
    private let swipe = SpaceSwipeController()
    private var spaces: [Space] = []
    private var activeSpaceID: UUID?
    /// How far the name is pushed at a full Space of travel. A name that moved
    /// the whole width of the cylinder would be gone before the gesture had
    /// decided anything; this is far enough to read as "being pushed aside".
    private static let nameTravel: CGFloat = 12

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        Glass.apply(.control, to: self, cornerRadius: TopBarMetrics.plate.cornerRadius)
        setAccessibilityRole(.group)

        name.lineBreakMode = .byTruncatingTail
        name.cell?.usesSingleLineMode = true
        name.alignment = .center
        addSubview(name)

        build(previous, symbol: "chevron.left", label: String(localized: "Previous Space"), step: -1)
        build(next, symbol: "chevron.right", label: String(localized: "Next Space"), step: 1)

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

    /// The arrows own no material of their own: the cylinder is one piece of
    /// glass, and half of it swelling inside the other half is not a press.
    /// Same rule as §4's action capsule, same reason.
    private func build(_ arrow: TopBarButton, symbol: String, label: String, step: Int) {
        arrow.icon = TopBarButton.symbol(symbol)
        arrow.ownsItsMaterial = false
        arrow.onPressChange = { [weak self] pressed in
            guard let self else { return }
            Tokens.Motion.swell(self, to: pressed ? Tokens.Motion.pressSwell : 1)
        }
        arrow.setAccessibilityLabel(label)
        arrow.toolTip = label
        arrow.target = self
        arrow.action = step < 0 ? #selector(goBack) : #selector(goForward)
        addSubview(arrow)
    }

    func show(spaces: [Space], activeSpaceID: UUID) {
        let moved = self.activeSpaceID != nil && self.activeSpaceID != activeSpaceID
        self.spaces = spaces
        self.activeSpaceID = activeSpaceID
        let index = spaces.firstIndex { $0.id == activeSpaceID }
        previous.isEnabled = (index ?? 0) > 0
        next.isEnabled = index.map { $0 < spaces.count - 1 } ?? false

        let title = index.map { spaces[$0].name } ?? ""
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

    // MARK: - §6.6: a tab carried to the Space next door

    /// The Space an arrow at `point` leads to, with `point` in `space`'s
    /// coordinates. Nil anywhere but on an enabled arrow — an arrow at the end
    /// of the run leads nowhere, and a target that lights up and then refuses
    /// the drop is worse than one that never lights up.
    func neighbourSpace(at point: NSPoint, from space: NSView) -> UUID? {
        let local = convert(point, from: space)
        guard let index = spaces.firstIndex(where: { $0.id == activeSpaceID }) else { return nil }
        for (arrow, step) in [(previous, -1), (next, 1)] where arrow.isEnabled && arrow.frame.contains(local) {
            return spaces[index + step].id
        }
        return nil
    }

    /// The Space a lift is held over, marked on the arrow that leads there.
    var dropTarget: UUID? {
        didSet {
            guard dropTarget != oldValue else { return }
            let index = spaces.firstIndex { $0.id == activeSpaceID }
            let lit = index.flatMap { index in spaces.firstIndex { $0.id == dropTarget }.map { $0 - index } }
            previous.isSelected = lit == -1
            next.isSelected = lit == 1
            // Named while it is the target, so the hand knows where it is about
            // to send the tab before it lets go.
            if let dropTarget, let space = spaces.first(where: { $0.id == dropTarget }) {
                name.stringValue = space.name
            } else {
                name.stringValue = spaces.first { $0.id == activeSpaceID }?.name ?? ""
            }
        }
    }

    // MARK: - The two arrows

    @objc private func goBack() { step(-1) }

    @objc private func goForward() { step(1) }

    private func step(_ delta: Int) {
        guard let index = spaces.firstIndex(where: { $0.id == activeSpaceID }) else { return }
        let target = index + delta
        guard spaces.indices.contains(target) else { return }
        onSwitch?(spaces[target].id)
    }

    // MARK: - §30.9's swipe

    override func scrollWheel(with event: NSEvent) {
        guard !swipe.scrollWheel(with: event) else { return }
        super.scrollWheel(with: event)
    }

    /// The live read-out: the name is pushed the way the fingers are going and
    /// fades as it goes, so the gesture says what it is doing before it does it.
    private func read(_ state: SpaceSwipe) {
        let reach = min(abs(state.travel), 1)
        Tokens.Motion.immediately {
            name.frame = nameFrame(pushedBy: -state.travel * Self.nameTravel)
            name.alphaValue = 1 - reach * 0.7
        }
    }

    private func settle(_ state: SpaceSwipe, committing: Bool) {
        defer {
            Tokens.Motion.immediately {
                name.frame = nameFrame()
                name.alphaValue = 1
            }
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

    /// Two arrows, a word between them, and the cylinder's padding — with the
    /// same ceiling on the word a tab's title has, for the same reason: one
    /// long name must not spend the room the tabs need.
    override var intrinsicContentSize: NSSize {
        let title = min(name.fittingSize.width.rounded(.up), TopBarMetrics.nameCeiling)
        let arrows = TopBarMetrics.arrow.width * 2 + TopBarMetrics.gap * 2
        return NSSize(
            width: TopBarMetrics.groupPlateInset * 2 + arrows + title,
            height: TopBarMetrics.plate.height
        )
    }

    override func layout() {
        super.layout()
        Tokens.Motion.immediately { placeContents() }
    }

    private func placeContents() {
        let inset = TopBarMetrics.groupPlateInset
        let side = TopBarMetrics.arrow.size
        let y = ((bounds.height - side.height) / 2).rounded()
        previous.frame = NSRect(origin: NSPoint(x: inset, y: y), size: side)
        next.frame = NSRect(
            origin: NSPoint(x: bounds.width - inset - side.width, y: y),
            size: side
        )
        name.frame = nameFrame()
    }

    private func nameFrame(pushedBy offset: CGFloat = 0) -> NSRect {
        let line = (name.font?.boundingRectForFont.height ?? Tokens.Metric.faviconSize).rounded(.up)
        let left = previous.frame.maxX + TopBarMetrics.gap
        return NSRect(
            x: left + offset,
            y: ((bounds.height - line) / 2).rounded(),
            width: max(next.frame.minX - TopBarMetrics.gap - left, 0),
            height: line
        )
    }

    /// §4: dragging the bar moves the window, and the cylinder is bar. The
    /// arrows take their own clicks.
    override var mouseDownCanMoveWindow: Bool { true }

    func applyTokens() {
        name.font = Tokens.TypeScale.sidebarRow
        name.textColor = Tokens.Text.primary
        previous.applyTokens()
        next.applyTokens()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyTokens()
    }
}
