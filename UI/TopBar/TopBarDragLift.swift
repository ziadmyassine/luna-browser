//
//  TopBarDragLift.swift
//  Luna
//
//  The chip under the pointer while a tab is being moved along §4's bar — see
//  `TopBarTabDrag.swift` for the gesture that drives it.
//
//  It is the chip, not a picture of the chip: the same capsule, the same
//  favicon at the same inset, the same title in the same face. `TopBarButton`
//  itself cannot be it, because a chip's shape is fixed at birth and this one
//  changes — a tab carried across the hairline goes from a titled capsule to a
//  bare circle and back, and that morph is two frames and an alpha inside one
//  animation rather than one view being swapped for another.
//
//  It carries §3.4's selected fill the whole time. A tab in the air is the tab
//  you are about to be on — the drop selects it — so it wears what the tab you
//  are on wears, and nothing about the run underneath has to change to say it.
//

import AppKit

@MainActor
final class TopBarDragLift: NSView {

    /// A bare circle (§3.3, §3.4b) or a titled capsule (today's tabs).
    var style: TopBarTabStyle = .chip {
        didSet {
            guard style != oldValue else { return }
            needsLayout = true
        }
    }

    private let fill = NSView()
    private let icon = NSImageView()
    private let title = NSTextField(labelWithString: "")

    init(icon image: NSImage?, title text: String) {
        super.init(frame: .zero)
        wantsLayer = true
        // §5's shadow, the one drop shadow in the chrome, and the only thing
        // that says "this is off the surface" without recolouring anything.
        layer?.masksToBounds = false

        fill.wantsLayer = true
        fill.layer?.cornerCurve = .circular
        addSubview(fill)

        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.image = image
        addSubview(icon)

        title.lineBreakMode = .byTruncatingTail
        title.cell?.usesSingleLineMode = true
        title.stringValue = text
        addSubview(title)

        setAccessibilityElement(false)
        applyTokens()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code")
    }

    /// How wide this lift is in each of the two shapes — what the gap the run
    /// opens for it has to be.
    func width(as style: TopBarTabStyle) -> CGFloat {
        guard style == .chip else { return TopBarMetrics.tile.width }
        let text = title.fittingSize.width.rounded(.up)
        let width = TopBarMetrics.chipInset * 2 + TopBarMetrics.glyph + TopBarMetrics.gap + text
        return min(max(width, TopBarMetrics.chipFloor), TopBarMetrics.chipCeiling)
    }

    // MARK: - Entrance and exit

    /// §6's `tabInsert`: the chip leaves the bar. A shadow and a percent of
    /// scale, which together read as "picked up" without moving it — the
    /// pointer has not gone anywhere yet when this runs.
    func lift() {
        applyShadow()
        guard !Tokens.Motion.reduceMotion else { return }
        layer?.shadowOpacity = 0
        Tokens.Motion.animate(Tokens.Motion.tabInsert) { context in
            context.allowsImplicitAnimation = true
            self.layer?.shadowOpacity = 1
        }
    }

    /// Fades out where it stands. The run has already been told to close its
    /// gap, so the chip it is standing in for is on its way back under it.
    func drop() {
        Tokens.Motion.animate(Tokens.Motion.controlHover) { context in
            context.allowsImplicitAnimation = true
            animator().alphaValue = 0
        } completion: { [self] in
            MainActor.assumeIsolated { removeFromSuperview() }
        }
    }

    /// Comes to rest in the gap, then hands over. `commit` runs when it lands
    /// rather than when it is released: the real chip stays out of the run
    /// until the lift is standing exactly where it will be, which is what makes
    /// the hand-off invisible.
    func settle(into frame: NSRect, then commit: @escaping @MainActor @Sendable () -> Void) {
        guard !Tokens.Motion.reduceMotion else {
            self.frame = frame
            commit()
            removeFromSuperview()
            return
        }
        Tokens.Motion.animate(Tokens.Motion.tabInsert) { context in
            context.allowsImplicitAnimation = true
            animator().frame = frame
        } completion: { [self] in
            MainActor.assumeIsolated {
                layoutContents()
                commit()
                drop()
            }
        }
    }

    // MARK: - Geometry

    /// Moves the lift, and — when `animated` — morphs it between the two shapes
    /// on the way. A tab crossing the hairline changes what it is, and that is
    /// exactly the thing that should be seen happening.
    func apply(frame: NSRect, style: TopBarTabStyle, animated: Bool) {
        self.style = style
        guard animated, !Tokens.Motion.reduceMotion else {
            Tokens.Motion.immediately {
                self.frame = frame
                layoutContents()
            }
            return
        }
        Tokens.Motion.animate(Tokens.Motion.tabInsert) { context in
            context.allowsImplicitAnimation = true
            animator().frame = frame
            layoutContents()
        }
    }

    override func layout() {
        super.layout()
        Tokens.Motion.immediately { layoutContents() }
    }

    private func layoutContents() {
        fill.frame = bounds
        fill.layer?.cornerRadius = bounds.height / 2
        let glyph = TopBarMetrics.glyph
        let y = ((bounds.height - glyph) / 2).rounded()
        guard style == .chip else {
            icon.frame = NSRect(x: ((bounds.width - glyph) / 2).rounded(), y: y, width: glyph, height: glyph)
            title.alphaValue = 0
            return
        }
        icon.frame = NSRect(x: TopBarMetrics.chipInset, y: y, width: glyph, height: glyph)
        let textX = icon.frame.maxX + TopBarMetrics.gap
        let line = (title.font?.boundingRectForFont.height ?? glyph).rounded(.up)
        title.frame = NSRect(
            x: textX,
            y: ((bounds.height - line) / 2).rounded(),
            width: max(bounds.width - TopBarMetrics.chipInset - textX, 0),
            height: line
        )
        title.alphaValue = 1
    }

    // MARK: - Appearance

    private func applyTokens() {
        title.font = Tokens.TypeScale.sidebarRow
        title.textColor = Tokens.Text.primary
        icon.contentTintColor = Tokens.Text.primary
        effectiveAppearance.performAsCurrentDrawingAppearance {
            self.fill.layer?.backgroundColor = Tokens.Surface.selected.cgColor
        }
        applyShadow()
    }

    private func applyShadow() {
        guard let layer else { return }
        Tokens.Shadow.popover.apply(to: layer, in: effectiveAppearance)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyTokens()
    }

    /// The lift is under the pointer for the whole gesture and must never take
    /// an event: the tracking loop owns them.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
