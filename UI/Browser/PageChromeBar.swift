//
//  PageChromeBar.swift
//  Luna
//
//  §3.2b: the sidebar's head, on the page.
//
//  When Settings ▸ Appearance puts the search bar "On the page", the three §3.1
//  circles and the §3.2 pill leave the sidebar and sit on a bar across the top
//  of the content pane instead. The sidebar keeps its tabs, its Essentials and
//  its bottom bar — and its top 52 pt, because that is what holds the traffic
//  lights' corner clear.
//
//  **The bar is a plane in the page's own colour, and that is the whole idea.**
//  It was tried as floating controls with nothing behind them, and it has to be
//  said plainly why that does not work: no material in Luna can react to the
//  page. `NSGlassEffectView` composites what is behind the *window*, and
//  `NSVisualEffectView` will not sample a `WKWebView`'s out-of-process layer —
//  both measured, both written down in `Glass.peekPlane`. So over a white site
//  the glass showed a light desktop and three white circles vanished into a
//  white page. A plane taken from `TabState.pageBackground` has the opposite
//  property: it is the colour the page is painted on, so it reads as the site's
//  own top edge rather than as something laid over it, and it is a *known*
//  surface, which is what the controls on it need.
//
//  **And it follows the page down.** `pageBackground` is one answer for a whole
//  document, so a bar wearing it stayed white all the way down a site whose
//  second section is black: the plane stopped being the page's top edge the
//  moment the page moved. What is under the bar is a question only the page can
//  answer, so `TabController+Scroll` asks it as the page scrolls.
//
//  **And the bar wears the appearance that plane calls for.** Everything drawn
//  here — the domain, the glyph ink, the glass fallbacks — resolves from an
//  `NSAppearance`, so one assignment re-inks all of it at once. A dark app over
//  a white site gets dark glyphs on the bar and light ones everywhere else,
//  which is correct rather than inconsistent: the bar is the only surface in
//  Luna whose background is not Luna's.
//
//  Two states, and the page decides which. At the top of a document the bar is
//  open: toggle, back, reload and a wide pill. Once the page has scrolled past
//  `pageBarScrollSlack` the buttons go, the bar shrinks to `pageBarCollapsed`
//  and the pill goes bare — the plane is the only surface left, which is the
//  thin strip of site colour with the domain in it that the reference shows.
//  `PageChromeController` owns that decision; this owns what the two look like.
//

import AppKit
import BrowserKit

@MainActor
final class PageChromeBar: NSView {

    var onToggleSidebar: (() -> Void)?
    var onBack: (() -> Void)?
    var onReloadOrStop: ((_ isLoading: Bool) -> Void)?
    var onSubmitURL: ((String) -> Void)?
    /// What is being typed in the pill, for whoever asks the engine. Nil until
    /// `PageChromeController` wires it; the list simply stays empty.
    var onTyping: ((String) -> Void)?
    /// How much room the bar is taking, whenever that changes. The page starts
    /// below it — see `ContentCardView.setContentTopInset`.
    var onBandHeight: ((_ height: CGFloat, _ animated: Bool) -> Void)?
    /// The pill has been reached for, and the bar is open by the time this
    /// fires. It stays open for as long as the editing lasts.
    var onEditingBegan: (() -> Void)?
    /// Editing is over, and the bar is the page's again. `committed` is Return:
    /// a navigation is on its way and arriving opens the bar anyway, so taking
    /// it back for the fraction of a second in between is a flinch.
    var onEditingEnded: ((_ committed: Bool) -> Void)?

    /// The page's colour, as a plane. Behind everything, and the only thing on
    /// this bar that is painted rather than placed.
    private let plane = NSView()
    private let toggle = GlassButton(
        shape: Tokens.Metric.sidebarCircle,
        symbolName: "sidebar.leading",
        pointSize: Tokens.Metric.glyphSize,
        label: "Show Sidebar"
    )
    private let back = GlassButton(
        shape: Tokens.Metric.sidebarCircle,
        symbolName: "chevron.backward",
        pointSize: Tokens.Metric.glyphSize,
        label: "Back"
    )
    private let reload = GlassButton(
        shape: Tokens.Metric.sidebarCircle,
        symbolName: "arrow.clockwise",
        pointSize: Tokens.Metric.glyphSize,
        label: "Reload"
    )
    private let pill = URLPillView()
    /// §3.4's completions, hanging off the bottom of the pill.
    private let suggestions = PageBarSuggestions()
    private var isLoading = false
    private(set) var isCollapsed = false
    /// The document's own background, the strip under the bar, and whichever of
    /// the two is on the plane right now.
    private var documentColour: NSColor?
    private var topColour: NSColor?
    private var pageColour: NSColor?

    private var buttons: [NSView] { [toggle, back, reload] }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        plane.wantsLayer = true
        addSubview(plane)
        pill.centresText = true
        pill.surface = .glass
        toggle.onActivate = { [weak self] in self?.onToggleSidebar?() }
        back.onActivate = { [weak self] in self?.onBack?() }
        reload.onActivate = { [weak self] in
            guard let self else { return }
            onReloadOrStop?(isLoading)
        }
        pill.onSubmit = { [weak self] text in self?.onSubmitURL?(text) }
        pill.onSiteMenu = { [weak self] in
            guard let self else { return }
            SiteMenu.present(from: pill.siteMenuAnchor)
        }
        for view in buttons + [pill, suggestions] { addSubview(view) }
        wirePill()
        applyPlane(animated: false)
        watchForTheLights() // The one thing that moves without resizing this view.
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    /// The pill owns the keystrokes and the list owns the selection, so the
    /// hooks between them are all there is to it: what was typed goes out, the
    /// arrows move the list, Return asks it for a phrase, and the end of
    /// editing takes it away.
    ///
    /// **And the pill being touched at all opens the bar.** A press on the
    /// collapsed capsule used to start editing inside 22 pt of it — a full URL
    /// or a query in a capsule sized to `apple.com`, with no room under it for
    /// the list and no buttons beside it. So the click opens the bar first and
    /// the typing happens in the pill that grows out of it. The bar then stays
    /// open for as long as the editing lasts, whatever the page does: see
    /// `PageChromeController.pageScrolled(to:)`.
    private func wirePill() {
        pill.onTyping = { [weak self] text in self?.onTyping?(text) }
        pill.onMoveSelection = { [weak self] offset in self?.suggestions.move(offset) ?? false }
        pill.chosenCompletion = { [weak self] in self?.suggestions.selectedPhrase }
        pill.onBeginEditing = { [weak self] in
            guard let self else { return }
            setCollapsed(false, animated: true)
            onEditingBegan?()
        }
        pill.onEndEditing = { [weak self] committed in
            guard let self else { return }
            suggestions.dismiss()
            onEditingEnded?(committed)
        }
        suggestions.onCommit = { [weak self] phrase in
            guard let self else { return }
            suggestions.dismiss()
            onSubmitURL?(phrase)
        }
    }

    /// The engine's answers, from `SearchSuggestions` by way of the controller.
    func showSuggestions(_ phrases: [String]) {
        suggestions.show(phrases)
        needsLayout = true
    }

    // MARK: - State

    func show(url: URL?) {
        pill.show(url: url)
        needsLayout = true
    }

    func update(canGoBack: Bool, isLoading: Bool) {
        back.isEnabled = canGoBack
        guard isLoading != self.isLoading else { return }
        self.isLoading = isLoading
        reload.setSymbol(isLoading ? "xmark" : "arrow.clockwise")
        reload.setAccessibilityLabel(isLoading ? "Stop" : "Reload")
    }

    /// The colour the page is painted on, from `TabState.pageBackground`.
    ///
    /// Nil for a tab with no live web view — a cold tab, or the moment before
    /// the first paint — and then the bar falls back to the content pane's own
    /// plane, which is exactly what is behind it at that moment.
    func setPageColour(_ colour: RGBA?) {
        documentColour = colour.map(NSColor.init)
        refreshPlane()
    }

    /// The colour the page reports for the strip right under this bar, which is
    /// the more useful question and the one `pageBackground` cannot answer.
    ///
    /// Nil is the page saying it has no single colour up there — two columns in
    /// different shades, a card over a tint — and then the document's own
    /// background is the right answer again. See `TabController+Scroll`.
    func setTopColour(_ colour: RGBA?) {
        topColour = colour.map(NSColor.init)
        refreshPlane()
    }

    /// The two colours resolve here and nowhere else, so there is one plane and
    /// one rule for what it wears.
    private func refreshPlane() {
        let colour = topColour ?? documentColour
        guard colour != pageColour else { return }
        pageColour = colour
        applyPlane(animated: true)
    }

    /// §3.2b's two states. Animated on `sidebarCollapse` — the same 0.20 s the
    /// sidebar itself slides on, because this is the same piece of chrome
    /// getting out of the page's way.
    func setCollapsed(_ collapsed: Bool, animated: Bool) {
        guard collapsed != isCollapsed else { return }
        isCollapsed = collapsed
        // Before the bar moves, not after: the page's own animation runs on the
        // same spec, and telling it afterwards would start it a frame late.
        onBandHeight?(bandHeight, animated)
        // Un-hidden *before* the fade in either direction: a view cannot fade
        // from `isHidden`, and the fade out hides it again on completion.
        if !collapsed { for view in buttons { view.isHidden = false } }
        guard animated else {
            Tokens.Motion.immediately { applyState() }
            for view in buttons { view.isHidden = collapsed }
            pill.settleGlyph()
            return
        }
        Tokens.Motion.animate(Tokens.Motion.sidebarCollapse) { context in
            context.allowsImplicitAnimation = true
            applyState()
        } completion: { [weak self] in
            MainActor.assumeIsolated {
                // A view at alpha 0 still hit-tests, so a faded button would go
                // on eating clicks meant for the page. Re-read rather than
                // trust the captured value: another change may have landed.
                guard let self else { return }
                for view in self.buttons { view.isHidden = view.alphaValue == 0 }
                // The pill's own glyph faded with them, and for the same reason.
                self.pill.settleGlyph()
            }
        }
    }

    // MARK: - The plane

    /// The plane's colour, and the appearance that colour implies.
    ///
    /// The appearance is assigned outside the animation: `NSAppearance` is not
    /// an animatable property, and re-inking a subtree inside a colour fade
    /// makes the glyphs jump a frame before the plane has finished moving.
    private func applyPlane(animated: Bool) {
        let colour = pageColour ?? Tokens.Surface.base
        appearance = NSAppearance(
            named: colour.wantsLightInk(in: effectiveAppearance) ? .darkAqua : .aqua
        )
        let assign: () -> Void = { self.plane.layer?.backgroundColor = colour.cgColor }
        guard animated else { return Tokens.Motion.immediately(assign) }
        // The same spec §2's page-derived wash uses: a navigation changes this
        // colour, and a hard cut between two sites' whites is a flash.
        Tokens.Motion.animate(Tokens.Motion.themeWash) { context in
            context.allowsImplicitAnimation = true
            assign()
        }
    }

    // MARK: - Layout

    /// The bar's frame is the **open** band, whatever state it is in: nothing
    /// here resizes, so the plane and the controls can travel inside a frame
    /// that is standing still. `hitTest` is what keeps the part of it the plane
    /// does not cover from taking the page's clicks.
    override func layout() {
        super.layout()
        Tokens.Motion.immediately { applyState() }
    }

    /// The surface before the frames: the pill's own contents are laid out
    /// against the margins its surface keeps, and the collapsed one keeps
    /// narrower ones.
    private func applyState() {
        pill.surface = isCollapsed ? .bare : .glass
        placeControls()
        for view in buttons { view.alphaValue = isCollapsed ? 0 : 1 }
    }

    /// The room the bar is taking right now, for the page below it.
    var bandHeight: CGFloat {
        isCollapsed ? Tokens.Metric.pageBarCollapsed : Tokens.Metric.pageBar
    }

    /// The band the plane fills, in this view's coordinates.
    private var band: NSRect {
        NSRect(x: bounds.minX, y: bounds.maxY - bandHeight, width: bounds.width, height: bandHeight)
    }

    private func placeControls() {
        let circle = Tokens.Metric.sidebarCircle
        let lights = TrafficLightSpace.rect(in: self)
        let strip = band
        plane.frame = strip

        // **The traffic lights are the centre line whenever they are on
        // screen.** The pane is flush to the window's top in every state this
        // bar appears in, so the lights' centre is a line this view shares with
        // §3.1's control row — and the two must agree, because with the sidebar
        // showing they are 280 pt apart on the same row of pixels.
        let centreY = isCollapsed ? strip.midY : (lights?.midY ?? strip.midY)

        // With the sidebar showing, the lights are 280 pt to the left of this
        // view and `maxX` comes back negative — which is exactly right, and why
        // this is a `max` rather than a branch on the chrome state.
        let start = max(
            lights.map { $0.maxX + Tokens.Metric.chromeGapWide } ?? 0,
            Tokens.Metric.pageBarInset
        )
        var x = start
        for view in buttons {
            view.frame = NSRect(
                x: x,
                y: centreY - circle.height / 2,
                width: circle.width,
                height: circle.height
            ).pixelAligned
            x += circle.width + Tokens.Metric.controlPairGap
        }
        let buttonsEnd = x - Tokens.Metric.controlPairGap

        // **The buttons' own diameter, not the pill's own height token.** The
        // two are the same 34 pt today — `sidebarCircle` is defined as a circle
        // of `urlPill.height` — and on this bar they have to *stay* the same:
        // four controls on one line, one of them a different height, is the
        // thing the eye finds first.
        //
        // **Centred on the pane when there is room, and pushed off centre when
        // there is not.** A 640 pt window with a sidebar open leaves about
        // 230 pt beside the buttons; a pill centred in that overlaps them, and
        // an overlapping pill is worse than an off-centre one.
        //
        // **The open layout places the pill, and the collapsed one keeps that
        // place exactly — the same x and the same width.** Both were worked out
        // separately before: open, clear of the buttons; collapsed, sized to the
        // domain and centred in what was left of the bar. Even once they shared
        // a centre the capsule still travelled, because its two edges did: it
        // drew in from 420 pt to the width of `apple.com` while its material was
        // fading, which is the address sliding in from the side that the two
        // states were supposed to stop doing.
        //
        // **It can keep the width because collapsed it has no surface.** A
        // `.bare` pill draws nothing but its centred domain, so 420 pt of it is
        // 420 pt of nothing with a word in the middle — and the word is already
        // on the centre line the open pill put it on. Nothing moves sideways at
        // any point of the change; the height and the material are all of it.
        // It also puts the truncation question beyond reach: a domain that fits
        // the open pill fits the collapsed one, because they are the same pill.
        let right = bounds.maxX - Tokens.Metric.pageBarInset
        let left = buttonsEnd + Tokens.Metric.chromeGapWide
        let width = min(Tokens.Metric.pageBarPillWidth, max(right - left, 0))
        let height = isCollapsed ? Tokens.Metric.pageBarCollapsedPillHeight : circle.height
        pill.frame = NSRect(
            x: min(max(bounds.midX - width / 2, left), max(right - width, left)),
            y: centreY - height / 2,
            width: width,
            height: height
        ).pixelAligned

        // Under the pill and exactly as wide: the list is the pill's own
        // continuation, so it lines up with it rather than with the bar.
        let listHeight = suggestions.fittingHeight
        suggestions.frame = NSRect(
            x: pill.frame.minX,
            y: pill.frame.minY - Tokens.Metric.chromeGap - listHeight,
            width: pill.frame.width,
            height: listHeight
        ).integral
    }

    // MARK: - Events

    /// **Only the band takes events.** The bar's frame is the open band's
    /// height whichever state it is in, so while it is collapsed the lower
    /// 22 pt of it is over live page and must behave like page: a link there
    /// has to stay clickable.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        // A control, a row of the list, or the list's own material: theirs.
        guard hit === self || hit === plane else { return hit }
        return band.contains(convert(point, from: superview)) ? self : nil
    }

    /// The bar is chrome, so dragging it moves the window — the same as the
    /// sidebar's own plane. The controls on it override this themselves.
    override var mouseDownCanMoveWindow: Bool { true }
}
