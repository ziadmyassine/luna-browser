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
//  `centres(count:in:)` instead lays the run out on `Metric.spaceDotPitch` —
//  one constant, the same at every count — and centres it, so every gap is the
//  same whole number of points and the two end margins are equal. The **pill**
//  is then sized to the run rather than the run divided into the pill, which is
//  the other half of the same mistake: a fixed 56 pt pill holding two dots had
//  to stand them 28 pt apart to fill itself. Both are pure and static, so the
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

    /// **One pitch for the whole run, and the run centred in `width`.**
    ///
    /// Every gap is then `Metric.spaceDotPitch` exactly and the two end margins
    /// are equal, at any count — which is what the old
    /// slot-per-dot-then-round arithmetic could not do at a count that does not
    /// divide the pill evenly, and three is one of those. See the file header.
    ///
    /// `width` is a parameter rather than `bounds.width` so the claim can be
    /// tested without a window, and so the `+`'s slot can be taken off the end
    /// before the dots are centred in what is left.
    ///
    /// The one rounding left is `first`, and against `width(forDots:)` it never
    /// fires: what the run does not use is `spaceDot + 2 × cornerRadius`, which
    /// is even. It stays because this is handed a width, and a width it was not
    /// given the arithmetic for is better half a point off centre than half a
    /// point off the pixel grid — a 6 pt dot drawn across two pixels is a
    /// blurred dot.
    static func centres(count: Int, in width: CGFloat) -> [CGFloat] {
        guard count > 0 else { return [] }
        let pitch = Tokens.Metric.spaceDotPitch
        let run = pitch * CGFloat(count - 1)
        let first = ((width - run) / 2).rounded()
        return (0..<count).map { first + CGFloat($0) * pitch }
    }

    /// How wide a pill holding `count` dots is: the run, plus a dot, plus an
    /// end cap either side.
    ///
    /// **The end inset is the pill's own corner radius**, which is not a
    /// coincidence dressed up as a rule: at radius 11 the pill's end is a
    /// half-circle 11 pt deep, so a dot 11 pt from the edge sits exactly on
    /// that cap's centre. Any other number is a dot that looks pushed into the
    /// curve or marooned short of it.
    static func width(forDots count: Int) -> CGFloat {
        Tokens.Metric.spaceDotPitch * CGFloat(max(count - 1, 0))
            + Tokens.Metric.spaceDot
            + 2 * Tokens.Metric.spaceDotsPill.cornerRadius
    }

    /// The slot §30.9's `+` takes at the end of the strip.
    ///
    /// Wider than a dot's pitch, because the ring is wider than a dot: at the
    /// strip's own 12 pt the ring would be drawn over the last Space, which is
    /// the one mark it must not touch.
    static var createSlot: CGFloat { Tokens.Metric.spaceCreateRing + Tokens.Metric.chromeGap }

    override var intrinsicContentSize: NSSize {
        NSSize(
            width: Self.width(forDots: dots.count) + (creation > 0 ? Self.createSlot : 0),
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
        // The `+`'s slot comes off the end first, and the dots are centred in
        // what is left — so making room for a Space slides the existing ones
        // aside rather than squeezing them together.
        let showsCreate = creation > 0
        let strip = bounds.width - (showsCreate ? Self.createSlot : 0)
        let centres = Self.centres(count: dots.count, in: strip)
        for (index, dot) in dots.enumerated() {
            let leading = index == 0 ? 0 : ((centres[index - 1] + centres[index]) / 2).rounded()
            // The last dot runs out to the strip's trailing edge, which is the
            // pill's own unless the `+` has taken a slot off it.
            let trailing = index == dots.count - 1
                ? strip
                : ((centres[index] + centres[index + 1]) / 2).rounded()
            dot.frame = NSRect(x: leading, y: 0, width: trailing - leading, height: bounds.height)
            dot.markCentreX = centres[index] - leading
        }
        guard showsCreate else { return }
        let side = Tokens.Metric.spaceCreateRing
        create.frame = NSRect(
            x: strip + (Self.createSlot - side) / 2,
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
