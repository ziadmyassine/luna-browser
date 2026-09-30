//
//  SidebarControlRow.swift
//  Luna
//
//  §3.1, 52 pt: `[traffic lights] · [toggle] ··· [back · forward] [reload]`.
//  Back grows a forward half when there is somewhere to go (`NavCluster`).
//  Reload stays its own circle: §3.2b's 420 pt bar has room for it in the
//  capsule, and this column's 200 pt pill has a domain in it already.
//
//  The traffic lights are `TrafficLightLayoutManager`'s (§7.7). This row only
//  leaves their space clear, derived from what AppKit never moves; reading
//  their live origins is a race it loses on every resize.
//
//  Two departures from §3.1's written order, measured off
//  `inspiration/main-tab-bar-and-ui.png`: back and reload are pinned to the
//  trailing edge, and the toggle is the same `sidebarCircle` as they are,
//  on the traffic lights' centre line.
//

import AppKit

@MainActor
final class SidebarControlRow: NSView, TrafficLightNeighbour {

    var onToggleSidebar: (() -> Void)?
    var onBack: (() -> Void)?
    /// Forward, which appears only when there is one — see `NavCluster`.
    var onForward: (() -> Void)?
    /// Reload, or stop while the page is loading.
    var onReloadOrStop: ((_ isLoading: Bool) -> Void)?

    /// Always glass, like its neighbours. Material on hover only makes the one
    /// control that brings a hidden sidebar back invisible until the pointer
    /// finds it, and it is not reachable any other way.
    private let toggle = GlassButton(
        shape: Tokens.Metric.sidebarCircle,
        symbolName: "sidebar.leading",
        pointSize: Tokens.Metric.glyphSize,
        label: "Hide Sidebar"
    )
    private let nav = NavCluster()
    private let reload = GlassButton(
        shape: Tokens.Metric.sidebarCircle,
        symbolName: "arrow.clockwise",
        pointSize: Tokens.Metric.glyphSize,
        label: "Reload"
    )
    private var isLoading = false

    /// False when §3.2b has moved these three onto the page. The row itself
    /// stays — it is what keeps the traffic lights' corner clear, and the lights
    /// do not move when the pill does (`TrafficLightLayout` places them the same
    /// way in every layout). Only its buttons go.
    var showsButtons = true {
        didSet {
            guard showsButtons != oldValue else { return }
            for view in [toggle, nav, reload] { view.isHidden = !showsButtons }
        }
    }
    /// Whether the last pass found the traffic lights. See `placeButtons`.
    private var hadLights = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        toggle.onActivate = { [weak self] in self?.onToggleSidebar?() }
        nav.onBack = { [weak self] in self?.onBack?() }
        nav.onForward = { [weak self] in self?.onForward?() }
        reload.onActivate = { [weak self] in
            guard let self else { return }
            onReloadOrStop?(isLoading)
        }
        for view in [toggle, nav, reload] { addSubview(view) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: Tokens.Metric.topBarHeight)
    }

    // MARK: - State

    /// §3.1: back dims when there is nowhere to go, forward is simply not there
    /// until there is, and reload becomes a stop glyph while the page loads.
    func update(canGoBack: Bool, canGoForward: Bool, isLoading: Bool) {
        let was = nav.intrinsicContentSize.width
        nav.update(canGoBack: canGoBack, canGoForward: canGoForward)
        if isLoading != self.isLoading {
            self.isLoading = isLoading
            reload.setSymbol(isLoading ? "xmark" : "arrow.clockwise")
            reload.setAccessibilityLabel(isLoading ? "Stop" : "Reload")
        }
        guard nav.intrinsicContentSize.width != was else { return }
        // The cluster has changed shape and it is pinned to the trailing edge,
        // so its leading end travels. Nothing else on this row moves.
        Tokens.Motion.animate(Tokens.Motion.sidebarCollapse) { context in
            context.allowsImplicitAnimation = true
            placeButtons()
        }
    }

    // MARK: - Layout

    /// The space the three traffic lights occupy, in this row's coordinates —
    /// or nil when there are none to clear. See `TrafficLightSpace` for why the
    /// read is derived rather than taken from the buttons' live origins, and
    /// for the second caller it is shared with.
    ///
    /// And nil when they are not on this row at all. macOS keeps the lights
    /// at the window's top-left and offers no way to move them, so a sidebar
    /// standing on the trailing edge does not contain them — they float over
    /// the page instead, which is what every browser that offers a right-hand
    /// sidebar does. Reserving their space anyway would push the toggle off the
    /// column entirely; that is what a rect starting left of this row is saying.
    private var trafficLights: NSRect? {
        guard let rect = TrafficLightSpace.rect(in: self), rect.minX >= bounds.minX else { return nil }
        return rect
    }

    override func layout() {
        super.layout()
        Tokens.Motion.immediately { placeButtons() }
    }

    private func placeButtons() {
        let inset = Tokens.Metric.rowInset
        let circle = Tokens.Metric.sidebarCircle
        let lights = trafficLights
        // A nil that was not nil a moment ago is worth asking about twice.
        // The buttons are legitimately gone while the sidebar is hidden, and
        // then this row closes up around the space they left. But AppKit also
        // rebuilds the titlebar from time to time — entering fullscreen is one
        // such rebuild, and the lights are moved rather than lost — and a pass
        // that lands inside that rebuild measures nothing and lays the toggle
        // out over the lights it could not see. One more pass on the next tick
        // settles it, and costs nothing when they really are gone: the second
        // pass finds nil as well and stops asking.
        if lights == nil, hadLights {
            DispatchQueue.main.async { [weak self] in self?.needsLayout = true }
        }
        hadLights = lights != nil
        // §3.1: the three buttons share the traffic lights' centre line. The
        // lights sit `trafficLightInset` from the window's top, which is not
        // the centre of a 52 pt row — centring here instead would leave them a
        // point apart, which is exactly the misalignment this row is fixing.
        let centreY = lights?.midY ?? bounds.midY
        let originY = centreY - circle.height / 2
        // With no lights to clear, the toggle starts where any other row does.
        let toggleX = lights.map { $0.maxX + Tokens.Metric.chromeGapWide } ?? inset
        toggle.frame = NSRect(
            x: toggleX,
            y: originY,
            width: circle.width,
            height: circle.height
        ).pixelAligned
        reload.frame = NSRect(
            x: bounds.maxX - inset - circle.width,
            y: originY,
            width: circle.width,
            height: circle.height
        ).pixelAligned
        let navWidth = nav.intrinsicContentSize.width
        nav.frame = NSRect(
            x: reload.frame.minX - Tokens.Metric.controlPairGap - navWidth,
            y: originY,
            width: navWidth,
            height: circle.height
        ).pixelAligned
    }
}
