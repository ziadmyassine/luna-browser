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
//  lights' corner clear. §4's top bar has no page bar: its tabs open the
//  address in the Command Bar.
//
//  The bar is a plane in the page's own colour. Floating controls with nothing
//  behind them were tried, and the reason they do not work is that no material
//  in Luna can react to the page: `NSGlassEffectView` composites what is behind
//  the window, and `NSVisualEffectView` will not sample a `WKWebView`'s
//  out-of-process layer (both measured, both in `Glass.peekPlane`). Over a
//  white site the glass showed a light desktop and three white circles vanished
//  into a white page. A plane from `TabState.pageBackground` is the colour the
//  page is painted on, so it reads as the site's own top edge and is a known
//  surface, which is what the controls on it need.
//
//  It follows the page down. `pageBackground` is one answer for a whole
//  document, so a bar wearing it stayed white all the way down a site whose
//  second section is black. What is under the bar is a question only the page
//  can answer, so `TabController+Scroll` asks it as the page scrolls.
//
//  The bar wears the appearance that plane calls for. Everything drawn here
//  resolves from an `NSAppearance`, so one assignment re-inks all of it. A dark
//  app over a white site gets dark glyphs on the bar and light ones everywhere
//  else, which is correct rather than inconsistent: this is the only surface in
//  Luna whose background is not Luna's.
//
//  One state: the toggle, the history cluster and a wide pill with a control
//  at each end of it, however far the page scrolls. It used to shrink to a
//  strip of site colour once the page scrolled, and the change lagged on every
//  turn of direction, so it was taken out.
//
//  Reload is not on this bar. It is inside the capsule on its trailing edge,
//  with site settings on the leading one, and both belong to `URLPillView`.
//
//  The address is not typed here either: the pill hands the whole job to §9.1,
//  which opens on this capsule and grows down out of it (`CommandBarAnchor`),
//  the same hand-off the sidebar's pill makes. What this bar had instead was
//  `PageBarSuggestions` — search phrases and nothing else, no open tabs, no
//  history, no commands, no autofill.
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
    /// How much room the bar is taking, whenever that changes. The page runs
    /// under it and is told this much is covered — see
    /// `ContentCardView.setContentTopInset`.
    var onBandHeight: ((_ height: CGFloat, _ animated: Bool) -> Void)?
    /// §16.4: a pinned extension, and the button that lists them all, each
    /// with the view its popup or pop-out opens on.
    var onExtension: ((String, NSView) -> Void)?
    var onExtensions: ((NSView) -> Void)?

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
    /// §16.4's cylinder in the trailing corner, as tall as the circles at the
    /// other end: the extensions button, and the pins it grows to hold.
    let shelf = PageBarExtensionShelf()
    var extensionPins: [ExtensionShelfItem] = [] { didSet { needsLayout = true } }
    var showsExtensions = false {
        didSet {
            shelf.isHidden = !showsExtensions
            needsLayout = true
        }
    }
    private var isLoading = false
    /// The document's own background, the strip under the bar, and whichever of
    /// the two is on the plane right now.
    private var documentColour: NSColor?
    private var topColour: NSColor?
    private var pageColour: NSColor?

    /// The bar's own controls, in the order they are laid out.
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
        pill.onReading = { [weak self] in
            guard let self else { return }
            ReadingMenu.present(from: pill.readingAnchor)
        }
        shelf.isHidden = true
        shelf.onPin = { [weak self] id, anchor in self?.onExtension?(id, anchor) }
        shelf.onExtensions = { [weak self] anchor in self?.onExtensions?(anchor) }
        for view in buttons + [pill, shelf] { addSubview(view) }
        wirePill()
        applyPlane(animated: false)
        watchForTheLights() // The one thing that moves without resizing this view.
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    /// The pill hands the address to §9.1, which opens standing on it.
    private func wirePill() {
        pill.onHandOff = { [weak self] in
            guard let self else { return }
            onHandOff?(CommandBarAnchor(view: pill, startFrame: nil, onDismiss: nil))
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
