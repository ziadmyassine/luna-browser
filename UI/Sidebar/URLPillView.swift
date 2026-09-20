//
//  URLPillView.swift
//  Luna
//
//  §3.2's address pill: the domain, and a control at each end of it — site
//  settings leading, reload trailing.
//
//  **It is not an editable field, on either surface.** Both pills hand the
//  whole job to §9.1, which grows out of the pill it was handed by
//  (`CommandBarAnchor`): that is where the field, the history, the ranking, the
//  autofill and the list of completions already are. The sidebar's pill has
//  handed off since there was nowhere in a 200 pt column to put a list; §3.2b's
//  used to edit in place with a list of search phrases under it, which was a
//  second, thinner answer to a question §9.1 answers completely — it knew
//  nothing of open tabs, history or commands, and it was the only place in Luna
//  where typing an address got you a different set of suggestions.
//
//  **Both ends are the pill's, on both surfaces.** The page bar grew them first
//  and owned them as siblings laid over the capsule; the sidebar's pill then
//  wanted the same two, and two implementations of "a glyph inside this pill"
//  is two sets of the same hover, fade and inset bugs. They live here, and a
//  pill without a `onReload` simply does not show one — which is how §4's top
//  bar keeps the pill it has always had.
//
//  **It does not take the page's colour.** §2 made this the one page-derived
//  tint in the app: the site's `themeColor`, washed over `Surface.chromeFill`
//  and clamped until the pill's text still cleared §21.4. On screen that meant
//  the one fixed landmark in the sidebar changed shade with every navigation —
//  getroosta.app and YouTube lifted it, Apple's pages left it where it was —
//  and a control that is a different colour on every site is not a control you
//  stop noticing. It is `Surface.well` now, in every state and on every page:
//  the same recess a pinned tile rests in, so the head of the sidebar is one
//  surface rather than two that agree only sometimes.
//
//  The pill carries its glass when it is being *reached for* — hovered — and is
//  a bordered well the rest of the time. Constant glass made it the brightest
//  thing in the sidebar: a second lit surface directly under three lit circles,
//  with the eye drawn to an address the user already knows.
//

import AppKit
import BrowserKit

@MainActor
final class URLPillView: NSView {

    /// The leading sliders glyph (§3.2's site menu).
    var onSiteMenu: (() -> Void)?
    /// Reload, or stop while the page is loading — the trailing glyph. **Nil
    /// means there is no such glyph**: §4's top bar has its own reload button
    /// beside the pill, and a second one inside it would be two.
    var onReload: ((_ isLoading: Bool) -> Void)? {
        didSet {
            reload.isHidden = onReload == nil
            // The sliders glyph changes ends with it — see
            // `URLPillLayout.slidersLead`.
            needsLayout = true
        }
    }
    /// **Where the address is actually edited.** A click, or `⌘L`, opens §9.1
    /// on the current URL — anchored to this pill, so what the user sees is
    /// this capsule growing the field and the list it never had.
    ///
    /// A pill with nothing wired here is inert, which is the honest fallback:
    /// it is a label that has no bar to open.
    var onHandOff: (() -> Void)?
    /// What §3.2's menu hangs off: the glyph itself, not the pill, so it opens
    /// from the control that was pressed.
    var siteMenuAnchor: NSView { sliders }

    // Not `private`: `URLPillLayout.swift` places both. See its header.
    let field = NSTextField(labelWithString: "")
    /// The `.control` backing, built the first time the pill is reached for —
    /// see `updateGlass`.
    private var glass: NSView?
    /// The radius the backing was built at. A glass view's corner radius is
    /// fixed when it is constructed, so a pill that changes height — §3.2b's,
    /// collapsing — has to be given a new one rather than resized into a
    /// capsule with the wrong ends.
    private var glassRadius: CGFloat?
    private var isHovering = false
    // Bare glyphs, not `GlassButton`s: a glass control inside a glass pill is
    // two materials, and the reference draws no bubble around either.
    let sliders = RowGlyphView()
    let reload = RowGlyphView()
    private var isLoading = false
    // Internal for `URLPillMark.swift`, as `field` and `sliders` are for
    // `URLPillLayout.swift`: still the pill's, still untouched from elsewhere.
    var displayedURL: URL?
    /// §3.2b: the same pill, the other way round — the domain centred in a
    /// capsule rather than read down a column's leading edge. Which way round
    /// it goes is a fact about what the pill sits in.
    ///
    var centresText = false {
        didSet {
            guard centresText != oldValue else { return }
            applyPlaceholder()
            // The two glyphs are drawn at the size the pill they are in calls
            // for — see `URLPillLayout.glyphInk`.
            applyGlyphs()
            needsLayout = true
        }
    }

    /// What the pill is made of, which is a fact about what it is sitting in.
    enum Surface {
        /// §3.2: a bordered well cut into the sidebar's glass plane, lit only
        /// while the pill is being used. Constant glass here made it the
        /// brightest thing in the column — a second lit surface under three lit
        /// circles, with the eye drawn to an address the user knows.
        case well
        /// §3.2b, open: the material at rest and no plate under it — what
        /// stands beside it on that bar is glass at rest too, and a recess
        /// among them reads as a gap in the set.
        case glass
        /// §3.2b, collapsed: nothing. The bar's own plane is the surface, and a
        /// capsule on it would be a control inside a control.
        case bare
    }

    var surface: Surface = .well {
        didSet {
            guard surface != oldValue else { return }
            // **The site menu goes with the surface.** A collapsed bar is the
            // page's own top edge with an address in it; a control floating in
            // that strip is the one thing on it that is not the site. The menu
            // is a scroll away — the bar opens again the moment the page moves
            // up — and §3.2's pill in the sidebar still carries it.
            //
            // It *fades* with it: §3.2b's two states are one dissolve, and a
            // glyph that blinks out on the first frame is the one thing in that
            // dissolve which reads as a cut. Shown before the fade in either
            // direction — a hidden view cannot fade — and hidden again by
            // `settleGlyph()` once the fade has finished, because a view at
            // alpha 0 still takes clicks.
            if surface != .bare { sliders.isHidden = false; reload.isHidden = onReload == nil }
            for glyph in [sliders, reload] { glyph.alphaValue = surface == .bare ? 0 : 1 }
            needsDisplay = true
            needsLayout = true
            updateGlass()
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerCurve = .continuous

        field.font = Tokens.TypeScale.urlPill
        field.lineBreakMode = .byTruncatingTail
        field.focusRingType = .none
        field.isBordered = false
        field.drawsBackground = false
        field.setAccessibilityLabel("Address")
        applyPlaceholder()
        addSubview(field)

        // **The same mark, the same size and the same hover as the buttons on
        // the bar beside it.** This was a drawn two-slider glyph at 13 pt
        // carrying §3.4's close-button chip — a badge's treatment, from when it
        // was a badge printed on a pill in a column. It is a control on a row
        // of controls now, so it is an SF Symbol at `glyphSize` whose hover
        // lifts the ink, which is what every other glyph in Luna's chrome does.
        // A chip here would be a rounded rectangle inside a capsule.
        for glyph in [sliders, reload] {
            glyph.liftsInk = true
            addSubview(glyph)
        }
        applyGlyphs()
        sliders.onActivate = { [weak self] in self?.onSiteMenu?() }
        reload.onActivate = { [weak self] in
            guard let self else { return }
            onReload?(isLoading)
        }
        reload.isHidden = true
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: Tokens.Metric.urlPill.height)
    }



    /// §3.1: reload becomes a **stop** glyph for as long as the page is
    /// loading. The same swap the sidebar's own circle made before the control
    /// moved inside the pill.
    func setLoading(_ loading: Bool) {
        guard loading != isLoading else { return }
        isLoading = loading
        applyGlyphs()
    }

    /// Both glyphs, at the size and in the state the pill is in now.
    private func applyGlyphs() {
        sliders.configure(
            symbolName: "slider.horizontal.3",
            label: String(localized: "Site settings"),
            pointSize: glyphInk
        )
        reload.configure(
            symbolName: isLoading ? "xmark" : "arrow.clockwise",
            label: isLoading ? String(localized: "Stop") : String(localized: "Reload"),
            pointSize: glyphInk
        )
        needsLayout = true
    }

    // MARK: - Appearance

    private func refresh() {
        field.textColor = Tokens.Text.primary
        for glyph in [sliders, reload] { glyph.tint = Tokens.Text.secondary }
        needsDisplay = true
    }

    override var wantsUpdateLayer: Bool { true }


    override func updateLayer() {
        guard let layer else { return }
        layer.cornerRadius = cornerRadius
        // §3.2: a well cut into the sidebar, not a plate sitting on it. The
        // glass fades in above this when the pill is reached for.
        //
        // **Neither, off the sidebar.** A `GlassButton` at `.always` carries no
        // plate and no hairline either: the material is the whole surface, and
        // a well behind it is a shadow the buttons beside it do not have. A
        // `.bare` pill has no surface of its own at all — see `Surface`.
        let plated = surface == .well
        layer.backgroundColor = plated ? Tokens.Surface.well.cgColor : nil
        layer.borderWidth = plated ? Tokens.Metric.hairline : 0
        // **Never the accent.** An editing pill used to take a system-blue
        // ring; the material is what says the pill is live, the same way it
        // does for a selected row and a pinned tile.
        layer.borderColor = plated ? Tokens.Line.border.cgColor : nil
    }

    // MARK: - Dormant material

    /// The pill carries its glass when it is **being reached for** — hovered —
    /// and is a bordered plate on the sidebar's own plane the rest of the time.
    ///
    /// Constant glass is what made it the brightest thing in the sidebar: a
    /// second lit surface directly under three lit circles, with the eye drawn
    /// to an address the user already knows.
    ///
    /// There is no third state for "open": the pill does not open. §9.1 stands
    /// in its place while the address is being edited, and this view is hidden
    /// for the whole of it — see `CommandBarAnchor`.
    private var glassTarget: CGFloat {
        switch surface {
        case .glass: 1
        // Bare on hover too: a material over a plane that is already the page's
        // colour is a second surface announcing itself on a bar built to
        // disappear into the site.
        case .bare: 0
        case .well: isHovering ? 1 : 0
        }
    }

    private func updateGlass() {
        let target = glassTarget
        guard let view = glass ?? (target > 0 ? makeGlass() : nil), view.alphaValue != target else { return }
        Tokens.Motion.animate(Tokens.Motion.controlHover) { context in
            context.allowsImplicitAnimation = true
            view.animator().alphaValue = target
        }
    }

    @discardableResult
    private func makeGlass() -> NSView {
        let view = Glass.apply(.control, to: self, cornerRadius: cornerRadius)
        view.alphaValue = 0
        glass = view
        glassRadius = cornerRadius
        return view
    }

    /// Rebuilds the backing when the pill has changed height under it — only
    /// §3.2b's ever does; the sidebar's finds nothing to do.
    ///
    /// **It carries the alpha across rather than jumping to the target.** A
    /// glass view's radius is fixed when it is built, so a pill that collapses
    /// has to be given a new backing — and the height that forces it changes on
    /// the same frame the material starts fading. Rebuilding at the target
    /// finished that fade instantly: the glass cut out at the top of a 0.20 s
    /// morph instead of dissolving through it.
    func refreshGlassShape() {
        guard let current = glass, glassRadius != cornerRadius else { return }
        makeGlass().alphaValue = current.alphaValue
        updateGlass()
        needsDisplay = true
    }

    /// Hides the site-menu glyph once it has finished fading out, or leaves it
    /// alone if it faded back in. §3.2b's bar calls this when its own animation
    /// completes; nothing else changes `surface`.
    func settleGlyph() {
        sliders.isHidden = sliders.alphaValue == 0
        reload.isHidden = onReload == nil || reload.alphaValue == 0
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where area.owner === self { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        updateGlass()
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        updateGlass()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refresh()
    }

    /// §21.2 / contract rule 4: Increase Contrast is not an appearance, so the
    /// border has to be re-resolved on the workspace notification or the
    /// setting is ignored forever. `SidebarViewController` owns the single
    /// observer and calls this.
    func accessibilityDisplayOptionsChanged() {
        refresh()
    }

    // MARK: - The hand-off (§3.2, §9.1, ⌘L)

    /// Opens §9.1 on this pill. §20.1's `⌘L` arrives here, and so does a click.
    func handOff() {
        onHandOff?()
    }

    /// §30.1: the sidebar's plane moves the window; a control on it does not.
    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) {
        handOff()
    }
}
