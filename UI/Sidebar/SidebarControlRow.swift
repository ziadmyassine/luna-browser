//
//  SidebarControlRow.swift
//  Luna
//
//  §3.1, 52 pt: `[traffic lights] · [toggle 28] ··· [back 28] [reload 28]`.
//
//  **The traffic lights are not laid out here.** `TrafficLightLayoutManager`
//  owns their frames for all six window states (§7.7); this row only has to
//  leave their space clear. It does that by measuring what AppKit owns and
//  never moves — the buttons' size, and the spacing between them — and deriving
//  the rest from `trafficLightInset`, the one number the manager places them
//  with. Reading their live origins instead is a race this row loses on every
//  resize; see `trafficLights`.
//
//  Two deliberate departures from §3.1's written order, both measured off
//  `inspiration/main-tab-bar-and-ui.png`:
//
//  · the reference puts the toggle beside the traffic lights and pins
//    back/reload to the **trailing** edge, not 16 pt after the toggle. §3.1's
//    gap figure describes a cluster the reference does not have.
//  · **the toggle is the same circle as its two neighbours**, not the squircle
//    §3.1 quotes, and its glyph sits on the same centre line as the traffic
//    lights — which is why this row asks the window for that line rather than
//    centring in its own 52 pt.
//
//  The circle is `Metric.sidebarCircle` — the URL pill's own height — so the
//  sidebar's head is one stack of equal-height controls instead of three small
//  buttons above a bigger one. All three carry their glass at rest: the toggle
//  is how you get the sidebar back, and a control you cannot see until you
//  happen to sweep the pointer over it is not one.
//

import AppKit

@MainActor
final class SidebarControlRow: NSView {

    var onToggleSidebar: (() -> Void)?
    var onBack: (() -> Void)?
    /// Reload, or stop while the page is loading.
    var onReloadOrStop: ((_ isLoading: Bool) -> Void)?

    /// **Always glass.** It briefly carried its material on hover only; that
    /// made the one control that brings a hidden sidebar back invisible until
    /// the pointer found it, which is the wrong trade for the one button on
    /// this row that is not reachable any other way.
    private let toggle = GlassButton(
        shape: Tokens.Metric.sidebarCircle,
        symbolName: "sidebar.leading",
        pointSize: Tokens.Metric.glyphSize,
        label: "Hide Sidebar"
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
    private var isLoading = false
    /// Whether the last pass found the traffic lights. See `placeButtons`.
    private var hadLights = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        toggle.onActivate = { [weak self] in self?.onToggleSidebar?() }
        back.onActivate = { [weak self] in self?.onBack?() }
        reload.onActivate = { [weak self] in
            guard let self else { return }
            onReloadOrStop?(isLoading)
        }
        for view in [toggle, back, reload] { addSubview(view) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: Tokens.Metric.topBarHeight)
    }

    // MARK: - State

    /// §3.1: back dims when there is nowhere to go, and reload becomes a stop
    /// glyph for as long as the page is loading.
    func update(canGoBack: Bool, isLoading: Bool) {
        back.isEnabled = canGoBack
        guard isLoading != self.isLoading else { return }
        self.isLoading = isLoading
        reload.setSymbol(isLoading ? "xmark" : "arrow.clockwise")
        reload.setAccessibilityLabel(isLoading ? "Stop" : "Reload")
    }

    // MARK: - Layout

    /// The space the three traffic lights occupy, in this row's coordinates —
    /// or nil when there are none to clear.
    ///
    /// **Sizes are measured; positions are not.** AppKit resets the buttons'
    /// origins on every window resize and `TrafficLightLayoutManager` puts them
    /// back a beat later, *after* this row has already laid out — so a row that
    /// read `zoomButton.frame.midY` was reading AppKit's own placement, nine
    /// points higher than the one that ends up on screen, and drew its three
    /// circles clipped against the window's top edge until something else made
    /// it dirty. What does not race is the buttons' size and the spacing
    /// between them, which AppKit owns and never changes, and
    /// `trafficLightInset`, which is the single number `TrafficLightLayout`
    /// places them with. Measure the first, derive the second, and the row
    /// lands on the lights whatever order the two passes run in.
    private var trafficLights: NSRect? {
        guard let window,
              let close = window.standardWindowButton(.closeButton),
              let zoom = window.standardWindowButton(.zoomButton),
              // In fullscreen macOS takes the buttons away (they come back on a
              // hover at the top of the screen) but leaves their frames behind.
              // Reserving that space anyway left a hole at the head of the row
              // where three lights used to be.
              !zoom.isHiddenOrHasHiddenAncestor,
              !window.styleMask.contains(.fullScreen),
              let root = window.contentView
        else { return nil }
        let inset = Tokens.Metric.trafficLightInset
        // Close's leading edge to zoom's trailing edge: AppKit's own spacing,
        // whatever it is, and the same distance wherever the row happens to be.
        let span = zoom.frame.maxX - close.frame.minX
        let corner = convert(NSPoint(x: root.bounds.minX, y: root.bounds.maxY), from: root)
        let lights = NSRect(
            x: corner.x + inset,
            y: corner.y - inset - zoom.frame.height,
            width: max(span, zoom.frame.width),
            height: zoom.frame.height
        )
        // **And nil when they are not on this row at all.** macOS keeps the
        // lights at the window's top-left and offers no way to move them, so a
        // sidebar standing on the *trailing* edge does not contain them — they
        // float over the page instead, which is what every browser that offers
        // a right-hand sidebar does. Reserving their space anyway would push
        // the toggle off the column entirely; that is what a rect starting left
        // of this row is saying.
        return lights.minX >= bounds.minX ? lights : nil
    }

    override func layout() {
        super.layout()
        Tokens.Motion.immediately { placeButtons() }
    }

    private func placeButtons() {
        let inset = Tokens.Metric.rowInset
        let circle = Tokens.Metric.sidebarCircle
        let lights = trafficLights
        // **A nil that was not nil a moment ago is worth asking about twice.**
        // The buttons are legitimately gone in fullscreen and while the sidebar
        // is hidden, and then this row closes up around the space they left.
        // But AppKit also rebuilds the titlebar from time to time, and a pass
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
        back.frame = NSRect(
            x: reload.frame.minX - Tokens.Metric.controlPairGap - circle.width,
            y: originY,
            width: circle.width,
            height: circle.height
        ).pixelAligned
    }
}
