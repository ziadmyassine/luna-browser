//
//  SidebarUtilityBar.swift
//  Luna
//
//  §3.5: `[profile 34] ··· [dots 56 × 22] ··· [downloads | history]`, pinned to
//  the bottom at 52 pt, with §3.5's profile line standing above it.
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
//  The dots are the Space switcher (§30.9) and live in `SpaceDotsView.swift`.
//

import AppKit
import BrowserKit

@MainActor
final class SidebarUtilityBar: NSView {

    /// The avatar was wired to a closure nothing ever set, so §3.5's Profile
    /// button did nothing at all when pressed. It opens the menu below now.
    var onProfile: (() -> Void)?
    /// §6.2's rows, for the Profile menu's way into Settings.
    var onManageProfiles: (() -> Void)?
    private var space: String?
    private var spaceFanOut: String?
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

    /// §3.5's Profile control, and §9's fan-out made pressable.
    ///
    /// The one place the window says whose cookies it is using, which used to
    /// be the caption over the strip. A button is the better host: the caption
    /// could only state the Profile, and this can be asked about it. It is also
    /// where a picture of the Profile goes when there is one to show — the
    /// glyph is the placeholder, not the design.
    private let avatar = GlassButton(
        shape: Tokens.Metric.bottomCircle,
        symbolName: SidebarUtilityBar.avatarSymbol,
        pointSize: Tokens.Metric.glyphSize,
        label: "Profile"
    )
    /// What the avatar wears with no picture on the Profile, and what it goes
    /// back to when one is taken off.
    static let avatarSymbol = "person.crop.circle"
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
        avatar.onActivate = { [weak self] in
            guard let self else { return }
            onProfile?()
            // A press opens it where a right-click would, which is what every
            // other pop-out in this bar does (`SidebarActionCapsule`).
            SidebarMenu.profile(
                name: space,
                manage: { [weak self] in self?.onManageProfiles?() }
            ).popUp(positioning: nil, at: NSPoint(x: 0, y: avatar.bounds.maxY), in: avatar)
        }
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

    /// The active Space, on §3.5's button: its picture, its name, and what its
    /// own jar holds.
    ///
    /// `fanOut` is the line Settings puts on the Space's card, so the two
    /// places that answer this question answer it in the same words.
    func show(spaceName: String?, fanOut: String?, picture: Data? = nil) {
        // §9's picture, or the glyph that stands in for one. `setPortrait`
        // takes the symbol back itself when there is nothing to show.
        avatar.setPortrait(ProfilePicture.image(from: picture), fallbackSymbol: Self.avatarSymbol)
        avatar.setAccessibilityLabel(
            spaceName.map { String(localized: "Space: \($0)") } ?? String(localized: "Space")
        )
        avatar.toolTip = [spaceName.map { String(localized: "Cookies and logins for \($0)") }, fanOut]
            .compactMap { $0 }
            .joined(separator: "\n")
        space = spaceName
        spaceFanOut = fanOut
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: Tokens.Metric.topBarHeight)
    }

    /// Where the Space strip's bottom edge sits, measured from the bar's
    /// bottom.
    ///
    /// The same as the avatar's and the cylinder's, which is not the same as
    /// centred. All three used to be centred on the bar's midline, and three
    /// things centred in a 52 pt bar do not line up unless they are the same
    /// height: the 34 pt circles sat 9 pt off the bottom and the 22 pt pill sat
    /// 15, so the footer read as a row with one item floating in it. A row of
    /// controls of different heights lines up on the edge they share, and the
    /// one they share here is the bottom — it is the sidebar's own margin.
    static var spaceStripBottom: CGFloat {
        (Tokens.Metric.topBarHeight - Tokens.Metric.bottomCircle.height) / 2
    }

    /// Where the Space strip's top edge sits — which is where §3.5's
    /// profile line has to stand.
    ///
    /// Arithmetic rather than `dots.frame.maxY`, and static rather than an
    /// instance read, because the column lays the caption out in the same pass
    /// that lays this bar out: a frame read there is a frame from the pass
    /// before. The pill's height never depends on how many Spaces there are, so
    /// neither does this.
    static var spaceStripTop: CGFloat {
        spaceStripBottom + Tokens.Metric.spaceDotsPill.height
    }

    override func layout() {
        super.layout()
        // Bounds-derived frames never animate — see `Motion.immediately`.
        Tokens.Motion.immediately { placeContents() }
    }

    private func placeContents() {
        let inset = Tokens.Metric.rowInset
        let circle = Tokens.Metric.bottomCircle
        // One baseline for the whole footer — see `spaceStripBottom`, which is
        // this same number, named where the column has to read it.
        let foot = Self.spaceStripBottom
        avatar.frame = NSRect(x: inset, y: foot, width: circle.width, height: circle.height).pixelAligned
        let cylinder = library.intrinsicContentSize
        library.frame = NSRect(
            x: bounds.maxX - inset - cylinder.width,
            y: foot,
            width: cylinder.width,
            height: cylinder.height
        ).pixelAligned
        let pill = dots.intrinsicContentSize
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

    /// Centred in the bar while it fits, and centred in what is left when it
    /// does not.
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

/// §3.5's caption: which Space you are in, over the strip that switches them.
///
/// It named the Profile until it named the Space. The dots below it say which
/// Space only by colour and position, and the name the user gave the Space
/// appeared nowhere in the column at all — not in the strip, not on the list,
/// not on the tabs. A user who names a Space is owed the name somewhere they
/// can see it, and this is the line directly over the thing being named.
///
/// Whose cookies moved rather than went: it is on the avatar beside the strip,
/// which is the Profile's own control and where a picture of one will go. The
/// fan-out is still the thing that must not be hidden — Space → Profile is
/// many-to-one (`SPACES-SPEC` §9) and Arc's most-reported conceptual confusion
/// is "why am I still logged in over here" — and a button carries it better
/// than a caption did, because it can also be pressed.
///
/// It is set in `Text.secondary` — an inactive tab's ink, exactly. Brighter
/// than that and it would compete with the tab titles above it for a line that
/// is only ever glanced at.
@MainActor
final class SidebarSpaceLabel: NSView {

    /// The name Luna ships with, which is this line's ruler in the narrowest
    /// column it can be drawn in — see `allowance`.
    ///
    /// Not localized, because it is never shown: `BrowserStore.seedIfEmpty`
    /// writes this exact string as the first Space's name and the first
    /// Profile's, and the rule the ruler states is that the name the app
    /// starts life with fits whole at every width §1 allows.
    static let narrowestName = "Personal"

    /// Right-click here or on the strip below — §6.2's rows are in Settings.
    var onEditSpaces: (() -> Void)?
    var onNewSpace: (() -> Void)?

    /// Clips the name to what the column allows and carries the ramp that
    /// ends it. The pair §3.4's rows use, for the reason they use it: three
    /// characters spent on an `…` say less than three more of the name.
    ///
    /// Internal rather than private so `SidebarSpaceLabelTests` can measure
    /// what the cell padded against what the box kept: a glyph drawn outside
    /// the clip is still inside every frame a test can read, so the two have
    /// to be compared to catch it.
    let clip = NSView()
    let label = NSTextField(labelWithString: "")
    private let fadeMask = CAGradientLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // Clipping, not truncating: the fade is what ends an over-long name,
        // and an ellipsis would be drawn before it got there.
        label.lineBreakMode = .byClipping
        label.cell?.usesSingleLineMode = true
        clip.wantsLayer = true
        clip.layer?.masksToBounds = true
        clip.addSubview(label)
        fadeMask.startPoint = CGPoint(x: 0, y: 0.5)
        fadeMask.endPoint = CGPoint(x: 1, y: 0.5)
        setAccessibilityRole(.staticText)
        addSubview(clip)
        applyTokens()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    /// The active Space's name, or nothing at all — the line disappears rather
    /// than standing empty, so the strip below it keeps its air.
    ///
    /// The full name goes to the tooltip and to VoiceOver whatever the line
    /// shows: what is clipped here is the reading, not the name.
    func show(spaceName: String?) {
        label.stringValue = spaceName ?? ""
        isHidden = (spaceName ?? "").isEmpty
        setAccessibilityLabel(spaceName.map { String(localized: "Space: \($0)") })
        toolTip = spaceName
        needsLayout = true
    }

    /// How much name this line may carry in a column of `column` points.
    ///
    /// `narrowestName` at §1's floor, and a point more for every point the
    /// column is dragged wider. The line is one of three things a column's
    /// width is spent on — the tab titles above it and the Space strip below
    /// are the others — and it was the only one that did not answer to the
    /// drag: a fixed cap showed exactly as much of a name in a 420 pt column
    /// as in a 220 pt one, with the rest of the line empty either side of it.
    ///
    /// Measured against `sidebarFootFloor` and not against
    /// `Settings.sidebarWidth`, so the answer is the width on screen and
    /// nothing else. The live span's floor moves with §3.2b's placement and
    /// §3.1's edge, and a caption that lengthened because the search bar moved
    /// onto the page would be answering a question nobody asked it.
    static func allowance(inColumnOfWidth column: CGFloat) -> CGFloat {
        ceil(textWidth(narrowestName)) + max(column - Tokens.Metric.sidebarFootFloor, 0)
    }

    /// The box that allowance is drawn in: the allowance, plus the overhang
    /// the ramp trails off into.
    ///
    /// The overhang is what keeps the dissolve from ending on a hard edge —
    /// `sidebarSpaceNameFade` is wider than it, so the ink is already faint by
    /// the time the box runs out.
    static func shownWidth(inColumnOfWidth column: CGFloat) -> CGFloat {
        allowance(inColumnOfWidth: column) + Tokens.Metric.rowTitleFade
    }

    /// What the glyphs measure, which is not what the field reports.
    ///
    /// `NSTextFieldCell` keeps 2 pt of its own either side of the text and
    /// `intrinsicContentSize` counts none of it, so a box cut to that width
    /// draws the string 2 pt in and loses the end of it: "Personal" came out
    /// "Persona". Everything here measures the string, and `placeContents`
    /// offsets the field by the padding instead of trying to account for it.
    private static func textWidth(_ text: String) -> CGFloat {
        NSAttributedString(
            string: text,
            attributes: [.font: Tokens.TypeScale.settingsCaption]
        ).size().width
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
        // Bounds-derived frames never animate — see `Motion.immediately`,
        // which also stops the mask below animating its own frame.
        Tokens.Motion.immediately { placeContents() }
    }

    /// Centred whether it is clipped or not. The box holds the head of the
    /// name, never the middle of it, so the strip's caption starts where the
    /// name starts and the fade is always eating the tail.
    ///
    /// The field hangs its padding off the leading edge (see `textWidth`), so
    /// the first glyph stands on the box's edge and the box is exactly as wide
    /// as the text it is keeping.
    private func placeContents() {
        let natural = ceil(Self.textWidth(label.stringValue))
        let room = max(bounds.width - 2 * Tokens.Metric.rowInset, 0)
        let shown = min(natural, min(Self.shownWidth(inColumnOfWidth: bounds.width), room))
        let box = NSRect(x: (bounds.width - shown) / 2, y: 0, width: shown, height: bounds.height).integral
        clip.frame = box
        let pad = Self.padding(of: label)
        let height = label.intrinsicContentSize.height
        label.frame = NSRect(
            x: -pad,
            y: ((box.height - height) / 2).rounded(),
            width: max(natural, box.width) + 2 * pad,
            height: height
        )
        applyFade(overflowing: natural > box.width, width: box.width)
    }

    /// The leading half of what the cell keeps for itself, asked of the cell
    /// rather than written down: it is 2 pt today on both sides, and the point
    /// of measuring is that nothing here breaks if it stops being.
    static func padding(of field: NSTextField) -> CGFloat {
        let cell = field.cell?.cellSize.width ?? 0
        return max((cell - textWidth(field.stringValue)) / 2, 0)
    }

    /// The ramp, which is §3.4's idea at `sidebarSpaceNameFade` rather than a
    /// row's width. Nil when the name fits: a
    /// gradient that is opaque end to end is a masked composite drawing
    /// nothing.
    private func applyFade(overflowing: Bool, width: CGFloat) {
        let ramp = Tokens.Metric.sidebarSpaceNameFade
        guard overflowing, width > ramp else {
            clip.layer?.mask = nil
            return
        }
        // A mask reads alpha and nothing else, so this is not an ink and no
        // token belongs in it.
        fadeMask.frame = clip.bounds
        fadeMask.colors = [NSColor.black.cgColor, NSColor.black.cgColor, NSColor.clear.cgColor]
        fadeMask.locations = [0, NSNumber(value: Double(1 - ramp / width)), 1]
        clip.layer?.mask = fadeMask
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
