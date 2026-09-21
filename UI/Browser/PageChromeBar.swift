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
//  The bar is a plane in the page's own colour, and that is the whole idea.
//  It was tried as floating controls with nothing behind them, and it has to be
//  said plainly why that does not work: no material in Luna can react to the
//  page. `NSGlassEffectView` composites what is behind the window, and
//  `NSVisualEffectView` will not sample a `WKWebView`'s out-of-process layer —
//  both measured, both written down in `Glass.peekPlane`. So over a white site
//  the glass showed a light desktop and three white circles vanished into a
//  white page. A plane taken from `TabState.pageBackground` has the opposite
//  property: it is the colour the page is painted on, so it reads as the site's
//  own top edge rather than as something laid over it, and it is a known
//  surface, which is what the controls on it need.
//
//  And it follows the page down. `pageBackground` is one answer for a whole
//  document, so a bar wearing it stayed white all the way down a site whose
//  second section is black: the plane stopped being the page's top edge the
//  moment the page moved. What is under the bar is a question only the page can
//  answer, so `TabController+Scroll` asks it as the page scrolls.
//
//  And the bar wears the appearance that plane calls for. Everything drawn
//  here — the domain, the glyph ink, the glass fallbacks — resolves from an
//  `NSAppearance`, so one assignment re-inks all of it at once. A dark app over
//  a white site gets dark glyphs on the bar and light ones everywhere else,
//  which is correct rather than inconsistent: the bar is the only surface in
//  Luna whose background is not Luna's.
//
//  Two states, and the page decides which. At the top of a document the bar is
//  open: the toggle, the history cluster and a wide pill with a control at each
//  end of it. Once the page has scrolled past `pageBarScrollSlack` all of them
//  go, the bar shrinks to `pageBarCollapsed` and the pill goes bare — the plane
//  is the only surface left, which is the thin strip of site colour with the
//  domain in it that the reference shows. `PageChromeController` owns that
//  decision; this owns what the two look like.
//
//  Reload is not on this bar. It is inside the capsule on its trailing
//  edge, with site settings on the leading one — and both belong to
//  `URLPillView`, which carries the same pair in the sidebar. This bar wires
//  the reload closure and nothing else.
//
//  And the address is not typed here either. The pill hands the whole job
//  to §9.1, which opens on this capsule and grows down out of it
//  (`CommandBarAnchor`) — the same hand-off the sidebar's pill makes, so the
//  two address bars now behave identically rather than offering two different
//  sets of suggestions. What this bar had instead was `PageBarSuggestions`: a
//  list of search phrases and nothing else, no open tabs, no history, no
//  commands, no autofill. It is gone, and so is editing in place.
//

import AppKit
import BrowserKit

@MainActor
final class PageChromeBar: NSView, TrafficLightNeighbour {

    var onToggleSidebar: (() -> Void)?
    var onBack: (() -> Void)?
    /// Forward, which §3.2b shows only when there is one — see
    /// `NavCluster`.
    var onForward: (() -> Void)?
    var onReloadOrStop: ((_ isLoading: Bool) -> Void)?
    /// The pill wants §9.1, standing in its place. Wired to
    /// `BrowserSession.presentCommandBar` by `PageChromeController`.
    var onHandOff: ((CommandBarAnchor) -> Void)?
    /// How much room the bar is taking, whenever that changes. The page starts
    /// below it — see `ContentCardView.setContentTopInset`.
    var onBandHeight: ((_ height: CGFloat, _ animated: Bool) -> Void)?
    /// The pill has been reached for, and the bar is open by the time this
    /// fires. It stays open for as long as §9.1 is standing on it.
    var onEditingBegan: (() -> Void)?
    /// §9.1 has closed and the bar is the page's again.
    var onEditingEnded: (() -> Void)?

    // These are `internal` for `PageChromeBarLayout.swift`. See its header.

    /// The page's colour, as a plane. Behind everything, and the only thing on
    /// this bar that is painted rather than placed.
    let plane = NSView()
    let toggle = GlassButton(
        shape: Tokens.Metric.sidebarCircle,
        symbolName: "sidebar.leading",
        pointSize: Tokens.Metric.glyphSize,
        label: "Show Sidebar"
    )
    let nav = NavCluster()
    let pill = URLPillView()
    private var isLoading = false
    private(set) var isCollapsed = false
    /// The document's own background, the strip under the bar, and whichever of
    /// the two is on the plane right now.
    private var documentColour: NSColor?
    private var topColour: NSColor?
    private var pageColour: NSColor?

    /// The bar's own controls, in the order they are laid out. The pill's two
    /// glyphs go away with its surface — see `URLPillView.settleGlyph`.
    var buttons: [NSView] { [toggle, nav] }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        plane.wantsLayer = true
        addSubview(plane)
        pill.centresText = true
        pill.surface = .glass
        toggle.onActivate = { [weak self] in self?.onToggleSidebar?() }
        nav.onBack = { [weak self] in self?.onBack?() }
        nav.onForward = { [weak self] in self?.onForward?() }
        pill.onReload = { [weak self] isLoading in self?.onReloadOrStop?(isLoading) }
        pill.onSiteMenu = { [weak self] in
            guard let self else { return }
            SiteMenu.present(from: pill.siteMenuAnchor)
        }
        for view in buttons + [pill] { addSubview(view) }
        wirePill()
        applyPlane(animated: false)
        watchForTheLights() // The one thing that moves without resizing this view.
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    /// The pill being touched at all opens the bar. A press on the collapsed
    /// capsule would otherwise hand §9.1 a 22 pt anchor sized to `apple.com`
    /// and let it grow out of that; the bar it belongs to is 52 pt with a
    /// 420 pt pill in it, and that is the shape the panel should take.
    ///
    /// Opened without animation, unlike every other change of this state:
    /// the panel reads the pill's frame on the frame it is created, and a pill
    /// two hundred milliseconds into a morph would be read mid-flight. Nothing
    /// is lost — the panel covers the bar for the whole of the animation that
    /// is not being run.
    ///
    /// The bar then stays open for as long as §9.1 is standing on it, whatever
    /// the page does: see `PageChromeController.pageScrolled(to:)`.
    private func wirePill() {
        pill.onHandOff = { [weak self] in
            guard let self else { return }
            setCollapsed(false, animated: false)
            onEditingBegan?()
            onHandOff?(CommandBarAnchor(view: pill) { [weak self] in self?.onEditingEnded?() })
        }
    }

    // MARK: - State

    func show(url: URL?) {
        pill.show(url: url)
        needsLayout = true
    }

    func update(canGoBack: Bool, canGoForward: Bool, isLoading: Bool) {
        let was = nav.intrinsicContentSize.width
        nav.update(canGoBack: canGoBack, canGoForward: canGoForward)
        if nav.intrinsicContentSize.width != was {
            // The cluster has changed shape, so what stands beside it has to
            // travel rather than jump. Back does not move — see the cluster's
            // own layout — so all this carries is its trailing end and, on a
            // pane too narrow to centre the pill, the pill.
            Tokens.Motion.animate(Tokens.Motion.sidebarCollapse) { context in
                context.allowsImplicitAnimation = true
                placeControls()
            }
        }
        self.isLoading = isLoading
        pill.setLoading(isLoading)
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
        // Un-hidden before the fade in either direction: a view cannot fade
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

}
