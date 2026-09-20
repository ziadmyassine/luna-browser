//
//  SpaceDotsView.swift
//  Luna
//
//  §3.5's Space switcher — the strip of dots at the foot of the sidebar, and
//  §30.9's swipe read out on it. Split out of `SidebarUtilityBar.swift` when
//  the strip grew a gesture: the bar places three clusters and this is one of
//  them, and a file that does both was past SwiftLint's length limit.
//
//  **The dots are laid out from their centres, not from their slots**, and that
//  is the whole of the alignment fix. The strip used to hand each dot
//  `width / count` rounded with `.integral`, which rounds each slot's leading
//  edge down and its trailing edge up — *independently*. Three dots in a 56 pt
//  pill came out in slots 19, 20 and 19 points wide, each dot centred inside
//  its own slot and rounded again, so the gaps measured 18 and 19 pt and the
//  run sat half a point left of centre. At a 6 pt dot a point of difference
//  between two gaps is a sixth of the gap, and the eye reads a row of three as
//  crooked long before it can say why. The slots also overlapped by a point at
//  every seam, which made `spaceID(at:)` — §6.6's drop target — ambiguous
//  exactly where two Spaces meet.
//
//  `centres(count:in:)` instead derives one **integer** pitch for the whole
//  run and centres the run in the pill, so every gap is the same number of
//  points and the two end margins are equal. It is pure and static so the
//  claim is a test rather than a screenshot.
//
//  §8 requires the strip to be usable with Differentiate Without Colour on, so
//  each dot carries the Space's **name** as tooltip and accessibility label and
//  the group reports itself as a tab list with position and count — never "the
//  purple one".
//

import AppKit
import BrowserKit

/// §3.5's Space switcher: one 6 pt dot per Space, the active one at full ink.
@MainActor
final class SpaceDotsView: NSView {

    /// §3.5: the pill widens past this many Spaces.
    static let restingSpaceCount = 3

    var onSwitch: ((UUID) -> Void)?
    var onSetGradient: ((UUID, GradientPair) -> Void)?
    /// Right-click on the strip, on a dot or beside one — §6.2's rows are in
    /// Settings and this is the one place a Space is visible.
    var onEditSpaces: (() -> Void)?
    /// The §30.9 swipe asked for a Space that is not there yet.
    var onNewSpace: (() -> Void)?

    /// Where §30.9's swipe has got to, **in Spaces**: 0 is the active one, +1
    /// the next, −1 the previous, fractional while a finger is down.
    ///
    /// It drives two things at once, and the second is the useful one: the ink
    /// cross-fades between the two dots as the finger moves, and the ring lands
    /// on **the dot you will get if you let go now** — so the gesture states
    /// its own commit threshold instead of leaving it to be discovered.
    var travel: CGFloat = 0 {
        didSet {
            guard travel != oldValue else { return }
            applyTravel()
        }
    }

    /// 0…1: how far past the last Space the finger has gone. 1 is a closed
    /// ring, which is the gesture saying the Space will be created on release.
    var creation: CGFloat = 0 {
        didSet {
            guard creation != oldValue else { return }
            let wasOpen = oldValue > 0
            create.progress = creation
            create.isHidden = creation <= 0
            // The strip makes room for the Space that is about to exist, once,
            // as the ring appears and again as it goes — never per frame. A
            // pill whose width tracked the finger would drag every dot under it
            // back and forth for the whole of the gesture, and the dots are
            // what the gesture is being read on.
            guard wasOpen != (creation > 0) else { return }
            invalidateIntrinsicContentSize()
            superview?.needsLayout = true
        }
    }

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

    private var spaces: [Space] = []
    private var activeSpaceID: UUID?
    private var dots: [SpaceDotView] = []
    private let create = SpaceCreateMarkView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        Glass.apply(.control, to: self, cornerRadius: Tokens.Metric.spaceDotsPill.cornerRadius)
        create.isHidden = true
        addSubview(create)
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
            addSubview(dot, positioned: .below, relativeTo: create)
            return dot
        }
        setAccessibilityChildren(dots)
        applyTravel()
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    // MARK: - Geometry

    /// **One integer pitch for the whole run, and the run centred in the pill.**
    ///
    /// Every gap is then the same whole number of points and the two end
    /// margins are equal, at any count — which is what the old
    /// slot-per-dot-then-round arithmetic could not do at a count that does not
    /// divide the pill evenly, and three is one of those. See the file header.
    ///
    /// `.rounded(.down)` on the pitch rather than `.rounded()`: the run has to
    /// fit inside the pill it is centred in, and a pitch rounded up overflows
    /// it by up to half a point per gap.
    ///
    /// **The parity step is not a rounding nicety, it is the last point.** A
    /// run of whole-point gaps can only sit exactly in the middle of a
    /// whole-point pill if what is left over either side is *even* — and at six
    /// Spaces it is not: 80 pt of pill less a 13 pt pitch leaves 15, which is
    /// 8 pt of margin at one end and 7 at the other. Taking the pitch down by
    /// one point flips the leftover even and the strip is symmetric again. The
    /// alternative is half-point centres, and a 6 pt dot drawn across two
    /// pixels is a blurred dot, which is worse than a dot one point closer to
    /// its neighbour.
    static func centres(count: Int, in width: CGFloat) -> [CGFloat] {
        guard count > 0 else { return [] }
        var pitch = (width / CGFloat(count)).rounded(.down)
        if count > 1, Int(width - pitch * CGFloat(count - 1)) % 2 != 0 { pitch -= 1 }
        let run = pitch * CGFloat(count - 1)
        let first = ((width - run) / 2).rounded()
        return (0..<count).map { first + CGFloat($0) * pitch }
    }

    /// The pill's resting width: §3.5's 56 pt, plus a slot for every Space past
    /// the third and one more while §30.9's `+` is showing.
    override var intrinsicContentSize: NSSize {
        let slots = dots.count + (creation > 0 ? 1 : 0)
        let extra = max(slots - Self.restingSpaceCount, 0)
        return NSSize(
            width: Tokens.Metric.spaceDotsPill.width + CGFloat(extra) * Tokens.Metric.spaceDotsPillGrowth,
            height: Tokens.Metric.spaceDotsPill.height
        )
    }

    /// Each dot view owns a full-height slot and is told where to draw its 6 pt
    /// mark inside it. A 6 pt view would be a 6 pt click and a 6 pt §6.6 drop
    /// target, which no one can hit — and the slots **abut** rather than
    /// overlapping, so the Space a drop lands in is never a question of which
    /// of two frames `first(where:)` happened to reach.
    override func layout() {
        super.layout()
        // Bounds-derived frames never animate — see `Motion.immediately`.
        Tokens.Motion.immediately { placeContents() }
    }

    private func placeContents() {
        guard !dots.isEmpty else { return }
        let slots = dots.count + (creation > 0 ? 1 : 0)
        let centres = Self.centres(count: slots, in: bounds.width)
        for (index, dot) in dots.enumerated() {
            let leading = index == 0 ? 0 : ((centres[index - 1] + centres[index]) / 2).rounded()
            // Only the *last slot* runs out to the pill's edge, and while the
            // `+` is showing that slot is the `+`'s — so the last dot stops
            // half way to it rather than owning the ground the ring stands on.
            let trailing = index == slots - 1
                ? bounds.width
                : ((centres[index] + centres[index + 1]) / 2).rounded()
            dot.frame = NSRect(x: leading, y: 0, width: trailing - leading, height: bounds.height)
            dot.markCentreX = centres[index] - leading
        }
        guard let plus = centres.last, slots > dots.count else { return }
        let side = Tokens.Metric.spaceCreateRing
        create.frame = NSRect(
            x: plus - side / 2,
            y: (bounds.height - side) / 2,
            width: side,
            height: side
        ).pixelAligned
    }

    // MARK: - §30.9's swipe, read out on the strip

    /// The dot the gesture is currently over, and how much ink each one has.
    ///
    /// Nothing wears the ring while the `+` is showing: the gesture has left
    /// the Spaces that exist, and two marks claiming to be the destination is
    /// one more than there is a destination.
    private func applyTravel() {
        guard let activeSpaceID, let active = spaces.firstIndex(where: { $0.id == activeSpaceID }) else { return }
        let indicator = CGFloat(active) + travel
        let landing = creation > 0 ? -1 : Int(indicator.rounded())
        for (index, dot) in dots.enumerated() {
            dot.isActive = dot.space.id == activeSpaceID
            dot.presence = max(0, 1 - abs(CGFloat(index) - indicator))
            dot.wearsRing = index == landing
        }
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
