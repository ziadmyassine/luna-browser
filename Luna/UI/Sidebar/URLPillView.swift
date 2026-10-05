//
//  URLPillView.swift
//  Luna
//
//  §3.2's address pill: the domain, and a control at each end of it — site
//  settings leading, reload trailing.
//
//  It is not an editable field on either surface. Both pills hand the whole job
//  to §9.1 (`CommandBarAnchor`), which has the field, the history, the ranking,
//  the autofill and the completions; an editor in the pill would be a second,
//  thinner set of suggestions that knows nothing of open tabs or commands.
//
//  Both ends belong to the pill, on both surfaces, rather than being siblings laid
//  over it: two implementations of "a glyph inside this pill" is two sets of the
//  same hover, fade and inset bugs.
//
//  It does not take the page's colour: a tinted pill made the sidebar's one fixed
//  landmark change shade with every navigation. It is `Surface.well` in every
//  state, the recess a pinned tile rests in. `glassTarget` says when it is lit.
//

import AppKit
import BrowserKit

@MainActor
final class URLPillView: NSView, PopoutShelf {

    /// The leading sliders glyph (§3.2's site settings).
    var onSiteMenu: (() -> Void)?
    /// The Aa glyph before reload, which opens the Reading pop-out.
    var onReading: (() -> Void)?
    /// The rover's face before the trailing glyphs, which shows and hides the
    /// agent panel (`⌘E`). Nil leaves it off the pill.
    var onAgent: (() -> Void)? {
        didSet {
            agent.isHidden = onAgent == nil
            needsLayout = true
        }
    }
    /// Whether the tab wears the Aa glyph: only where its settings change the
    /// page, which is Reader and a Markdown document. An ordinary site that
    /// merely reads as an article does not; Reader is on ⇧⌘R and in site settings.
    static func showsReading(for state: TabState?) -> Bool { state?.isReading ?? false }

    /// Whether the tab on show is a reading page, and so wears the Aa glyph.
    var showsReading = false {
        didSet {
            guard showsReading != oldValue else { return }
            reading.isHidden = !showsReading
            needsLayout = true
        }
    }
    /// A Markdown document's editor holds text its file does not have yet.
    var isEdited = false {
        didSet {
            guard isEdited != oldValue else { return }
            show(url: displayedURL)
        }
    }
    /// Reload, or stop while the page is loading — the trailing glyph. Nil
    /// means there is no such glyph: §4's top bar has its own reload button
    /// beside the pill, and a second one inside it would be two.
    var onReload: ((_ isLoading: Bool) -> Void)? {
        didSet {
            reload.isHidden = onReload == nil
            // The sliders glyph changes ends with it — see
            // `URLPillLayout.slidersLead`.
            needsLayout = true
        }
    }
    /// Where the address is actually edited. A click, or `⌘L`, opens §9.1
    /// on the current URL — anchored to this pill, so what the user sees is
    /// this capsule growing the field and the list it never had.
    ///
    /// A pill with nothing wired here is inert: a label with no bar to open.
    var onHandOff: (() -> Void)?
    /// What §3.2's site settings stand on: the glyph across, so the pop-out
    /// opens from the control that was pressed, and the pill's glass up and
    /// down (`PopoutShelf`).
    var siteMenuAnchor: NSView { sliders }
    var readingAnchor: NSView { reading }

    // Not `private`: `URLPillLayout.swift` places both. See its header.
    let field = NSTextField(labelWithString: "")
    /// The `.control` backing, built the first time the pill is reached for —
    /// see `updateGlass`.
    private var glass: GlassBackingView?
    private var isHovering = false
    // Bare glyphs, not `GlassButton`s: a glass control inside a glass pill is
    // two materials, and the reference draws no bubble around either.
    let sliders = RowGlyphView()
    let reload = RowGlyphView()
    let reading = RowGlyphView()
    let agent = RowGlyphView()
    /// §16.4, in the sidebar's pill: the extensions button in the trailing
    /// slot and the pinned extensions to its left — `URLPillExtensions.swift`.
    /// Off on §3.2b's pill, whose bar has a cylinder of its own for them.
    let extensionsGlyph = RowGlyphView()
    var pinGlyphs: [RowGlyphView] = []
    var extensionPins: [ExtensionShelfItem] = [] { didSet { dressPins() } }
    var showsExtensions = false {
        didSet {
            guard showsExtensions != oldValue else { return }
            extensionsGlyph.isHidden = !showsExtensions
            dressPins()
        }
    }
    var onExtension: ((String, NSView) -> Void)?
    var onExtensions: ((NSView) -> Void)?
    /// §3.2c's load line. Not private: `URLPillLayout.swift` places it, as it
    /// places everything else on the pill.
    let loadLine = LoadProgressLine()
    private var isLoading = false
    // Internal for `URLPillMark.swift`, as `field` and `sliders` are for
    // `URLPillLayout.swift`: still the pill's, still untouched from elsewhere.
    var displayedURL: URL?
    /// §3.2b: the same pill, the other way round — the domain centred in a
    /// capsule rather than read down a column's leading edge. Which way round
    /// it goes is a fact about what the pill sits in.
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
        /// while the pill is being used. See `glassTarget` for why it is not
        /// lit at rest.
        case well
        /// §3.2b, open: the material at rest and no plate under it — what
        /// stands beside it on that bar is glass at rest too, and a recess
        /// among them reads as a gap in the set.
        case glass
    }

    var surface: Surface = .well {
        didSet {
            guard surface != oldValue else { return }
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

        // The sliders glyph is a control on a row of controls, not a badge
        // printed on the pill: an SF Symbol behaving exactly as the reload
        // beside it does (`RowGlyphView`).
        for glyph in [sliders, reload, reading, agent, extensionsGlyph] {
            glyph.isRound = true
            addSubview(glyph)
        }
        agent.isHidden = true
        agent.onActivate = { [weak self] in self?.onAgent?() }
        reading.isHidden = true
        reading.onActivate = { [weak self] in self?.onReading?() }
        extensionsGlyph.isHidden = true
        extensionsGlyph.onActivate = { [weak self] in
            guard let self else { return }
            onExtensions?(extensionsGlyph)
        }
        applyGlyphs()
        sliders.onActivate = { [weak self] in self?.onSiteMenu?() }
        reload.onActivate = { [weak self] in
            guard let self else { return }
            onReload?(isLoading)
        }
        reload.isHidden = true
        // Above the glyphs and the field: 2 pt of ink along an edge nothing
        // else reaches, taking no clicks (`hitTest`), so the order costs the
        // pill nothing.
        addSubview(loadLine)
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: Tokens.Metric.urlPill.height)
    }

    /// §3.1: reload becomes a stop glyph for as long as the page is
    /// loading.
    func setLoading(_ loading: Bool) {
        guard loading != isLoading else { return }
        isLoading = loading
        applyGlyphs()
    }

    /// §3.2c: how far the page in this pill has loaded.
    ///
    /// Nil is not zero: it means there is no live tab behind this pill — a tab
    /// that was never warm, or a bar just handed back the window. The line
    /// clears rather than animating out of a load it never showed.
    func setLoad(_ state: TabState?, for tab: UUID?) {
        guard let state else { return loadLine.clear() }
        loadLine.show(state, for: tab)
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
        reading.configure(symbolName: ReadingMenu.Glyph.header, label: String(localized: "Reading"), pointSize: glyphInk)
        agent.configure(image: AgentGlyph.image(pointSize: glyphInk), label: String(localized: "Agent"), pointSize: glyphInk)
        extensionsGlyph.configure(symbolName: ExtensionsSymbol.name, label: ExtensionsSymbol.label, pointSize: glyphInk)
        needsLayout = true
    }

    // MARK: - Appearance

    private func refresh() {
        field.textColor = Tokens.Text.primary
        for glyph in [sliders, reload, reading, agent, extensionsGlyph] { glyph.tint = Tokens.Text.secondary }
        needsDisplay = true
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        guard let layer else { return }
        layer.cornerRadius = cornerRadius
        // §3.2: a well cut into the sidebar, not a plate sitting on it. The
        // glass fades in above this when the pill is reached for.
        //
        // Neither, off the sidebar. A `GlassButton` at `.always` carries no
        // plate and no hairline either: the material is the whole surface, and
        // a well behind it is a shadow the buttons beside it do not have.
        let plated = surface == .well
        layer.backgroundColor = plated ? Tokens.Surface.well.cgColor : nil
        layer.borderWidth = plated ? Tokens.Metric.hairline : 0
        // Never an accent ring: the material is what says the pill is live,
        // the same way it does for a selected row and a pinned tile.
        layer.borderColor = plated ? Tokens.Line.border.cgColor : nil
    }

    // MARK: - Dormant material

    /// The pill carries its glass when it is being reached for — hovered —
    /// and is a bordered plate on the sidebar's own plane the rest of the time.
    ///
    /// Constant glass made it the brightest thing in the sidebar: a second lit
    /// surface directly under three lit circles, drawing the eye to an address
    /// the user already knows.
    ///
    /// There is no third state for "open": the pill does not open. §9.1 stands
    /// in its place while the address is being edited, and this view is hidden
    /// for the whole of it — see `CommandBarAnchor`.
    private var glassTarget: CGFloat {
        switch surface {
        case .glass: 1
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

    private func makeGlass() -> NSView {
        let view = Glass.apply(.control, to: self, cornerRadius: cornerRadius)
        view.alphaValue = 0
        glass = view as? GlassBackingView
        return view
    }

    /// Re-cuts the backing's ends when the pill has changed height under it.
    /// The same backing, given a new radius: rebuilding it at the new height
    /// cost 3–10 ms on the main thread each time and cut the material's fade.
    func refreshGlassShape() {
        glass?.cornerRadius = cornerRadius
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
