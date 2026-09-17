//
//  SidebarUtilityBar.swift
//  Luna
//
//  §3.5: `[profile avatar 34] ··· [space dots pill 56 × 22] ··· [archive 34]`,
//  pinned to the bottom at 52 pt.
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
    var onArchive: (() -> Void)?
    var onSwitchSpace: ((UUID) -> Void)?
    /// §6.6: a tab was dropped on a Space dot.
    var onMoveTabToSpace: ((UUID, UUID) -> Void)?

    private let avatar = GlassButton(
        shape: Tokens.Metric.bottomCircle,
        symbolName: "person.crop.circle",
        pointSize: Tokens.Metric.faviconSize,
        label: "Profile"
    )
    private let archive = GlassButton(
        shape: Tokens.Metric.bottomCircle,
        symbolName: "archivebox",
        pointSize: Tokens.Metric.faviconSize,
        label: "Archive"
    )
    private let dots = SpaceDotsView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        avatar.onActivate = { [weak self] in self?.onProfile?() }
        archive.onActivate = { [weak self] in self?.onArchive?() }
        dots.onSwitch = { [weak self] id in self?.onSwitchSpace?(id) }
        dots.onDrop = { [weak self] tab, space in self?.onMoveTabToSpace?(tab, space) }
        for view in [avatar, archive, dots] { addSubview(view) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
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
        let inset = Tokens.Metric.rowInset
        let circle = Tokens.Metric.bottomCircle
        let midY = (bounds.height - circle.height) / 2
        avatar.frame = NSRect(x: inset, y: midY, width: circle.width, height: circle.height).integral
        archive.frame = NSRect(
            x: bounds.maxX - inset - circle.width,
            y: midY,
            width: circle.width,
            height: circle.height
        ).integral
        let pill = dots.intrinsicContentSize
        dots.frame = NSRect(
            x: (bounds.width - pill.width) / 2,
            y: (bounds.height - pill.height) / 2,
            width: pill.width,
            height: pill.height
        ).integral
    }
}

/// §3.5's Space switcher: one 6 pt dot per Space, the active one at full ink.
@MainActor
final class SpaceDotsView: NSView {

    /// §3.5: the pill widens past this many Spaces.
    private static let restingSpaceCount = 3

    var onSwitch: ((UUID) -> Void)?
    var onDrop: ((UUID, UUID) -> Void)?

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
            dot.onDropTab = { [weak self] tab in self?.onDrop?(tab, space.id) }
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
        guard !dots.isEmpty else { return }
        let slot = bounds.width / CGFloat(dots.count)
        for (index, dot) in dots.enumerated() {
            dot.frame = NSRect(x: CGFloat(index) * slot, y: 0, width: slot, height: bounds.height).integral
        }
    }
}

/// One dot. Its own view because it is three things at once: a click target, a
/// §6.6 drop target, and an accessibility element carrying the Space's name.
@MainActor
final class SpaceDotView: NSView {

    let space: Space
    var onActivate: (() -> Void)?
    var onDropTab: ((UUID) -> Void)?
    var isActive = false { didSet { needsDisplay = true } }

    private var isDropTarget = false { didSet { needsDisplay = true } }
    private let mark = CALayer()

    init(space: Space, position: Int, of count: Int) {
        self.space = space
        super.init(frame: .zero)
        wantsLayer = true
        layer?.addSublayer(mark)
        registerForDraggedTypes([SidebarDrag.tabType])
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
        ).integral
        mark.cornerRadius = size / 2
        // §3.5's "100 % white / 35 %" as Luna's ink tiers: `primary` is the
        // full-strength label colour in both themes, `tertiary` the dimmest
        // that still clears §21.4.
        mark.backgroundColor = (isActive ? Tokens.Text.primary : Tokens.Text.tertiary).cgColor
        mark.borderWidth = isDropTarget ? Tokens.Metric.hairline : 0
        mark.borderColor = isDropTarget ? Tokens.Accent.tint.cgColor : nil
        CATransaction.commit()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onActivate?()
    }

    override func accessibilityPerformPress() -> Bool {
        onActivate?()
        return true
    }

    // MARK: - Drop (§6.6 — drop a tab on a dot to move it to that Space)

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        isDropTarget = SidebarDrag.tabID(in: sender) != nil
        return isDropTarget ? .move : []
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        isDropTarget = false
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        isDropTarget = false
        guard let id = SidebarDrag.tabID(in: sender) else { return false }
        onDropTab?(id)
        return true
    }
}
