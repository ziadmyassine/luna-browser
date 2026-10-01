//
//  SpaceDotsView.swift
//  Luna
//
//  §3.5's Space switcher — the strip of dots at the foot of the sidebar, and
//  §30.9's swipe read out on it.
//
//  The dots are laid out from their centres on `Metric.spaceDotPitch`, not by
//  dividing the pill into slots: `width / count` rounded per slot left three
//  dots in 56 pt with 18 and 19 pt gaps, half a point off centre, and slots
//  overlapping at the seams where `spaceID(at:)` must be unambiguous. The pill
//  is sized to the run. Dots only — the `+` is read in the column.
//
//  Three show at a time (`Metric.spaceDotWindow`; twelve were too small to count
//  or hit), the indicator held in the middle and the run sliding continuously
//  with the swipe. Every dot stays an accessibility child, named, for §8.
//

import AppKit
import BrowserKit

/// §3.5's Space switcher: one 6 pt dot per Space, the active one at full ink.
@MainActor
final class SpaceDotsView: NSView {

    var onSwitch: ((UUID) -> Void)?
    var onSetGradient: ((UUID, GradientPair) -> Void)?
    /// Right-click on the strip, on a dot or beside one — §6.2's rows are in
    /// Settings and this is the one place a Space is visible.
    var onEditSpaces: (() -> Void)?
    /// The §30.9 swipe asked for a Space that is not there yet.
    var onNewSpace: (() -> Void)?

    /// Where §30.9's swipe has got to, in Spaces: 0 is the active one, +1
    /// the next, −1 the previous, fractional while a finger is down.
    ///
    /// It drives two things: the ink cross-fades between the two dots as the
    /// finger moves, and the ring lands on the dot you will get if you let go
    /// now, so the gesture states its own commit threshold.
    var travel: CGFloat = 0 {
        didSet {
            guard travel != oldValue else { return }
            applyTravel()
        }
    }

    /// 0…1: how far past the last Space the finger has gone.
    ///
    /// Nothing on the strip is drawn for it — the `+` and the ring live in the
    /// column. It is read here for one thing: past the last Space there is no
    /// Space to land on, so no dot may wear the ring saying there is.
    var creation: CGFloat = 0 {
        didSet {
            guard creation != oldValue else { return }
            applyTravel()
        }
    }

    /// §6.6: the Space a lift held over `point` would move the tab to, with
    /// `point` in `space`'s coordinates. Nil anywhere but on a dot.
    func spaceID(at point: NSPoint, from space: NSView) -> UUID? {
        let local = convert(point, from: space)
        // `!isHidden` because a dot scrolled out of the window still has a
        // frame, off the end of the pill — and a drop must never land in a
        // Space the strip is not showing.
        return dots.first { !$0.isHidden && $0.frame.contains(local) }?.space.id
    }

    /// The dot the lift is over, marked as such. Nil clears the mark.
    var highlightedSpaceID: UUID? {
        didSet {
            guard highlightedSpaceID != oldValue else { return }
            for dot in dots { dot.isDropTarget = dot.space.id == highlightedSpaceID }
        }
    }

    /// The dots, their chips and their pitch as a fraction of §3.5's. One
    /// in the column; §4's plate draws them a size down, under a smaller name.
    var dotScale: CGFloat = 1 {
        didSet {
            guard dotScale != oldValue else { return }
            for dot in dots { dot.scale = dotScale }
            needsLayout = true
        }
    }

    private var spaces: [Space] = []
    private var activeSpaceID: UUID?
    private var dots: [SpaceDotView] = []

    /// - Parameter framed: whether the strip is its own pill of glass. §4's
    ///   plate passes false: its dots stand on the plate's glass, under the
    ///   Space's name, and a pill inside a plate is a second material.
    init(frame frameRect: NSRect = .zero, framed: Bool = true) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        if framed {
            Glass.apply(.control, to: self, cornerRadius: Tokens.Metric.spaceDotsPill.cornerRadius)
            // The window's edge: dots outside it are laid out where they belong
            // and cut off by the pill, which is what lets the run slide rather
            // than re-deal itself every time the indicator moves.
            layer?.masksToBounds = true
        }
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
            applyTravel()
            return
        }
        self.spaces = spaces
        for dot in dots { dot.removeFromSuperview() }
        dots = spaces.enumerated().map { index, space in
            let dot = SpaceDotView(space: space, position: index + 1, of: spaces.count)
            dot.onActivate = { [weak self] in self?.onSwitch?(space.id) }
            dot.onSetGradient = { [weak self] gradient in self?.onSetGradient?(space.id, gradient) }
            dot.onEditSpaces = { [weak self] in self?.onEditSpaces?() }
            // The pill is what a press is against. A dot is 6 pt of ink with
            // no material of its own; this strip is one piece of glass holding
            // all of them, so it takes §6's swell on their behalf, as
            // `NavCluster` does for its two bare chevrons.
            dot.onPressChange = { [weak self] pressed in self?.setPressed(pressed) }
            dot.scale = dotScale
            addSubview(dot)
            return dot
        }
        setAccessibilityChildren(dots)
        applyTravel()
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    // MARK: - Geometry

    /// One pitch for the whole run, and the window centred in `width`: every
    /// gap is `Metric.spaceDotPitch` exactly and the end margins are equal, at
    /// any count. `width` is a parameter so that can be tested without a window.
    ///
    /// `start` is the index at the window's leading slot, fractional while a
    /// swipe moves it. Centres outside the window come back outside `width`;
    /// the pill clips them and `alpha(forDot:from:)` fades them.
    ///
    /// `first` is rounded, though against `width(forDots:)` that never fires:
    /// for a width it was not given, half a point off centre beats a 6 pt dot
    /// blurred across two pixels.
    static func centres(
        count: Int,
        in width: CGFloat,
        from start: CGFloat = 0,
        pitch: CGFloat = Tokens.Metric.spaceDotPitch
    ) -> [CGFloat] {
        guard count > 0 else { return [] }
        let run = pitch * CGFloat(shown(of: count) - 1)
        let first = ((width - run) / 2).rounded()
        return (0..<count).map { first + (CGFloat($0) - start) * pitch }
    }

    /// How many dots the pill is built to hold out of `count` — the window, or
    /// the whole run when it is shorter than one.
    static func shown(of count: Int) -> Int {
        min(count, Tokens.Metric.spaceDotWindow)
    }

    /// The index standing in the window's leading slot, with the indicator
    /// held in the middle of the window and the run stopped at both ends.
    ///
    /// Continuous on purpose: a window that jumped a whole slot when the
    /// indicator crossed a boundary would move the strip in a direction the
    /// fingers are not, halfway through a gesture whose job is to be followed.
    /// The clamps stop the first and last Spaces drifting off their own pill.
    static func windowStart(indicator: CGFloat, count: Int) -> CGFloat {
        let window = CGFloat(Tokens.Metric.spaceDotWindow)
        guard CGFloat(count) > window else { return 0 }
        return min(max(indicator - (window - 1) / 2, 0), CGFloat(count) - window)
    }

    /// How opaque the dot at `index` is, given where the window is standing.
    ///
    /// Full inside the window, out over the slot either side of it. The pill
    /// clips as well, so the fade is what stops a dot being cut in half on
    /// its way out rather than what hides it.
    static func alpha(forDot index: Int, from start: CGFloat) -> CGFloat {
        let position = CGFloat(index) - start
        let outside = max(-position, position - CGFloat(Tokens.Metric.spaceDotWindow - 1))
        return min(max(1 - outside, 0), 1)
    }

    /// How wide a pill holding `count` dots is: the run it shows, plus a dot,
    /// plus an end cap either side.
    ///
    /// The end inset is the pill's own corner radius: at radius 11 the pill's
    /// end is a half-circle 11 pt deep, so a dot 11 pt from the edge sits on
    /// that cap's centre. Any other number looks pushed into the curve or
    /// marooned short of it.
    ///
    /// It stops growing at `Metric.spaceDotWindow`: past three Spaces the strip
    /// scrolls instead of widening.
    static func width(forDots count: Int) -> CGFloat {
        Tokens.Metric.spaceDotPitch * CGFloat(max(shown(of: count) - 1, 0))
            + Tokens.Metric.spaceDot
            + 2 * Tokens.Metric.spaceDotsPill.cornerRadius
    }

    override var intrinsicContentSize: NSSize {
        NSSize(
            width: Self.width(forDots: dots.count),
            height: Tokens.Metric.spaceDotsPill.height
        )
    }

    /// Each dot view owns a full-height slot and is told where to draw its 6 pt
    /// mark inside it: a 6 pt view would be a 6 pt click and a 6 pt §6.6 drop
    /// target. The slots abut rather than overlap, so the Space a drop lands in
    /// is never a question of which frame `first(where:)` reached.
    override func layout() {
        super.layout()
        // Bounds-derived frames never animate — see `Motion.immediately`.
        Tokens.Motion.immediately { placeContents() }
    }

    /// Where the read-out is standing, in dot indices: the active Space plus
    /// however much of a Space the swipe has covered.
    private var indicator: CGFloat {
        guard let activeSpaceID, let active = spaces.firstIndex(where: { $0.id == activeSpaceID }) else { return 0 }
        return CGFloat(active) + travel
    }

    private func placeContents() {
        guard !dots.isEmpty else { return }
        let strip = bounds.width
        let start = Self.windowStart(indicator: indicator, count: dots.count)
        let pitch = Tokens.Metric.spaceDotPitch * dotScale
        let centres = Self.centres(count: dots.count, in: strip, from: start, pitch: pitch)
        for (index, dot) in dots.enumerated() {
            // The window's two outermost slots run out to the pill's edges when
            // the whole run fits; when it does not, every slot is its own half
            // pitch either side and the ones off the end are clipped away.
            let leading = index == 0
                ? min(centres[index] - pitch / 2, 0)
                : ((centres[index - 1] + centres[index]) / 2).rounded()
            let trailing = index == dots.count - 1
                ? max(centres[index] + pitch / 2, strip)
                : ((centres[index] + centres[index + 1]) / 2).rounded()
            dot.frame = NSRect(x: leading, y: 0, width: trailing - leading, height: bounds.height)
            dot.markCentreX = centres[index] - leading
            let alpha = Self.alpha(forDot: index, from: start)
            dot.alphaValue = alpha
            dot.isHidden = alpha <= 0
        }
    }

    // MARK: - §30.9's swipe, read out on the strip

    /// The dot the gesture is currently over, how much ink each one has, and
    /// where the window is standing.
    ///
    /// Nothing wears the ring while the `+` is showing: the gesture has left
    /// the Spaces that exist, so there is no destination for a ring to mark.
    /// Nor with one Space: the ring tells one dot from the others, and a lone
    /// dot has none to be told from.
    private func applyTravel() {
        guard let activeSpaceID, spaces.contains(where: { $0.id == activeSpaceID }) else { return }
        let indicator = self.indicator
        let landing = creation > 0 ? -1 : Int(indicator.rounded())
        for (index, dot) in dots.enumerated() {
            dot.isActive = dot.space.id == activeSpaceID
            dot.presence = max(0, 1 - abs(CGFloat(index) - indicator))
            dot.wearsRing = index == landing && dots.count > 1
        }
        // The run slides with the finger, so every frame of the swipe is a
        // placement — not a repaint of dots that stayed where they were.
        Tokens.Motion.immediately { placeContents() }
    }

    /// §6's `controlPress`, on behalf of whichever dot is down.
    private func setPressed(_ pressed: Bool) {
        Tokens.Motion.swell(self, to: pressed ? Tokens.Motion.pressSwell : 1)
    }

    // MARK: - §6.2 from the one place a Space is visible

    /// Right-click on the strip but not on a dot. `SpaceDotView` answers for
    /// the dots themselves, with the colours first — see its `menu(for:)`.
    override func menu(for event: NSEvent) -> NSMenu? {
        SidebarMenu.spaces(
            edit: { [weak self] in self?.onEditSpaces?() },
            new: { [weak self] in self?.onNewSpace?() }
        )
    }
}
