//
//  SidebarUtilityBar.swift
//  Luna
//
//  §3.5: `[profile 34] ··· [dots 56 × 22] ··· [downloads | history]`, pinned to
//  the bottom at 52 pt, with §3.5's profile line standing above it.
//
//  The trailing circle opens the archive page, and is called **History** —
//  that is what a user looking for a page they closed goes looking for, and
//  "archive" is Luna's internal word for the same shelf. It carries a clock
//  glyph for the same reason: a box means storage, a clock means "earlier".
//
//  **Downloads sits beside it, as its pair, in one cylinder.** They are the
//  same kind of thing — the shelf of what you already have, glanced at rather
//  than worked in, both opening as a pop-out that stands on its own button —
//  and §4's action capsule pairs the same two at the other end of the window,
//  in one piece of glass. So does this: see `SidebarActionCapsule` for why two
//  discs 5 pt apart read as two controls and one cylinder reads as a pair. The
//  alternative home was the §3.1 control row at the head, which is where
//  *actions on this page* live; a finished download is not one of those.
//
//  The pair is what set §1's sidebar minimum: three clusters and a centred pill
//  need 190 pt, and `Metric.sidebarWidth` records the arithmetic. Below the
//  width where the pill still fits between the outer two it is centred in what
//  is left rather than in the bar — see `placeContents`.
//
//  The dots are the Space switcher (§30.9) and live in `SpaceDotsView.swift`.
//

import AppKit
import BrowserKit

@MainActor
final class SidebarUtilityBar: NSView {

    var onProfile: (() -> Void)?
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

    private let avatar = GlassButton(
        shape: Tokens.Metric.bottomCircle,
        symbolName: "person.crop.circle",
        pointSize: Tokens.Metric.glyphSize,
        label: "Profile"
    )
    /// The same two glyphs §4's capsule uses, in the same order, so the pair is
    /// recognisably the same pair in both layouts.
    private var library: SidebarActionCapsule!
    private let dots = SpaceDotsView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        library = SidebarActionCapsule(items: [
            (symbolName: "arrow.down.to.line", label: String(localized: "Downloads"),
             action: { [weak self] in self?.onDownloads?() }),
            (symbolName: "clock.arrow.circlepath", label: String(localized: "History"),
             action: { [weak self] in self?.onHistory?() })
        ])
        avatar.onActivate = { [weak self] in self?.onProfile?() }
        dots.onSwitch = { [weak self] id in self?.onSwitchSpace?(id) }
        dots.onSetGradient = { [weak self] space, gradient in self?.onSetGradient?(space, gradient) }
        dots.onEditSpaces = { [weak self] in self?.onEditSpaces?() }
        dots.onNewSpace = { [weak self] in self?.onNewSpace?() }
        for view in [avatar, library, dots] as [NSView] { addSubview(view) }
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

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: Tokens.Metric.topBarHeight)
    }

    /// Where the Space strip's **top edge** sits, measured from the bar's
    /// bottom — which is where §3.5's profile line has to stand.
    ///
    /// Arithmetic rather than `dots.frame.maxY`, and static rather than an
    /// instance read, because the column lays the caption out in the same pass
    /// that lays this bar out: a frame read there is a frame from the pass
    /// before. The pill is centred on the bar's midline with the avatar and the
    /// cylinder, so its top is the one thing about it that never depends on how
    /// many Spaces there are.
    static var spaceStripTop: CGFloat {
        (Tokens.Metric.topBarHeight + Tokens.Metric.spaceDotsPill.height) / 2
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
        let cylinder = library.intrinsicContentSize
        library.frame = NSRect(
            x: bounds.maxX - inset - cylinder.width,
            y: midY,
            width: cylinder.width,
            height: cylinder.height
        ).pixelAligned
        let pill = dots.intrinsicContentSize
        dots.frame = NSRect(
            x: dotsOriginX(pillWidth: pill.width, trailingEdge: library.frame.minX),
            y: (bounds.height - pill.height) / 2,
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

    /// **Centred in the bar while it fits, and centred in what is left when it
    /// does not.**
    ///
    /// The pill is sized to the dots it holds (`SpaceDotsView.width(forDots:)`),
    /// so "does it fit" is not a question §1's minimum can answer once and for
    /// all: eight Spaces at 220 pt is wider than the gap between the avatar and
    /// the cylinder. Clamping to one side would have slid the pill under one
    /// cluster while leaving clear air under the other; centring the overflow
    /// keeps it symmetrical, which is the difference between a tight bar and a
    /// broken one.
    private func dotsOriginX(pillWidth: CGFloat, trailingEdge: CGFloat) -> CGFloat {
        let gap = Tokens.Metric.chromeGap
        let lower = avatar.frame.maxX + gap
        let upper = trailingEdge - gap - pillWidth
        let centred = (bounds.width - pillWidth) / 2
        guard upper >= lower else { return (lower + upper) / 2 }
        return min(max(centred, lower), upper)
    }
}

/// §3.5's profile line: the one place the window says whose cookies it is
/// using.
///
/// **The fan-out is the reason this exists.** Space → Profile is many-to-one
/// (`SPACES-SPEC` §9) and no other browser tells you which side of it you are
/// on: Arc's most-reported conceptual confusion is "why am I still logged in
/// over here", and its answer lives in a support article. Settings names the
/// profile on each Space's card, but a name you have to open a window to read
/// is not what you check before typing a password into a shared jar.
///
/// It is set in `Text.secondary` — **an inactive tab's ink, exactly** — and
/// sits directly over the Space strip, because the two answer one question
/// between them: which Space, and whose logins. Brighter than that and it
/// would compete with the tab titles above it for a line that is only ever
/// glanced at.
@MainActor
final class SidebarProfileLabel: NSView {

    /// Right-click here or on the strip below — §6.2's rows are in Settings.
    var onEditSpaces: (() -> Void)?
    var onNewSpace: (() -> Void)?

    private let label = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.setAccessibilityRole(.staticText)
        addSubview(label)
        applyTokens()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    /// The profile's name, or nothing at all — the line disappears rather than
    /// standing empty, so the strip below it keeps its air.
    func show(profileName: String?) {
        label.stringValue = profileName ?? ""
        isHidden = (profileName ?? "").isEmpty
        setAccessibilityLabel(profileName.map { String(localized: "Profile: \($0)") })
        toolTip = profileName.map { String(localized: "Cookies and logins for the \($0) profile") }
        needsLayout = true
    }

    private func applyTokens() {
        label.font = Tokens.TypeScale.settingsCaption
        // §3.4's inactive row title, to the point — this line is read at the
        // same glance as the list above it and must not outrank a tab.
        label.textColor = Tokens.Text.secondary
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyTokens()
    }

    /// §21.2: Increase Contrast is not an appearance, so the sidebar tells this
    /// by hand along with every other surface that draws text.
    func accessibilityDisplayOptionsChanged() {
        applyTokens()
    }

    override func layout() {
        super.layout()
        Tokens.Motion.immediately {
            let inset = Tokens.Metric.rowInset
            label.frame = NSRect(
                x: inset,
                y: 0,
                width: max(bounds.width - 2 * inset, 0),
                height: bounds.height
            ).integral
        }
    }

    /// §30.1: the sidebar's plane moves the window. A label is not a control,
    /// so this one deliberately keeps that behaviour — a drag here still moves
    /// the window, and only the right-click is ours.
    override func menu(for event: NSEvent) -> NSMenu? {
        SidebarMenu.spaces(
            edit: { [weak self] in self?.onEditSpaces?() },
            new: { [weak self] in self?.onNewSpace?() }
        )
    }
}
