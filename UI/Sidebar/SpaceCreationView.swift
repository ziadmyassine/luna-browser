//
//  SpaceCreationView.swift
//  Luna
//
//  The Space that does not exist yet, arriving from the trailing edge of the
//  sidebar as §30.9's swipe runs past the last one.
//
//  The strip alone was not enough of an answer. A 14 pt ring at the foot of the
//  column reads for a gesture you already understand and not at all for one you
//  are meeting first: the hand pushes a column of tabs sideways and the only
//  thing that changes is a mark the size of a full stop, 600 pt from where the
//  eye is. So the same mark is drawn where the gesture is happening — one disc,
//  the chrome's own 34 pt circle, sliding in from the edge the swipe heads for.
//
//  One of these, where there used to be two. A 14 pt copy stood at the end of
//  the §3.5 strip on the reasoning that one affordance at two sizes is one thing
//  to learn; in the hand it was the opposite, because the strip answers which
//  Space and a `+` in it answers a different question.
//
//  The ring is drawn around the disc, not on it. A stroke on a 34 pt glass
//  button's own edge takes a bite out of the button and has to be hairline-thin
//  to avoid looking like a border; drawn `Metric.spaceCreateRing` across, it is
//  a progress ring with a button inside it and can carry the weight it needs to
//  be read from the far side of the column.
//
//  It draws nothing at rest and never hit-tests: this is a read-out of
//  something happening in the hand, not a button. The `+` a pointer can press
//  is in the footer's menu (`SidebarMenu.spaces`).
//

import AppKit

/// §30.9's `+`, at the size the sidebar reads it at.
@MainActor
final class SpaceCreationView: NSView {

    /// 0…1, from `SpaceSwipe.creation`. 1 is a closed ring.
    var progress: CGFloat = 0 {
        didSet {
            guard progress != oldValue else { return }
            isHidden = progress <= 0
            needsLayout = true
            needsDisplay = true
        }
    }

    private let disc = NSView()
    private let ring = CAShapeLayer()
    private let glyph = NSImageView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isHidden = true
        disc.wantsLayer = true
        disc.layer?.cornerCurve = .continuous
        Glass.apply(.control, to: disc, cornerRadius: Tokens.Metric.bottomCircle.cornerRadius)
        ring.fillColor = nil
        ring.lineCap = .round
        // On this view's own layer rather than the disc's: it is bigger than
        // the disc, and a sublayer is clipped by nothing but it would be
        // centred on the wrong thing.
        wantsLayer = true
        layer?.addSublayer(ring)
        glyph.image = NSImage(systemSymbolName: "plus", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: Tokens.Metric.glyphSize, weight: .regular))
        disc.addSubview(glyph)
        addSubview(disc)
        // A read-out, not a control: VoiceOver is told about the new Space when
        // there is one, by the list that gains it.
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    /// Never takes a click. The gesture owns the pointer for as long as this is
    /// on screen, and a disc that swallowed a stray click would leave the tab
    /// under it unreachable.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        // Bounds-derived, so it may never animate — see `Motion.immediately`.
        Tokens.Motion.immediately { placeContents() }
    }

    private func placeContents() {
        let side = Tokens.Metric.bottomCircle.width
        let hoop = Tokens.Metric.spaceCreateRing
        let inset = Tokens.Metric.chromeGapWide
        // It travels in from off the edge rather than fading in on the spot.
        // The gesture is a sideways one and the Space is arriving from the side
        // it is heading toward; a mark that simply appeared would be a badge on
        // the column rather than something entering it.
        //
        // The ring is what is inset from the edge, not the disc: it is the
        // outermost thing drawn, so it is what has to clear the sidebar's
        // margin.
        // The disc arrives on its own clock, and it is a faster one than the
        // ring's. The sweep is the whole asking price now — a page of hand —
        // and a `+` paced by it would still be crossing the column when the
        // gesture was half paid for. It lands in the first `spaceCreateEntrance`
        // of the sweep, which is the shape the gesture is described in: a thing
        // that appears, and then a thing that fills.
        let arrival = max(0, min(progress / Tokens.Metric.spaceCreateEntrance, 1))
        let resting = bounds.maxX - inset - hoop
        let travel = bounds.maxX - resting
        // Not snapped to the pixel grid, for `SpaceDotView`'s reason and
        // more so: this disc exists only while it is moving — it is hidden at
        // rest — so there is no settled position for alignment to make crisp,
        // and rounding its origin turned a 280 pt glide into 280 visible steps
        // under a hand that was moving slowly and deliberately. Down the column
        // it is snapped, because that is a position that never moves.
        let hoopRect = NSRect(
            x: resting + travel * (1 - arrival),
            y: ((bounds.height - hoop) / 2).rounded(),
            width: hoop,
            height: hoop
        )
        disc.frame = hoopRect.insetBy(dx: (hoop - side) / 2, dy: (hoop - side) / 2)
        glyph.frame = NSRect(
            x: (side - Tokens.Metric.glyphSize) / 2,
            y: (side - Tokens.Metric.glyphSize) / 2,
            width: Tokens.Metric.glyphSize,
            height: Tokens.Metric.glyphSize
        ).pixelAligned
        drawRing(in: hoopRect)
        // The glass arrives before the ink does: at the moment the disc clears
        // the edge the finger has not said it means it yet.
        alphaValue = min(arrival * 2, 1)
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        Tokens.Motion.immediately {
            drawRing(in: ring.frame)
            glyph.contentTintColor = Tokens.Text.primary
        }
    }

    /// The hoop, its sweep and its ink. Called from both passes: the frame is
    /// the layout's answer and the fill is the appearance's, and the ring needs
    /// whichever of the two just changed.
    private func drawRing(in rect: NSRect) {
        guard rect.width > 0 else { return }
        let line = Tokens.Metric.spaceCreateRingLine
        Tokens.Motion.immediately {
            ring.frame = rect
            // Clockwise on screen from 12 o'clock, which is the direction every
            // progress ring on this platform sweeps.
            let path = CGMutablePath()
            path.addArc(
                center: CGPoint(x: rect.width / 2, y: rect.height / 2),
                radius: (rect.width - line) / 2,
                startAngle: .pi / 2,
                endAngle: .pi / 2 - 2 * .pi,
                clockwise: true
            )
            ring.path = path
            ring.lineWidth = line
            ring.strokeColor = Tokens.Text.primary.cgColor
            ring.strokeEnd = max(0, min(progress, 1))
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}
