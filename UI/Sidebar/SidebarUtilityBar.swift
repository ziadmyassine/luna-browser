//
//  SidebarUtilityBar.swift
//  Luna
//
//  §3.5: `[profile avatar 34] ··· [space dots pill 56 × 22] ··· [history 34]`,
//  pinned to the bottom at 52 pt.
//
//  The trailing circle opens the archive page, and is called **History** —
//  that is what a user looking for a page they closed goes looking for, and
//  "archive" is Luna's internal word for the same shelf. It carries a clock
//  glyph for the same reason: a box means storage, a clock means "earlier".
//
//  The dots are the Space switcher (§30.9). §8 requires them to be usable with
//  Differentiate Without Colour on, so each dot carries the Space's **name** as
//  both tooltip and accessibility label, and the group reports itself as a tab
//  list with position and count — never "the purple one".
//

import AppKit
import BrowserKit

@MainActor
final class SidebarUtilityBar: NSView {

    var onProfile: (() -> Void)?
    var onHistory: (() -> Void)?
    var onSwitchSpace: ((UUID) -> Void)?
    /// §8.2 / §13.6: a gradient was chosen from a dot's menu, including the
    /// neutral one. Wire to `BrowserSession.setGradient(_:forSpace:)`.
    var onSetGradient: ((UUID, GradientPair) -> Void)?

    private let avatar = GlassButton(
        shape: Tokens.Metric.bottomCircle,
        symbolName: "person.crop.circle",
        pointSize: Tokens.Metric.glyphSize,
        label: "Profile"
    )
    private let history = GlassButton(
        shape: Tokens.Metric.bottomCircle,
        symbolName: "clock.arrow.circlepath",
        pointSize: Tokens.Metric.glyphSize,
        label: "History"
    )
    private let dots = SpaceDotsView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        avatar.onActivate = { [weak self] in self?.onProfile?() }
        history.onActivate = { [weak self] in self?.onHistory?() }
        dots.onSwitch = { [weak self] id in self?.onSwitchSpace?(id) }
        dots.onSetGradient = { [weak self] space, gradient in self?.onSetGradient?(space, gradient) }
        for view in [avatar, history, dots] { addSubview(view) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    /// §6.4's pop-out stands on this. Exposed rather than the whole bar,
    /// because "beside the History button" is a statement about the button.
    var historyAnchor: NSView { history }

    /// §6.6: the Space a lift held over `point` would move the tab to, with
    /// `point` in `space`'s coordinates.
    func spaceID(at point: NSPoint, from space: NSView) -> UUID? {
        dots.spaceID(at: point, from: space)
    }

    /// The dot the lift is over, marked as such.
    var highlightedSpaceID: UUID? {
        get { dots.highlightedSpaceID }
        set { dots.highlightedSpaceID = newValue }
    }

    func show(spaces: [Space], activeSpaceID: UUID) {
        dots.show(spaces: spaces, activeSpaceID: activeSpaceID)
        needsLayout = true
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: Tokens.Metric.topBarHeight)
    }

    override func layout() {
        super.layout()
        // Bounds-derived frames never animate — see `Motion.immediately`.
        Tokens.Motion.immediately { placeContents() }
    }

    private func placeContents() {
        let inset = Tokens.Metric.rowInset
        let circle = Tokens.Metric.bottomCircle
        let midY = (bounds.height - circle.height) / 2
        avatar.frame = NSRect(x: inset, y: midY, width: circle.width, height: circle.height).pixelAligned
        history.frame = NSRect(
            x: bounds.maxX - inset - circle.width,
            y: midY,
            width: circle.width,
            height: circle.height
        ).pixelAligned
        let pill = dots.intrinsicContentSize
        dots.frame = NSRect(
            x: (bounds.width - pill.width) / 2,
            y: (bounds.height - pill.height) / 2,
            width: pill.width,
            height: pill.height
        ).pixelAligned
    }
}

/// §3.5's Space switcher: one 6 pt dot per Space, the active one at full ink.
@MainActor
final class SpaceDotsView: NSView {

    /// §3.5: the pill widens past this many Spaces.
    private static let restingSpaceCount = 3

    var onSwitch: ((UUID) -> Void)?

    /// §6.6: the Space a lift held over `point` would move the tab to, with
    /// `point` in `space`'s coordinates. Nil anywhere but on a dot.
    func spaceID(at point: NSPoint, from space: NSView) -> UUID? {
        let local = convert(point, from: space)
        return dots.first { $0.frame.contains(local) }?.space.id
    }

    /// The dot the lift is over, marked as such. Nil clears the mark.
    var highlightedSpaceID: UUID? {
        didSet {
            guard highlightedSpaceID != oldValue else { return }
            for dot in dots { dot.isDropTarget = dot.space.id == highlightedSpaceID }
        }
    }
    var onSetGradient: ((UUID, GradientPair) -> Void)?

    private var spaces: [Space] = []
    private var activeSpaceID: UUID?
    private var dots: [SpaceDotView] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        Glass.apply(.control, to: self, cornerRadius: Tokens.Metric.spaceDotsPill.cornerRadius)
        setAccessibilityElement(true)
        setAccessibilityRole(.tabGroup)
        setAccessibilityLabel("Spaces")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    func show(spaces: [Space], activeSpaceID: UUID) {
        self.activeSpaceID = activeSpaceID
        guard spaces != self.spaces else {
            for dot in dots { dot.isActive = dot.space.id == activeSpaceID }
            return
        }
        self.spaces = spaces
        for dot in dots { dot.removeFromSuperview() }
        dots = spaces.enumerated().map { index, space in
            let dot = SpaceDotView(space: space, position: index + 1, of: spaces.count)
            dot.isActive = space.id == activeSpaceID
            dot.onActivate = { [weak self] in self?.onSwitch?(space.id) }
            dot.onSetGradient = { [weak self] gradient in self?.onSetGradient?(space.id, gradient) }
            addSubview(dot)
            return dot
        }
        setAccessibilityChildren(dots)
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    override var intrinsicContentSize: NSSize {
        let extra = max(spaces.count - Self.restingSpaceCount, 0)
        return NSSize(
            width: Tokens.Metric.spaceDotsPill.width + CGFloat(extra) * Tokens.Metric.spaceDotsPillGrowth,
            height: Tokens.Metric.spaceDotsPill.height
        )
    }

    /// Each dot view owns its whole slot — the full pill height and an equal
    /// share of its width — and draws the 6 pt dot inside it. A 6 pt view would
    /// be a 6 pt click and a 6 pt §6.6 drop target, which no one can hit.
    override func layout() {
        super.layout()
        // Bounds-derived frames never animate — see `Motion.immediately`.
        Tokens.Motion.immediately { placeContents() }
    }

    private func placeContents() {
        guard !dots.isEmpty else { return }
        let slot = bounds.width / CGFloat(dots.count)
        for (index, dot) in dots.enumerated() {
            dot.frame = NSRect(x: CGFloat(index) * slot, y: 0, width: slot, height: bounds.height).integral
        }
    }
}

/// One dot. Its own view because it is three things at once: a click target, a
/// §6.6 landing place, and an accessibility element carrying the Space's name.
@MainActor
final class SpaceDotView: NSView {

    let space: Space
    var onActivate: (() -> Void)?
    var onSetGradient: ((GradientPair) -> Void)?
    var isActive = false { didSet { needsDisplay = true } }
    /// §6.6's lift is over this dot. Set by `SpaceDotsView`, which is the only
    /// thing that knows where the lift is.
    var isDropTarget = false { didSet { needsDisplay = true } }
    // A gradient layer, because §8.2a's dot is the Space's own pair of stops
    // rather than a shared ink — `updateLayer` sets `colors` on it.
    private let mark = CAGradientLayer()

    init(space: Space, position: Int, of count: Int) {
        self.space = space
        super.init(frame: .zero)
        wantsLayer = true
        layer?.addSublayer(mark)
        // §8/§21.2: the name, not the gradient, is what identifies a Space.
        toolTip = space.name
        setAccessibilityElement(true)
        setAccessibilityRole(.radioButton)
        setAccessibilityLabel(space.name)
        setAccessibilityValue("\(position) of \(count)")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        let size = Tokens.Metric.spaceDot
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        mark.frame = NSRect(
            x: (bounds.width - size) / 2,
            y: (bounds.height - size) / 2,
            width: size,
            height: size
        ).pixelAligned
        mark.cornerRadius = size / 2
        // §8.2a's full intensity, and the whole point of the twelve pairs: the
        // dots were `Text.primary` / `Text.tertiary`, so every Space looked
        // identical no matter what gradient it carried.
        let stops = Tokens.Gradient.planes(space.gradient, at: .full, in: effectiveAppearance)
        mark.startPoint = CGPoint(x: 0, y: 1)
        mark.endPoint = CGPoint(x: 1, y: 0)
        mark.colors = [stops.start.cgColor, stops.end.cgColor]
        // §3.5's "100 % / 35 %" step, kept — but the inactive dot is now a
        // dimmer version of *its own* colour rather than of a shared ink.
        mark.opacity = isActive ? 1 : 0.45
        // §21.2 Differentiate Without Colour: the active dot is also the only
        // one wearing a ring, so "which Space am I in" never depends on being
        // able to tell two hues apart. The drop ring outranks it — during a
        // §6.6 drag the question is where the tab is about to land.
        mark.borderWidth = isDropTarget || isActive ? Tokens.Metric.hairline : 0
        mark.borderColor = isDropTarget ? Tokens.Accent.tint.cgColor : Tokens.Text.primary.cgColor
        CATransaction.commit()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    /// §30.1: the sidebar's plane moves the window; a control on it does not.
    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onActivate?()
    }

    override func accessibilityPerformPress() -> Bool {
        onActivate?()
        return true
    }

    // MARK: - §8.2 / §13.6 the colour menu

    /// Right-click a dot to recolour its Space, and — the part Arc needed a
    /// help article for — to leave a colour again.
    ///
    /// A menu on the dot rather than a Settings pane because the dot is the one
    /// place a Space is *visible*: Arc's "How Do I Restore the Default Theme"
    /// exists because getting out of a theme was somewhere else entirely, and
    /// Zen has an open issue for not being able to unset a gradient at all.
    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(SidebarMenu.header("Colour for \(space.name)"))
        for (index, gradient) in Tokens.Gradient.spacePalette.enumerated() {
            let item = SidebarMenu.item(title: Tokens.Gradient.spacePaletteNames[index]) { [weak self] in
                self?.onSetGradient?(gradient)
            }
            item.image = SidebarMenu.swatch(gradient, in: effectiveAppearance)
            item.state = gradient == space.gradient ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        // §13.6's one click back to neutral. Always present, never conditional
        // on the Space already carrying a colour — a way out that only appears
        // once you are lost is not a way out.
        let reset = SidebarMenu.item(title: "No Colour") { [weak self] in
            self?.onSetGradient?(Tokens.Gradient.neutral)
        }
        reset.image = SidebarMenu.swatch(Tokens.Gradient.neutral, in: effectiveAppearance)
        reset.state = Tokens.Gradient.isNeutral(space.gradient) ? .on : .off
        menu.addItem(reset)
        menu.addItem(.separator())
        // Arc's own documentation shouts this, and it is the combination that
        // works: colour is per Space, Light/Dark is not. Saying so here is
        // cheaper than the support article that follows from not saying it.
        menu.addItem(SidebarMenu.header("Light and Dark apply to every Space"))
        return menu
    }
}
