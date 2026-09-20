//
//  SpaceCreationView.swift
//  Luna
//
//  The Space that does not exist yet, arriving from the trailing edge of the
//  sidebar as §30.9's swipe runs past the last one.
//
//  **The strip alone was not enough of an answer.** A 14 pt ring at the foot of
//  the column is the right read-out for a gesture you already understand, and
//  no read-out at all for one you are meeting for the first time: the hand is
//  pushing a column of tabs sideways and the only thing that changes is a mark
//  the size of a full stop, 600 pt away from where the eye is. So the same mark
//  is drawn again where the gesture is happening — one disc, the chrome's own
//  34 pt circle, sliding in from the edge the swipe is heading toward.
//
//  **It is the same mark at two sizes, deliberately.** Both carry a `plus` and
//  both wear a ring that closes at exactly the moment letting go would make the
//  Space. The one thing that is not shared is the stroke: a ring reads by its
//  weight *against its own diameter*, so the strip's 1.5 pt on a 14 pt mark is
//  `Metric.spaceCreateDiscLine` here, and drawing the two at the same number of
//  points made this one a hairline round a glass button — too thin to read how
//  full it was, which is the only thing it says. Two different affordances for
//  one gesture would be two things to learn; one affordance drawn to the same
//  weight at both sizes is one.
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
        disc.layer?.addSublayer(ring)
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
        let inset = Tokens.Metric.chromeGapWide
        // **It travels in from off the edge rather than fading in on the spot.**
        // The gesture is a sideways one and the Space is arriving from the side
        // it is heading toward; a mark that simply appeared would be a badge on
        // the column rather than something entering it.
        let reach = max(0, min(progress, 1))
        let resting = bounds.maxX - inset - side
        let travel = bounds.maxX - resting
        disc.frame = NSRect(
            x: resting + travel * (1 - reach),
            y: (bounds.height - side) / 2,
            width: side,
            height: side
        ).pixelAligned
        glyph.frame = NSRect(
            x: (side - Tokens.Metric.glyphSize) / 2,
            y: (side - Tokens.Metric.glyphSize) / 2,
            width: Tokens.Metric.glyphSize,
            height: Tokens.Metric.glyphSize
        ).pixelAligned
        // The glass arrives before the ink does: at the moment the disc clears
        // the edge the finger has not said it means it yet.
        alphaValue = min(reach * 2, 1)
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        let side = Tokens.Metric.bottomCircle.width
        let line = Tokens.Metric.spaceCreateDiscLine
        let circle = CGRect(origin: .zero, size: CGSize(width: side, height: side))
            .insetBy(dx: line / 2, dy: line / 2)
        Tokens.Motion.immediately {
            // Clockwise on screen from 12 o'clock, which is the direction every
            // progress ring on this platform sweeps — and the direction the one
            // in the §3.5 strip sweeps, because they are the same mark.
            let path = CGMutablePath()
            path.addArc(
                center: CGPoint(x: side / 2, y: side / 2),
                radius: circle.width / 2,
                startAngle: .pi / 2,
                endAngle: .pi / 2 - 2 * .pi,
                clockwise: true
            )
            ring.path = path
            ring.lineWidth = line
            ring.strokeColor = Tokens.Text.primary.cgColor
            ring.strokeEnd = max(0, min(progress, 1))
            glyph.contentTintColor = Tokens.Text.primary
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}
