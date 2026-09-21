//
//  LoadProgressLine.swift
//  Luna
//
//  §3.2c: how far the page has loaded, drawn as a line under the address.
//
//  **Under the search bar, wherever the search bar is.** Luna has three of
//  them — §3.2's in the column, §3.2b's on the page, §4's in the top bar — and
//  the line is the same line on all three: `loadLineInset` in from each end,
//  `loadLineFloor` up from the bottom edge, `loadLineHeight` thick, growing
//  from the leading end. The host owns the frame; this owns what is in it, so
//  there is one set of rules about when a progress bar is allowed to be on
//  screen rather than one per surface.
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

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        fill.wantsLayer = true
        fill.layer?.cornerCurve = .continuous
        addSubview(fill)
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

    /// Where the line goes inside a pill of `bounds` — §3.2c's one placement,
    /// written once because all three address bars use it and a line that is
    /// 12 pt in on one surface and 8 on another is two lines.
    ///
    /// The pill's bottom edge, not its baseline and not below the capsule: the
    /// line belongs *to* the address bar, and a rule drawn underneath one is a
    /// divider between it and whatever is next.
    static func frame(inPill bounds: NSRect) -> NSRect {
        let inset = Tokens.Metric.loadLineInset
        return NSRect(
            x: inset,
            y: Tokens.Metric.loadLineFloor,
            width: max(bounds.width - inset * 2, 0),
            height: Tokens.Metric.loadLineHeight
        )
    }


    override func layout() {
        super.layout()
        // Bounds-derived frames never animate — see `Motion.immediately`.
        Tokens.Motion.immediately { layoutFill() }
    }

    private func layoutFill() {
        fill.frame = fillFrame
        fill.layer?.cornerRadius = bounds.height / 2
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
