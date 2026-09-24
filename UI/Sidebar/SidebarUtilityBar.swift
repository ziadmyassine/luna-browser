//
//  SidebarUtilityBar.swift
//  Luna
//
//  §3.5: `[Space pill] ··· [dots 56 × 22] ··· [downloads | history]`, pinned
//  to the bottom at 52 pt, all three on one bottom edge.
//
//  The trailing circle opens the archive page, and is called History —
//  that is what a user looking for a page they closed goes looking for, and
//  "archive" is Luna's internal word for the same shelf. It carries a clock
//  glyph for the same reason: a box means storage, a clock means "earlier".
//
//  Downloads sits beside it, as its pair, in one cylinder. They are the
//  same kind of thing — the shelf of what you already have, glanced at rather
//  than worked in, both opening as a pop-out that stands on its own button —
//  and §4's action capsule pairs the same two at the other end of the window,
//  in one piece of glass. So does this: see `SidebarActionCapsule` for why two
//  discs 5 pt apart read as two controls and one cylinder reads as a pair. The
//  alternative home was the §3.1 control row at the head, which is where
//  actions on this page live; a finished download is not one of those.
//
//  The pair is what set §1's sidebar minimum: three clusters and a centred pill
//  need 190 pt, and `Metric.sidebarWidth` records the arithmetic. Below the
//  width where the pill still fits between the outer two it is centred in what
//  is left rather than in the bar — see `placeContents`.
//
//  The dots are the Space switcher (§30.9) and live in `SpaceDotsView.swift`;
//  the Space pill that names them is `SidebarSpacePill.swift`.
//

import AppKit
import BrowserKit

@MainActor
final class SidebarUtilityBar: NSView {

    /// Told when the Space pill is pressed, before its menu opens.
    var onProfile: (() -> Void)?
    /// §6.2's rows, for the Space pill's way into Settings.
    var onManageProfiles: (() -> Void)?
    private var space: String?
    var onHistory: (() -> Void)?
    var onDownloads: (() -> Void)?
    var onSwitchSpace: ((UUID) -> Void)?
    /// §8.2 / §13.6: a gradient was chosen from a dot's menu, including the
    /// neutral one. Wire to `BrowserSession.setGradient(_:forSpace:)`.
    var onSetGradient: ((UUID, GradientPair) -> Void)?
    /// §6.2 from the foot of the sidebar: open Settings on the Spaces section.
    var onEditSpaces: (() -> Void)?
    /// §6.1 from the same menu, and from §30.9's swipe past the last Space.
    var onNewSpace: (() -> Void)?

    /// §3.5's Space pill, where the Profile avatar was: the active Space's
    /// name, §9's picture when it has one, and §9's fan-out on its tooltip.
    ///
    /// The dots say which Space by colour and position alone, so the name has
    /// to be somewhere in the column. It was a caption over the dots until the
    /// Space got the same cylinder here that it has at the end of §4's bar.
    let spacePill = SidebarSpacePill()
    /// The same two glyphs §4's capsule uses, in the same order, so the pair is
    /// recognisably the same pair in both layouts.
    private var library: SidebarActionCapsule!
    /// Bare dots, with no pill of glass of their own: between two glass
    /// controls a third piece of glass made the foot read as three buttons.
    private let dots = SpaceDotsView(framed: false)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        library = SidebarActionCapsule(items: [
            (symbolName: "arrow.down.to.line", label: String(localized: "Downloads"),
             action: { [weak self] in self?.onDownloads?() }),
            (symbolName: "clock.arrow.circlepath", label: String(localized: "History"),
             action: { [weak self] in self?.onHistory?() })
        ])
        let pillButton = spacePill.button
        pillButton.onActivate = { [weak self, weak pillButton] in
            guard let self, let pillButton else { return }
            onProfile?()
            // A press opens it where a right-click would, which is what every
            // other pop-out in this bar does (`SidebarActionCapsule`).
            SidebarMenu.profile(
                name: space,
                manage: { [weak self] in self?.onManageProfiles?() }
            ).popUp(positioning: nil, at: NSPoint(x: 0, y: pillButton.bounds.maxY), in: pillButton)
        }
        // The pill's edge was what cut off the dots outside §30.9's window of
        // three; without the glass the strip still has to.
        dots.layer?.masksToBounds = true
        dots.onSwitch = { [weak self] id in self?.onSwitchSpace?(id) }
        dots.onSetGradient = { [weak self] space, gradient in self?.onSetGradient?(space, gradient) }
        dots.onEditSpaces = { [weak self] in self?.onEditSpaces?() }
        dots.onNewSpace = { [weak self] in self?.onNewSpace?() }
        for view in [spacePill, library, dots] as [NSView] { addSubview(view) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    /// §6.4's pop-out stands on this. Exposed rather than the whole bar,
    /// because "beside the History button" is a statement about the button.
    var historyAnchor: NSView { library.button(at: 1) }

    /// §15.3's pop-out stands on this, for the same reason.
    var downloadsAnchor: NSView { library.button(at: 0) }

    /// §5.0's flight lands on that button and the cylinder catches it —
    /// the glyph is `GlassMode.none` and has nothing of its own to bulge, so
    /// this is the same hand-up the press already does. See
    /// `SidebarActionCapsule`.
    var downloadsCatcher: NSView { library }

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

    /// §30.9's swipe, read out on the strip. See `SpaceDotsView.travel`.
    var spaceTravel: CGFloat {
        get { dots.travel }
        set { dots.travel = newValue }
    }

    /// §30.9's `+` ring. 0 hides it, 1 closes it.
    var spaceCreation: CGFloat {
        get { dots.creation }
        set { dots.creation = newValue }
    }

    func show(spaces: [Space], activeSpaceID: UUID) {
        dots.show(spaces: spaces, activeSpaceID: activeSpaceID)
        needsLayout = true
    }

    /// The active Space, on §3.5's pill: its picture, its name, and what its
    /// own jar holds.
    ///
    /// `fanOut` is the line Settings puts on the Space's card, so the two
    /// places that answer this question answer it in the same words.
    func show(spaceName: String?, fanOut: String?, picture: Data? = nil) {
        spacePill.show(name: spaceName, picture: ProfilePicture.image(from: picture))
        spacePill.button.setAccessibilityLabel(
            spaceName.map { String(localized: "Space: \($0)") } ?? String(localized: "Space")
        )
        spacePill.button.toolTip = [spaceName, spaceName.map { String(localized: "Cookies and logins for \($0)") }, fanOut]
            .compactMap { $0 }
            .joined(separator: "\n")
        space = spaceName
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
        // One bottom edge for the whole footer: controls of different heights
        // line up on the edge they share, and here that is the sidebar's own
        // margin.
        let foot = ((bounds.height - circle.height) / 2).rounded()
        let cylinder = library.intrinsicContentSize
        library.frame = NSRect(
            x: bounds.maxX - inset - cylinder.width,
            y: foot,
            width: cylinder.width,
            height: cylinder.height
        ).pixelAligned
        let pill = dots.intrinsicContentSize
        let gap = Tokens.Metric.chromeGap
        // The Space pill is its whole name, as §4's is, and only a name that
        // would leave the dots no room at all is faded. Capping it at the
        // centred dots instead cut "Personal" at §1's 220 pt floor, which is
        // the one pill a new user sees.
        let room = library.frame.minX - gap - pill.width - gap - inset
        spacePill.frame = NSRect(
            x: inset,
            y: foot,
            width: max(min(spacePill.naturalWidth, room), circle.width),
            height: circle.height
        ).pixelAligned
        dots.frame = NSRect(
            x: dotsOriginX(pillWidth: pill.width, trailingEdge: library.frame.minX),
            y: foot,
            width: pill.width,
            height: pill.height
        ).pixelAligned
    }

    /// The whole footer answers the right-click, not only the strip in the
    /// middle of it.
    ///
    /// The dots cover their pill edge to edge, so `SpaceDotsView`'s own menu
    /// would only ever be reached in the gap §30.9's `+` opens up — and the
    /// clear air either side of the pill would have had no menu at all. A user
    /// aiming at "the Spaces bit" is aiming at this bar; `SpaceDotView` still
    /// answers for a dot, with §8.2's colours first.
    override func menu(for event: NSEvent) -> NSMenu? {
        SidebarMenu.spaces(
            edit: { [weak self] in self?.onEditSpaces?() },
            new: { [weak self] in self?.onNewSpace?() }
        )
    }

    /// Centred in the bar while it fits, moved along by a Space name too long
    /// to leave the middle clear, and centred in what is left when neither
    /// works.
    ///
    /// The pill is sized to the dots it holds (`SpaceDotsView.width(forDots:)`),
    /// so "does it fit" is not a question §1's minimum can answer once and for
    /// all: eight Spaces at 220 pt is wider than the gap between the Space pill
    /// and the cylinder. Clamping to one side would have slid the pill under one
    /// cluster while leaving clear air under the other; centring the overflow
    /// keeps it symmetrical, which is the difference between a tight bar and a
    /// broken one.
    private func dotsOriginX(pillWidth: CGFloat, trailingEdge: CGFloat) -> CGFloat {
        let gap = Tokens.Metric.chromeGap
        let lower = spacePill.frame.maxX + gap
        let upper = trailingEdge - gap - pillWidth
        let centred = (bounds.width - pillWidth) / 2
        guard upper >= lower else { return (lower + upper) / 2 }
        return min(max(centred, lower), upper)
    }
}
