//
//  ReloadBloomView.swift
//  Luna
//
//  UI-SPEC §7 — the reload bloom: a prismatic arc over the content card while
//  a page loads, bound to real load progress rather than to a fixed duration.
//
//  The arc's colours and the blur's cost live in `ReloadBloomArc.swift`; the
//  "a load under 0.15 s plays nothing" rule lives in `ReloadBloomTimeline`.
//  What is left here is the view: four layers, and when each one moves.
//
//  §7's de-blur stagger is the blur's own trick again: five horizontal strips
//  of the one snapshot fading out 40 ms apart, revealing the finished live page
//  underneath. No filter is ever animated.
//

import AppKit
import BrowserKit
import QuartzCore
import WebKit

/// The §7 bloom. Decorative: it never takes a click and is invisible to
/// VoiceOver — the loading state is announced by the chrome, not by this.
@MainActor
final class ReloadBloomView: NSView {

    // MARK: - Wiring

    /// The active tab's live web view, i.e. `BrowserSession.webView(for:)` for
    /// the tab that is on screen. Weak on purpose: a hibernating tab drops its
    /// web view (§19.2) and the bloom must not be what keeps one alive.
    weak var source: NSView?

    /// Feed every `BrowserSession.onTabStateChange` for the active tab.
    func update(_ state: TabState) {
        progress = state.progress
        switch timeline.loading(state.isLoading) {
        case .arm: arm()
        case .disarm: armTask?.cancel(); armTask = nil
        case .end: finish()
        case .begin, .nothing: break
        }
        if timeline.phase == .playing {
            advance()
        }
    }

    /// The active tab changed, or the window is going away. Instant: the page
    /// this bloom belonged to is not on screen any more, so there is nothing
    /// to animate out.
    func reset() {
        if timeline.cancel() != .nothing {
            teardown()
        }
    }

    /// Adds the bloom inside `card`, above whatever the card is showing.
    /// A subview rather than a sibling so the card's own corner mask clips it
    /// for free — §7's "above the content card, below the chrome" then holds
    /// by construction, because the chrome is not in the card.
    func install(in card: NSView) {
        translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(self, positioned: .above, relativeTo: nil)
        NSLayoutConstraint.activate([
            topAnchor.constraint(equalTo: card.topAnchor),
            leadingAnchor.constraint(equalTo: card.leadingAnchor),
            bottomAnchor.constraint(equalTo: card.bottomAnchor),
            trailingAnchor.constraint(equalTo: card.trailingAnchor)
        ])
    }

    // MARK: - State

    /// Horizontal strips the de-blur is staggered across. Five is what §7's
    /// 0.30 s and 40 ms divide into while each strip still fades for longer
    /// than the stagger (0.14 s), so the sweep reads as one motion.
    private static let bandCount = 5

    // ponytail: a fixed 0.5 stands in for "the new document has committed and
    // is painting", which `TabState` does not expose. If it ever does, key off
    // that instead — the ceiling here is that a page stalling just under 0.5
    // keeps the stale blur until it finishes.
    /// Progress at which the frozen snapshot is let go even though the load is
    /// still running, so a slow page is never hidden behind a picture of the
    /// old one.
    private static let snapshotRelease = 0.5

    private var timeline = ReloadBloomTimeline()
    private var progress: Double = 0
    /// Captured once at `begin` so a mid-bloom Reduce Motion flip cannot leave
    /// the run half in one mode and half in the other.
    private var isReduced = false

    private let arcLayer = CAGradientLayer()
    private let lineLayer = CALayer()
    private var bands: [CALayer] = []
    private var blurReleased = false
    private let pageBlur = PageBlur()

    private var armTask: Task<Void, Never>?
    private var endTask: Task<Void, Never>?
    private var blurTask: Task<Void, Never>?

    // MARK: - Lifecycle

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        isHidden = true
        setAccessibilityElement(false)

        arcLayer.type = .radial
        arcLayer.startPoint = ReloadArc.centre
        arcLayer.endPoint = CGPoint(
            x: ReloadArc.centre.x + ReloadArc.radius.width,
            y: ReloadArc.centre.y - ReloadArc.radius.height
        )
        arcLayer.locations = ReloadArc.stops
        arcLayer.opacity = 0
        lineLayer.isHidden = true
        layer?.addSublayer(arcLayer)
        layer?.addSublayer(lineLayer)

        // NotificationCenter zeroes selector observers on dealloc, so there is
        // nothing to remove — the pattern `GlassBackingView` already uses.
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(accessibilityDisplayOptionsChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    /// §7: decoration. It must never take a click away from the page.
    override func hitTest(_: NSPoint) -> NSView? {
        nil
    }

    override var mouseDownCanMoveWindow: Bool {
        false
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            reset()
        }
    }

    // MARK: - Appearance

    override var wantsUpdateLayer: Bool {
        true
    }

    /// Called with this view's appearance already current, so the tokens
    /// resolve for the right theme and contrast setting.
    override func updateLayer() {
        arcLayer.colors = ReloadArc.bands.map(\.cgColor)
        lineLayer.backgroundColor = Tokens.Accent.tint.cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    /// Contract rule 4: Increase Contrast is not an `NSAppearance` on macOS
    /// 26.5, so nothing invalidates on its own.
    @objc private func accessibilityDisplayOptionsChanged() {
        needsDisplay = true
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        let scale = window?.backingScaleFactor ?? 1
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        arcLayer.bounds = CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height * (1 + ReloadArc.drift))
        arcLayer.position = arcPosition(for: progress)
        arcLayer.contentsScale = scale
        lineLayer.frame = progressLineFrame()
        lineLayer.contentsScale = scale
        layoutBands(scale: scale)
        CATransaction.commit()
    }

    private func arcPosition(for progress: Double) -> CGPoint {
        let travel = bounds.height * ReloadArc.drift
        // The view is unflipped, so "downward" is decreasing y. At progress 0
        // the arc layer's top edge sits on the card's; at 1 it has slid `travel`
        // below it, and the layer is that much taller so the bottom still covers.
        let top = bounds.maxY - travel * CGFloat(progress)
        return CGPoint(x: bounds.midX, y: top - (bounds.height + travel) / 2)
    }

    private func layoutBands(scale: CGFloat) {
        let count = CGFloat(Self.bandCount)
        let height = bounds.height / count
        for (index, band) in bands.enumerated() {
            // Band 0 is the top of the card. View geometry is y-up so the top
            // band has the highest origin, while `contentsRect` indexes the
            // snapshot y-down — hence the two different index expressions.
            band.frame = CGRect(
                x: bounds.minX,
                y: bounds.maxY - CGFloat(index + 1) * height,
                width: bounds.width,
                height: height
            )
            band.contentsRect = CGRect(x: 0, y: CGFloat(index) / count, width: 1, height: 1 / count)
            band.contentsScale = scale
        }
    }

    private func progressLineFrame() -> CGRect {
        let height = Tokens.Metric.reloadProgressLine
        return CGRect(x: bounds.minX, y: bounds.maxY - height, width: bounds.width * CGFloat(progress), height: height)
    }

    // MARK: - Phases

    private func arm() {
        armTask?.cancel()
        armTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Tokens.Motion.reloadSkipThreshold))
            guard !Task.isCancelled, let self else { return }
            if timeline.thresholdPassed() == .begin {
                begin()
            }
        }
    }

    private func begin() {
        // `ContentCardView.setContent` puts the web view on top whenever a tab
        // is activated, so re-assert z-order here rather than making the window
        // controller remember an ordering rule.
        superview?.addSubview(self, positioned: .above, relativeTo: nil)
        isReduced = Tokens.Motion.reduceMotion
        blurReleased = false
        isHidden = false

        guard !isReduced else {
            // §7: no blur, no arc — a 2 pt progress line, because the user
            // still has to know the page is loading.
            lineLayer.isHidden = false
            advance()
            return
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        arcLayer.position = arcPosition(for: progress)
        CATransaction.commit()
        arcLayer.fade(to: 1, Tokens.Motion.reloadArcIn)

        guard let web = source as? WKWebView else { return }
        pageBlur.capture(web, viewHeight: bounds.height) { [weak self] blurred in
            self?.showBlur(blurred)
        }
    }

    /// §7's hold: the arc tracks real progress instead of running on a clock.
    private func advance() {
        guard !isReduced else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            lineLayer.frame = progressLineFrame()
            CATransaction.commit()
            return
        }
        // Linear, and over the arc-in duration: `estimatedProgress` arrives in
        // lumps, so without a glide the arc would visibly step.
        CATransaction.begin()
        CATransaction.setAnimationDuration(Tokens.Motion.reloadArcIn.duration)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .linear))
        arcLayer.position = arcPosition(for: progress)
        CATransaction.commit()

        if progress >= Self.snapshotRelease {
            releaseBlur()
        }
    }

    private func finish() {
        guard !isReduced else { teardown(); return }
        arcLayer.fade(to: 0, Tokens.Motion.reloadArcOut)
        releaseBlur()
        endTask?.cancel()
        endTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Tokens.Motion.reloadArcOut.duration))
            guard !Task.isCancelled else { return }
            self?.teardown()
        }
    }

    private func teardown() {
        armTask?.cancel(); armTask = nil
        endTask?.cancel(); endTask = nil
        blurTask?.cancel(); blurTask = nil
        discardBlur()
        blurReleased = false
        progress = 0
        arcLayer.removeAllAnimations()
        arcLayer.opacity = 0
        lineLayer.isHidden = true
        isHidden = true
    }

    // MARK: - The blurred snapshot

    private func showBlur(_ image: CGImage) {
        guard timeline.phase == .playing, !isReduced, bands.isEmpty, !blurReleased else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        bands = (0 ..< Self.bandCount).map { _ in
            let band = CALayer()
            // One `CGImage` across all five strips: Core Animation uploads the
            // texture once and each strip is a cheap quad over `contentsRect`.
            band.contents = image
            band.contentsGravity = .resize
            band.masksToBounds = true
            band.opacity = 0
            layer?.insertSublayer(band, below: arcLayer)
            return band
        }
        layoutBands(scale: window?.backingScaleFactor ?? 1)
        CATransaction.commit()
        for band in bands {
            band.fade(to: 1, Tokens.Motion.reloadArcIn)
        }
    }

    /// §7's de-blur: 0.30 s total, staggered 40 ms top to bottom.
    private func releaseBlur() {
        guard !bands.isEmpty, !blurReleased else { return }
        blurReleased = true
        let stagger = Tokens.Motion.reloadDeblurStagger
        let spread = Double(Self.bandCount - 1) * stagger
        let each = max(stagger, Tokens.Motion.reloadArcOut.duration - spread)
        for (index, band) in bands.enumerated() {
            band.fade(to: 0, Tokens.Motion.reloadArcOut, duration: each, delay: Double(index) * stagger)
        }
        blurTask?.cancel()
        blurTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(each + spread))
            guard !Task.isCancelled else { return }
            self?.discardBlur()
        }
    }

    private func discardBlur() {
        for band in bands {
            band.contents = nil
            band.removeFromSuperlayer()
        }
        bands = []
    }
}
