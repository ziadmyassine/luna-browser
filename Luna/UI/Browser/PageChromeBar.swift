//
//  PageChromeBar.swift
//  Luna
//
//  §3.2b: the sidebar's head, on the page. With the search bar set "On the
//  page", §3.1's circles and §3.2's pill sit on a bar across the top of the
//  content pane; the sidebar keeps its top 52 pt for the traffic lights.
//
//  A plane in the page's own colour, not floating glass: no material in Luna
//  can react to the page (measured, see `Glass.peekPlane`), and over a white
//  site the white circles vanished. It follows the page down as it scrolls
//  (`TabController+Scroll`) and wears the appearance that plane calls for —
//  the one surface whose background is not Luna's. One state however far the
//  page scrolls: a strip that shrank on scroll lagged on every change of direction.
//
//  Reload and site settings belong to `URLPillView`; the address is typed in
//  §9.1, which grows out of this capsule (`CommandBarAnchor`). §4 has no page bar.
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
            shelf.isHidden = !showsShelf
            needsLayout = true
        }
    }
    /// The agent's button, at the end of the extensions cylinder. Nil leaves it off.
    var onAgent: (() -> Void)? {
        get { shelf.onAgent }
        set {
            shelf.onAgent = newValue
            shelf.isHidden = !showsShelf
            needsLayout = true
        }
    }
    /// The width the controls were last placed for: none yet is a first
    /// layout, which never animates (`PageChromeBarLayout`).
    var placedWidth: CGFloat = 0
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
        setAccessibilityElement(true)
        setAccessibilityRole(.toolbar)
        setAccessibilityLabel(String(localized: "Page bar"))
        applyPlane(animated: false)
        watchForTheLights() // The one thing that moves without resizing this view.
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    override func accessibilityChildren() -> [Any]? {
        super.accessibilityChildren().map { AccessibilityOrder.reading($0) }
    }

    /// Hides the sidebar while it is showing, and shows it while it is hidden
    /// or while the top bar has the window, so it says which.
    func setSidebarShown(_ shown: Bool) {
        toggle.setAccessibilityLabel(shown ? String(localized: "Hide Sidebar") : String(localized: "Show Sidebar"))
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
