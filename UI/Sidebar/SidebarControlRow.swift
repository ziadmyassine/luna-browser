//
//  SidebarControlRow.swift
//  Luna
//
//  §3.1, 52 pt: `[traffic lights] · [toggle squircle 28] ··· [back 35] [reload 35]`.
//
//  **The traffic lights are not laid out here.** `TrafficLightLayoutManager`
//  owns their frames for all six window states (§7.7); this row only has to
//  leave their space clear, and it does that by *measuring* them — converting
//  the zoom button's frame out of the titlebar and into this row — rather than
//  hard-coding a width that AppKit is free to change.
//
//  One deliberate departure from §3.1's written order: the reference puts the
//  toggle beside the traffic lights and pins back/reload to the **trailing**
//  edge (measured at ~209 pt and ~251 pt centres in a 280 pt sidebar), not
//  16 pt after the toggle. §3.1's gap figure describes a cluster the reference
//  does not have; the image wins (§30).
//

import AppKit

@MainActor
final class SidebarControlRow: NSView {

    var onToggleSidebar: (() -> Void)?
    var onBack: (() -> Void)?
    /// Reload, or stop while the page is loading.
    var onReloadOrStop: ((_ isLoading: Bool) -> Void)?

    private let toggle = GlassButton(
        shape: Tokens.Metric.controlSquircle,
        symbolName: "sidebar.leading",
        pointSize: Tokens.Metric.faviconSize,
        label: "Hide Sidebar"
    )
    private let back = GlassButton(
        shape: Tokens.Metric.controlCircle,
        symbolName: "chevron.backward",
        pointSize: Tokens.Metric.faviconSize,
        label: "Back"
    )
    private let reload = GlassButton(
        shape: Tokens.Metric.controlCircle,
        symbolName: "arrow.clockwise",
        pointSize: Tokens.Metric.faviconSize,
        label: "Reload"
    )
    private var isLoading = false

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

    /// The right edge of the system's traffic lights, in this row's
    /// coordinates. Measured, because `TrafficLightLayoutManager` owns the
    /// placement and AppKit owns the button sizes.
    private var trafficLightsTrailing: CGFloat {
        guard let button = window?.standardWindowButton(.zoomButton),
              let titlebar = button.superview
        else { return Tokens.Metric.rowInset }
        return convert(titlebar.convert(button.frame, to: nil), from: nil).maxX
    }

    override func layout() {
        super.layout()
        let inset = Tokens.Metric.rowInset
        let squircle = Tokens.Metric.controlSquircle
        let circle = Tokens.Metric.controlCircle
        toggle.frame = NSRect(
            x: trafficLightsTrailing + 2 * inset,
            y: (bounds.height - squircle.height) / 2,
            width: squircle.width,
            height: squircle.height
        ).integral
        let circleY = (bounds.height - circle.height) / 2
        reload.frame = NSRect(
            x: bounds.maxX - inset - circle.width,
            y: circleY,
            width: circle.width,
            height: circle.height
        ).integral
        back.frame = NSRect(
            x: reload.frame.minX - inset - circle.width,
            y: circleY,
            width: circle.width,
            height: circle.height
        ).integral
    }
}
