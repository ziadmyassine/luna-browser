//
//  PageChromeBar.swift
//  Luna
//
//  §3.2b: the sidebar's head, on the page.
//
//  When Settings ▸ Appearance puts the search bar "On the page", the three §3.1
//  circles and the §3.2 pill leave the sidebar and float over the content pane
//  instead. The sidebar keeps its tabs, its Essentials and its bottom bar — and
//  its top 52 pt, because that is what holds the traffic lights' corner clear.
//
//  **Two states, and the page decides which.** At the top of a document the bar
//  is open: toggle, back, reload and a wide centred pill. Once the page has
//  scrolled past `pageBarScrollSlack` the buttons fade out and the pill shrinks
//  to a capsule around the domain, so the page gets its top edge back. Scrolling
//  up, or arriving anywhere new, opens it again. `PageChromeController` owns
//  that decision; this view owns what the two states look like.
//
//  **It has no background of its own**, which is not an omission. Every control
//  on it already carries its own material — the circles are glass, the pill is
//  §3.2's well — and a bar behind them would be a fourth surface laid over a
//  live web page, which is the one thing no material in Luna can do honestly:
//  `NSGlassEffectView` composites what is behind the *window*, and
//  `NSVisualEffectView` will not sample a `WKWebView`'s out-of-process layer.
//  Both are measured in `Glass.peekPlane`'s note. So the controls float, and
//  what is between them is the page.
//

import AppKit

@MainActor
final class PageChromeBar: NSView {

    var onToggleSidebar: (() -> Void)?
    var onBack: (() -> Void)?
    var onReloadOrStop: ((_ isLoading: Bool) -> Void)?
    var onSubmitURL: ((String) -> Void)?

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
    private var isLoading = false
    private(set) var isCollapsed = false

    private var buttons: [NSView] { [toggle, back, reload] }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        pill.centresText = true
        // Same material as the three circles, at the same time: over a page
        // there is no plane for a well to be cut into. See `URLPillView`.
        pill.alwaysGlass = true
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
        for view in buttons + [pill] { addSubview(view) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
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

    /// §3.2b's two states. Animated on `sidebarCollapse` — the same 0.20 s the
    /// sidebar itself slides on, because this is the same piece of chrome
    /// getting out of the page's way.
    func setCollapsed(_ collapsed: Bool, animated: Bool) {
        guard collapsed != isCollapsed else { return }
        isCollapsed = collapsed
        // Un-hidden *before* the fade in either direction: a view cannot fade
        // from `isHidden`, and the fade out hides it again on completion.
        if !collapsed { for view in buttons { view.isHidden = false } }
        guard animated else {
            Tokens.Motion.immediately { applyState() }
            for view in buttons { view.isHidden = collapsed }
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
            }
        }
    }

    // MARK: - Layout

    /// The bar is the full width of the pane and as tall as its **open** state,
    /// whatever state it is in: nothing here resizes, so the controls can travel
    /// inside a frame that is standing still. `hitTest` is what keeps the empty
    /// part of it from taking the page's clicks.
    override func layout() {
        super.layout()
        Tokens.Motion.immediately { applyState() }
    }

    private func applyState() {
        placeControls()
        for view in buttons { view.alphaValue = isCollapsed ? 0 : 1 }
    }

    private func placeControls() {
        let circle = Tokens.Metric.sidebarCircle
        let lights = TrafficLightSpace.rect(in: self)
        // The bar's own band, and the line the controls sit on inside it.
        //
        // **The traffic lights are that line whenever they are on screen.** The
        // pane is flush to the window's top in every state this bar appears in,
        // so the lights' centre is a line this view shares with §3.1's control
        // row — and the two must agree, because with the sidebar showing they
        // are 280 pt apart on the same row of pixels.
        let band = isCollapsed ? Tokens.Metric.pageBarCollapsed : Tokens.Metric.pageBar
        let centreY = isCollapsed
            ? bounds.maxY - band / 2
            : (lights?.midY ?? bounds.maxY - band / 2)

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

        // **Centred on the pane when there is room, and pushed off centre when
        // there is not.** A 640 pt window with a sidebar open leaves about
        // 230 pt beside the buttons; a pill centred in that overlaps them, and
        // an overlapping pill is worse than an off-centre one.
        // **The buttons' own diameter, not the pill's own height token.** The
        // two are the same 34 pt today — `sidebarCircle` is defined as a circle
        // of `urlPill.height` — and on this bar they have to *stay* the same:
        // four controls on one line, one of them a different height, is the
        // thing the eye finds first.
        let height = isCollapsed ? Tokens.Metric.pageBarCollapsedPillHeight : circle.height
        let left = isCollapsed
            ? Tokens.Metric.pageBarInset
            : buttonsEnd + Tokens.Metric.chromeGapWide
        let right = bounds.maxX - Tokens.Metric.pageBarInset
        let ceiling = isCollapsed ? pill.fittingWidth : Tokens.Metric.pageBarPillWidth
        let width = min(ceiling, max(right - left, 0))
        let centred = bounds.midX - width / 2
        pill.frame = NSRect(
            x: min(max(centred, left), max(right - width, left)),
            y: centreY - height / 2,
            width: width,
            height: height
        ).pixelAligned
    }

    // MARK: - Events

    /// **Only the controls take events.** The bar covers the top of a live web
    /// page, and everything it does not draw on belongs to the page: a link
    /// under the gap between the buttons and the pill has to stay clickable.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
    }

    /// The page is not a drag handle, and neither is the air above it.
    override var mouseDownCanMoveWindow: Bool { false }
}
