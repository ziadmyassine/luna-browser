//
//  CommandBarPanelLayout.swift
//  Luna
//
//  Where §9.1's bar stands, how big it is, and how it opens.
//
//  Split out of `CommandBarPanel.swift` for the reason `URLPillLayout.swift`
//  was split out of `URLPillView.swift`: that file crosses SwiftLint's 400-line
//  limit otherwise. Nothing changed on the way across.
//
//  The bar has two placements and one of each here. Floating (`⌘T`), it is
//  `CommandBarMetrics.width` wide and 20 % down the **page**. Anchored, it has
//  grown out of an address pill and takes that pill's line, a little more than
//  its width, and the room under it — see `CommandBarAnchor`.
//
//  The constraints and the two flags this reaches are `internal` rather than
//  `private` so this file can set them. They are still the panel's, and nothing
//  outside these two files touches any of them.
//

import AppKit

extension CommandBarPanel {

    /// The corner the panel is cut at: a card's when it floats, and the pill's
    /// own when it grew out of one. Fixed at construction, which is all a glass
    /// backing allows — and all this needs, because a pill's height is the one
    /// thing about it that does not change while the bar is standing in it.
    var bodyRadius: CGFloat {
        anchor == nil ? CommandBarMetrics.cornerRadius : Tokens.Metric.urlPill.cornerRadius
    }

    /// **Wider than the pill, on purpose.** A bar exactly as wide as the thing
    /// it grew from is the most literal morph and the least useful list: a
    /// sidebar's pill is 234–264 pt and a result row spends about 140 of that
    /// on its icon, its insets and §21.2's Profile badge, so every title read
    /// `OpenAI | Rese…`. It takes a `chromeGapWide` at each end — the gap the
    /// chrome uses between clusters — and never less than
    /// `commandBarMinWidth`, which is measured off the row.
    private func anchoredWidth(for rect: NSRect) -> CGFloat {
        max(rect.width + 2 * Tokens.Metric.chromeGapWide, Tokens.Metric.commandBarMinWidth)
    }

    /// **The pill's centre line, kept unless the window's edge is closer.** The
    /// page bar's capsule is centred over the page and its bar should be too;
    /// the sidebar's is 140 pt from the window's leading edge, where a 360 pt
    /// bar centred on it would hang 40 pt off the screen. Clamped, that column
    /// case lands leading-aligned with the pill, which is where a bar growing
    /// out of the first thing in a column belongs anyway.
    private func anchoredCentre(for rect: NSRect, width: CGFloat) -> CGFloat {
        let margin = Tokens.Metric.chromeGap
        let leading = bounds.minX + margin
        let trailing = max(bounds.maxX - margin - width, leading)
        return min(max(rect.midX - width / 2, leading), trailing) + width / 2
    }

    /// A constant, written only when it is actually different.
    ///
    /// This runs on **every** layout pass, and while the bar is opening there
    /// is one of those per frame — so five unconditional writes to five
    /// constraints is five invalidations of a layout that was about to be
    /// correct anyway, per frame, for numbers that have not moved.
    private func set(_ constraint: NSLayoutConstraint?, to value: CGFloat) {
        guard let constraint, constraint.constant != value else { return }
        constraint.constant = value
    }

    /// The pill's place, in this view's coordinates — or nil when the bar is
    /// floating, and when the pill has left the window under it.
    private var anchorRect: NSRect? {
        guard let view = anchor?.view, view.window === window, window != nil else { return nil }
        return convert(view.bounds, from: view)
    }

    /// UI-SPEC §6 anchors the panel to a *fraction* of the surface it is over,
    /// so a constant set once is wrong the moment the window is resized — or
    /// the sidebar dragged — under an open bar. Both constants are re-derived
    /// here, against the page rather than the window.
    ///
    /// **Derived before `super.layout()`, never after.** The constraint pass
    /// that actually places `body` runs *inside* `super.layout()`, and AppKit
    /// marks this view clean the moment `layout()` returns — so a constant set
    /// on the way out is handed to a view the framework has just stopped
    /// asking about. It does not reach the screen on this pass and it does not
    /// schedule another one; the bar stays where the stale constants put it
    /// until something *else* dirties the panel, which on `⌘T` is whenever the
    /// history query lands or the first key is pressed.
    ///
    /// Both constants start at zero, and zero is not a harmless place: it is
    /// the window's top edge, centred on the window rather than on the page.
    /// Measured in a 1200×800 window with the sidebar out, the first pass left
    /// the bar at `(280, 740)` and the second put it at `(392, 551)` — **112 pt
    /// to the left and 189 pt too high**, held for as long as nothing asked for
    /// another pass. That is the bar Martin saw flash up and to the left.
    override func layout() {
        // **Anchored, there is no fraction to derive: the pill says where.**
        // Its rect is re-read on every pass for the same reason the floating
        // bar re-derives its two constants — the window resizes and the sidebar
        // is dragged while the bar is open, and the pill moves with both.
        if let rect = anchorRect {
            let width = anchoredWidth(for: rect)
            set(topAnchorConstraint, to: bounds.maxY - rect.maxY - inputPadding)
            set(centreConstraint, to: anchoredCentre(for: rect, width: width) - bounds.midX)
            set(widthConstraint, to: width)
            set(fieldCentreConstraint, to: inputHeight / 2)
            set(resultsTopConstraint, to: inputHeight)
            super.layout()
            return
        }
        // An empty region means nobody told us where the page is; the window
        // is the honest fallback, not a zero-sized rect at the origin.
        let reported = contentRegion?() ?? bounds
        let region = reported.isEmpty ? bounds : reported
        // Auto Layout measures a top constant downwards; `region` is in this
        // view's own bottom-left coordinates.
        topAnchorConstraint?.constant =
            (bounds.maxY - region.maxY) + region.height * CommandBarMetrics.topAnchorFraction
        centreConstraint?.constant = region.midX - bounds.midX
        super.layout()
    }

    /// §6 `commandBarIn`: 0.18 s spring, scale 0.96 → 1.0 + fade.
    ///
    /// Reduce Motion degrades it to instant with no second code path:
    /// `springAnimation` returns nil, and `Motion.animate` runs at zero
    /// duration.
    func animateIn() {
        beginOpening()
        layoutSubtreeIfNeeded()
        // **The body fades, not the panel.** This view is the whole window, and
        // an `alphaValue` on it puts every pixel of it — including the page
        // showing through — into a transparency layer for the length of the
        // animation. The body is the only thing on this view that draws.
        alphaValue = 1
        body.alphaValue = 0
        guard anchorRect == nil else { return revealFromPill() }
        guard let scale = Tokens.Motion.commandBarIn.springAnimation(keyPath: "transform.scale") else {
            body.alphaValue = 1
            finishOpening()
            return
        }
        scale.fromValue = 0.96
        scale.toValue = 1.0
        body.layer?.add(scale, forKey: "commandBarIn")
        Tokens.Motion.animate(Tokens.Motion.commandBarIn) { _ in
            self.body.animator().alphaValue = 1
        } completion: { [weak self] in
            MainActor.assumeIsolated { self?.finishOpening() }
        }
    }

    /// The same 0.18 s, spent on **more glass rather than a new pane**.
    ///
    /// The floating bar scales up from 0.96 because it is arriving: there was
    /// nothing there a moment ago. This one is not arriving — the pill it is
    /// standing in was already on screen, at that corner and on that line — so
    /// a scale would shrink and re-grow the thing the user just clicked. What
    /// opens instead is the glass itself, from the pill's height down to the
    /// bar's, with the rows already in place behind it.
    ///
    /// **Height only, and only the height.** The one thing that grows is the
    /// glass: the input row is already where the pill's text was, and the extra
    /// width the list needs is there on the first frame, under an alpha that
    /// starts at zero. Animating the width as well meant a second property
    /// re-laying the panel out every frame for a change nobody can see through
    /// the fade, and the first version did it by masking the body — which puts
    /// an offscreen pass around a live glass panel over a live web page.
    ///
    /// **And the glass is what has to grow, not a clip over it.** Cutting the
    /// body's layer down and animating the cut instead — a rounded
    /// `masksToBounds` on the presentation layer, which would have cost no
    /// layout at all — does not work over `NSGlassEffectView`: the material is
    /// composited outside the layer that is supposed to be clipping it, so the
    /// bar opened as eight rows of text floating over the sidebar with no
    /// panel behind them. Measured, on screen, and thrown away.
    ///
    /// **One frame of nothing first.** The panel, its glass and its eight rows
    /// are all built in the runloop turn that opens the bar, and the window
    /// server has a fresh glass backdrop to set up over a live web page on the
    /// first composite. Starting the spring in that same turn spends its first
    /// frames competing with that work, which is the part Martin could feel.
    /// The panel is laid out and left invisible instead, and the animation
    /// starts on the next turn — by which time the expensive frame has already
    /// been drawn.
    private func revealFromPill() {
        let target = body.frame.height
        let height = body.heightAnchor.constraint(equalToConstant: inputHeight)
        revealConstraint = height
        height.isActive = true
        layoutSubtreeIfNeeded()
        DispatchQueue.main.async { [weak self] in
            guard let self, revealConstraint === height else { return self?.finishOpening() ?? () }
            Tokens.Motion.animate(Tokens.Motion.commandBarIn) { context in
                context.allowsImplicitAnimation = true
                height.animator().constant = target
                self.body.animator().alphaValue = 1
            } completion: { [weak self] in
                MainActor.assumeIsolated {
                    // Off, not left at the target. **The list goes on changing
                    // size after the bar has opened** — the history query
                    // lands, then the engine's suggestions, and each re-ranks
                    // the rows — and a required height frozen at what the first
                    // pass asked for would clip everything that arrived after
                    // it. That is what a fullscreen page bar showed: an input
                    // row with an empty band under it, and the rows cut off
                    // below the glass.
                    self?.revealConstraint?.isActive = false
                    self?.revealConstraint = nil
                    self?.finishOpening()
                }
            }
        }
    }
}
