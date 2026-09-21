//
//  LoadProgressLine.swift
//  Luna
//
//  §3.2c: how far the page has loaded, drawn as a line under the address.
//
//  **On the bottom of the search bar, wherever the search bar is.** Luna has
//  three of them — §3.2's in the column, §3.2b's on the page, §4's in the top
//  bar — and the line is the same line on all three: `loadLineHeight` thick,
//  lying on the inside of the pill's bottom edge, running the pill's whole
//  width from the leading end, and **cut at both ends by the capsule itself**.
//  The host owns the frame; this owns what is in it, so there is one set of
//  rules about when a progress bar is allowed to be on screen rather than one
//  per surface.
//
//  It is the *pill* filling up, not a rule drawn inside one. A line held clear
//  of the bottom edge, with its own rounded ends, is a second object floating
//  in the capsule; a line lying on the edge and ending where the corner takes
//  it away is the bottom of the capsule turning blue. The reference measures
//  the second: the blue run ends exactly where the capsule's bottom stroke
//  begins, and its leading end is the corner's curve rather than a cap.
//
//  **When no pill is on screen the window's top edge wears it** — see
//  `LoadProgressHost`. That is the sidebar layout with the sidebar hidden and
//  the search bar still in the column: the address bar is parked off screen,
//  and a load with nothing to show for it is the one case worth a fallback.
//
//  Three rules keep it honest, and all three are about *not* drawing:
//
//  1. **A load under `reloadSkipThreshold` plays nothing.** §7 wrote that rule
//     down for the bloom and it is the same rule here: a cached reload is done
//     before a progress bar could say anything true about it, and a 2 pt line
//     flashing on every back-navigation is worse than no line at all.
//  2. **It never goes backwards.** `estimatedProgress` can fall when a load
//     commits a new document, and a bar that retreats reads as a fault in the
//     page rather than a fact about it.
//  3. **It finishes before it leaves.** The fill runs to full and *then* fades,
//     so the last thing seen is a full line, not a bar that vanished at four
//     fifths.
//

import AppKit
import BrowserKit

/// Which surface wears §3.2c's line, given the chrome on screen.
///
/// Pure, and tested the way `ChromeState.cardInsets` is: the three pill cases
/// exist so the fallback has something to be the absence of, and the window
/// controller only ever asks whether the answer is `.windowTop`.
enum LoadProgressHost: Equatable {
    /// §3.2's pill, in the sidebar's column.
    case sidebarPill
    /// §3.2b's pill, on the bar over the page.
    case pageBarPill
    /// §4's pill, the active tab in the top bar's strip.
    case topBarPill
    /// Nothing is showing an address: the top edge of the window takes it.
    case windowTop
}

extension ChromeState {

    /// - Parameter searchBarOnPage: `Settings.searchBarIsOnPage`, resolved by
    ///   the one reader that owns it (`AppDelegate.applySearchBarPlacement`)
    ///   rather than read again here. The placement is only meaningful in the
    ///   sidebar layout, and a second reader is how the two ends of that
    ///   question start disagreeing.
    func loadProgressHost(searchBarOnPage: Bool) -> LoadProgressHost {
        if searchBarOnPage { return .pageBarPill }
        return switch self {
        case .sidebar: .sidebarPill
        case .topBar: .topBarPill
        // The column is parked off screen, and page fullscreen has taken the
        // chrome with it. Neither has an address bar the user can see.
        case .sidebarCollapsed, .fullscreen: .windowTop
        }
    }
}

/// The line itself. Decorative: it takes no clicks and says nothing to
/// VoiceOver — loading is announced by the chrome (§3.4's rows dim and
/// shimmer, the reload glyph becomes a stop), not by a 2 pt rectangle.
@MainActor
final class LoadProgressLine: NSView {

    /// The fill, as a fraction. This is the **target**: it is assigned before
    /// the animator starts interpolating, so a layout pass that lands mid
    /// animation snaps to where the line was already going rather than to
    /// where it had got to.
    private(set) var fraction: Double = 0
    /// The tab being described. A switch is not progress — the line resets.
    private var tab: UUID?
    /// Whether a load is in flight, which is not the same question as whether
    /// anything is drawn: between the load starting and `reloadSkipThreshold`
    /// this is true and the line is still invisible.
    private var isRunning = false
    /// The §7 skip rule's timer. Cancelled by a load that finishes first, which
    /// is exactly the load that should play nothing.
    private var reveal: Task<Void, Never>?
    private let fill = NSView()
    /// The capsule the line is lying in, as a mask. Nil-pathed until a pill
    /// places it — the window's top edge (`LoadProgressHost.windowTop`) is a
    /// square line across the whole window and has no capsule to be cut by.
    private let clip = CAShapeLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        fill.wantsLayer = true
        // The leading end is the capsule's corner and the trailing end is the
        // progress head, which is square in the reference: the fill itself is
        // a plain rectangle and neither end is its own.
        addSubview(fill)
        // A mask is not a thing to watch move. Its path is re-cut on every
        // layout pass, and CoreAnimation would happily interpolate each one.
        clip.actions = ["path": NSNull(), "bounds": NSNull(), "position": NSNull()]
        alphaValue = 0
        refreshInk()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    // MARK: - The session's side

    /// One tab's live state. Safe to call on every tick — the work is guarded
    /// by what actually changed.
    func show(_ state: TabState, for tab: UUID?) {
        if tab != self.tab {
            self.tab = tab
            clear()
        }
        guard state.isLoading else { return finish() }
        if !isRunning { begin() }
        // Rule 2: forward only. WebKit reports a *new* document's progress from
        // the bottom, and a redirect two thirds of the way through a page is
        // not the page getting further away.
        advance(to: max(state.progress, fraction))
    }

    /// Everything off, now: no fade, no run to full. For a tab switch and for a
    /// host going off screen — what the line was describing is not what is in
    /// front of the user any more, so there is nothing to finish.
    func clear() {
        reveal?.cancel()
        reveal = nil
        isRunning = false
        fraction = 0
        Tokens.Motion.immediately {
            alphaValue = 0
            layoutFill()
        }
    }

    // MARK: - The line's own side

    private func begin() {
        isRunning = true
        fraction = 0
        Tokens.Motion.immediately {
            alphaValue = 0
            layoutFill()
        }
        // Rule 1. Armed rather than shown: if `finish()` lands first it cancels
        // this, and the whole load passes without a frame of line.
        reveal = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Tokens.Motion.reloadSkipThreshold))
            guard !Task.isCancelled, let self, isRunning else { return }
            Tokens.Motion.animate(Tokens.Motion.loadLineFade) { context in
                context.allowsImplicitAnimation = true
                animator().alphaValue = 1
            }
        }
    }

    private func advance(to next: Double) {
        let clamped = min(max(next, 0), 1)
        guard clamped != fraction else { return }
        fraction = clamped
        Tokens.Motion.animate(Tokens.Motion.loadLineAdvance) { context in
            context.allowsImplicitAnimation = true
            fill.animator().frame = fillFrame
        }
    }

    private func finish() {
        guard isRunning else { return }
        isRunning = false
        reveal?.cancel()
        reveal = nil
        // The load beat the skip threshold: nothing was ever shown, and the
        // right ending is no ending.
        guard alphaValue > 0 else { return clear() }
        // Rule 3: full first, then gone. The fade is started from the run's
        // completion rather than alongside it, or a page that finishes at 0.8
        // fades out while still visibly travelling.
        fraction = 1
        Tokens.Motion.animate(Tokens.Motion.loadLineAdvance) { context in
            context.allowsImplicitAnimation = true
            fill.animator().frame = fillFrame
        } completion: { [weak self] in
            MainActor.assumeIsolated { self?.fadeOut() }
        }
    }

    /// The second half of `finish()`, and the reason it is its own method: each
    /// step has to re-ask whether a *new* load started while it was running.
    /// A reload pressed during the fade owns the line from that moment, and an
    /// out-animation that keeps going is a bar that empties while the page it
    /// belongs to is filling.
    private func fadeOut() {
        guard !isRunning else { return }
        Tokens.Motion.animate(Tokens.Motion.loadLineFade) { context in
            context.allowsImplicitAnimation = true
            animator().alphaValue = 0
        } completion: { [weak self] in
            MainActor.assumeIsolated { self?.settle() }
        }
    }

    private func settle() {
        guard !isRunning else { return }
        Tokens.Motion.immediately {
            fraction = 0
            layoutFill()
        }
    }

    // MARK: - Geometry

    /// Places the line in a pill: §3.2c's one placement, written once because
    /// all three address bars use it and a line that lies on the edge of one
    /// surface and floats inside another is two lines.
    ///
    /// **Two halves, and the second is what makes it the pill's own bottom.**
    /// The strip spans the whole capsule, so the fill reaches the far end at
    /// full; the mask is the capsule, so both ends are taken by the corner
    /// instead of being held clear of it. Without the mask a full-width strip
    /// would draw square corners out past the curve.
    func place(inPill bounds: NSRect, cornerRadius: CGFloat) {
        frame = Self.frame(inPill: bounds)
        clip.path = Self.capsule(inPill: bounds, cornerRadius: cornerRadius)
        layer?.mask = clip
    }

    /// The strip the line lies in: the pill's full width, on the inside of its
    /// bottom edge.
    ///
    /// The pill's bottom edge, not its baseline and not below the capsule: the
    /// line belongs *to* the address bar, and a rule drawn underneath one is a
    /// divider between it and whatever is next.
    static func frame(inPill bounds: NSRect) -> NSRect {
        NSRect(
            x: 0,
            y: Tokens.Metric.loadLineFloor,
            width: bounds.width,
            height: Tokens.Metric.loadLineHeight
        )
    }

    /// The capsule that cuts the line's ends, **in the line's own
    /// coordinates** — which is why it is the well's shape and not the pill's:
    /// the strip already starts at `loadLineFloor`, so the inner edge the line
    /// lies on is this path's y = 0.
    ///
    /// Pure and `static` so the shape can be asked the questions a mask cannot
    /// answer once it is installed: whether a point on the flat run is in it,
    /// and whether a point out in the corner is not.
    static func capsule(inPill bounds: NSRect, cornerRadius: CGFloat) -> CGPath {
        let inset = Tokens.Metric.loadLineFloor
        let well = CGRect(
            x: inset,
            y: 0,
            width: max(bounds.width - inset * 2, 0),
            height: max(bounds.height - inset * 2, 0)
        )
        // A capsule narrower than its own corner is a shape `CGPath` will not
        // draw — §3.2b's pill shrinks with the window, and §4's strip with the
        // tab count.
        let radius = max(min(cornerRadius - inset, min(well.width, well.height) / 2), 0)
        return CGPath(roundedRect: well, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }

    override func layout() {
        super.layout()
        // Bounds-derived frames never animate — see `Motion.immediately`.
        Tokens.Motion.immediately { layoutFill() }
    }

    private func layoutFill() {
        fill.frame = fillFrame
    }

    /// Leading-anchored, so the line grows the way the language reads and the
    /// end that moves is the one the eye is not resting on.
    private var fillFrame: NSRect {
        let width = (bounds.width * fraction).rounded()
        return NSRect(x: 0, y: 0, width: width, height: bounds.height)
    }

    // MARK: - Ink

    private func refreshInk() {
        // §1's colour rule allows the accent as **fill** — which is all this
        // is. It is never text and never a border.
        fill.layer?.backgroundColor = Tokens.Accent.tint.cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshInk()
    }

    /// The line is decoration over a control; it must not eat the click that
    /// hands the address to §9.1.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
