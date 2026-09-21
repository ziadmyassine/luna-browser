//
//  CommandBarPanelLayout.swift
//  Luna
//
//  Where §9.1's bar stands, how big it is, and how it opens.
//
//  Split out of `CommandBarPanel.swift` for that file's length limit.
//
//  The bar has two placements and one of each here. Floating (`⌘T`), it is
//  `CommandBarMetrics.width` wide and 20 % down the page. Anchored, it has
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

    /// Wider than the pill, on purpose. A bar exactly as wide as the thing
    /// it grew from is the most literal morph and the least useful list: a
    /// sidebar's pill is 234–264 pt and a result row spends about 140 of that
    /// on its icon, its insets and §21.2's Profile badge, so every title read
    /// `OpenAI | Rese…`. It takes a `chromeGapWide` at each end — the gap the
    /// chrome uses between clusters — and never less than
    /// `commandBarMinWidth`, which is measured off the row.
    private func anchoredWidth(for rect: NSRect) -> CGFloat {
        max(rect.width + 2 * Tokens.Metric.chromeGapWide, Tokens.Metric.commandBarMinWidth)
    }

    /// The pill's centre line, kept unless the window's edge is closer. The
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
    /// This runs on every layout pass, and while the bar is opening there
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

    /// UI-SPEC §6 anchors the panel to a fraction of the surface it is over,
    /// so a constant set once is wrong the moment the window is resized — or
    /// the sidebar dragged — under an open bar. Both constants are re-derived
    /// here, against the page rather than the window.
    ///
    /// Derived before `super.layout()`, never after. The constraint pass that
    /// places `body` runs inside `super.layout()`, and AppKit marks this view
    /// clean the moment `layout()` returns — so a constant set on the way out
    /// reaches nothing this pass and schedules no other, leaving the bar where
    /// the stale constants put it until something else dirties the panel.
    ///
    /// Both constants start at zero, and zero is not a harmless place: it is
    /// the window's top edge, centred on the window rather than on the page.
    /// Measured in a 1200×800 window with the sidebar out, the first pass left
    /// the bar at `(280, 740)` and the second put it at `(392, 551)` — 112 pt
    /// to the left and 189 pt too high, held for as long as nothing asked for
    /// another pass. That is the bar that flashed up and to the left.
    override func layout() {
        // Anchored, there is no fraction to derive: the pill says where.
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

    /// Everything the bar needs in place before it opens: added, laid out,
    /// and drawn at the pill's own size, so that what the first composite
    /// puts on screen is the capsule the user just clicked, in its place, with
    /// their caret in it.
    ///
    /// The first frame of a Command Bar is expensive in a way tuning does not
    /// fix — a fresh `NSGlassEffectView` over a live web page, eight rows of
    /// text, and a field taking the window's first responder. Measured from the
    /// click to the commit that draws it: 65 ms, of which 20 is the commit and
    /// 15 is `makeFirstResponder`. Four dropped frames, landing wherever this
    /// is called.
    ///
    /// So they land before the animation rather than inside it, and they land
    /// on a bar the size of a pill rather than on one the size of the list:
    /// the glass the window server sets up here is the glass the reveal then
    /// grows, so the reveal's own first frame has nothing left to build. The
    /// bar that stalled in the middle was doing that work on frame one,
    /// at full size, with an alpha ramp over the top of it.
    ///
    /// The floating bar keeps its fade, because it really is arriving out of
    /// nothing — there is no pill under it to be the first frame.
    func prepareToOpen() {
        alphaValue = 1
        guard anchorRect != nil else {
            body.alphaValue = 0
            layoutSubtreeIfNeeded()
            return
        }
        body.alphaValue = 1
        layoutSubtreeIfNeeded()
        let height = body.heightAnchor.constraint(equalToConstant: inputHeight)
        revealConstraint = height
        height.isActive = true
        layoutSubtreeIfNeeded()
    }

    /// §6 `commandBarIn`: 0.18 s spring, scale 0.96 → 1.0 + fade.
    ///
    /// Reduce Motion degrades it to instant with no second code path:
    /// `springAnimation` returns nil, and `Motion.animate` runs at zero
    /// duration.
    func animateIn() {
        beginOpening()
        if let height = revealConstraint { return revealFromPill(height) }
        layoutSubtreeIfNeeded()
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

    /// The same 0.18 s, spent on more glass rather than a new pane.
    ///
    /// The floating bar scales up from 0.96 because it is arriving: there was
    /// nothing there a moment ago. This one is not arriving — the pill it is
    /// standing in was already on screen, at that corner and on that line — so
    /// a scale would shrink and re-grow the thing the user just clicked. What
    /// opens instead is the glass itself, from the pill's height down to the
    /// bar's, with the rows already in place behind it.
    ///
    /// Height only. Not the width — the room the list needs is there on the
    /// first frame, and animating it meant a second property re-laying the
    /// panel out every frame for a change nobody can see. Not the alpha either:
    /// the bar is already on screen at the pill's size when this runs
    /// (`prepareToOpen`), so a fade would be the capsule the user is looking at
    /// dimming and coming back.
    ///
    /// The glass has to grow, not a clip over it. Cutting the body's layer down
    /// and animating the cut — a rounded `masksToBounds` on the presentation
    /// layer, costing no layout at all — does not work over
    /// `NSGlassEffectView`: the material composites outside the layer meant to
    /// clip it, so the bar opened as eight rows of text floating over the
    /// sidebar with no panel behind them.
    ///
    /// - Parameter height: the constraint holding the bar at the pill's height,
    ///   installed by `prepareToOpen`. It is let go of at the end, because
    ///   the list goes on changing size after the bar has opened — the
    ///   engine's suggestions land, and every keystroke re-ranks the rows — and
    ///   a required height frozen at what the opening pass asked for would clip
    ///   everything that arrived after it. That is what a fullscreen page bar
    ///   showed: an input row with an empty band under it, and the rows cut off
    ///   below the glass.
    private func revealFromPill(_ height: NSLayoutConstraint) {
        // Asked of the list, not of the body. The target has to be read
        // now rather than when the bar was prepared — the store's answer has
        // landed since, and that is what the bar was waiting for — but taking
        // it off `body.frame` means letting the height constraint go, laying
        // out, and putting it back, which resizes the glass twice for a number
        // nobody sees. Measured, that round trip cost 26 ms on the frame the
        // animation was about to start on. The list can simply be asked how
        // tall it wants to be, which is the same arithmetic the two constraints
        // below `results` do: the input row, the rows, and the panel's own
        // bottom margin.
        let target = inputHeight + results.fittingSize.height + CommandBarMetrics.padding
        Tokens.Motion.animate(Tokens.Motion.commandBarIn) { context in
            context.allowsImplicitAnimation = true
            height.animator().constant = target
        } completion: { [weak self] in
            MainActor.assumeIsolated {
                self?.revealConstraint?.isActive = false
                self?.revealConstraint = nil
                self?.finishOpening()
            }
        }
    }

    // MARK: - Closing

    /// `animateIn` run backwards, and one of each again: the floating bar
    /// shrinks and fades the way it grew, and the anchored one closes back
    /// down onto its pill.
    ///
    /// It used to be `removeFromSuperview()`, which is a bar that is there and
    /// then is not. On the floating panel that reads as a window being shut
    /// rather than a summoned thing going away; on the anchored one it is
    /// worse, because the whole of what that bar is saying is "I am the pill
    /// you clicked, opened up" — and a bar that vanishes to reveal the pill
    /// underneath was never the pill at all. Whatever the way in argued, the
    /// way out has to argue the same thing or it withdraws it.
    ///
    /// Takes the panel out of the window itself and calls `onClosed`, so a
    /// caller has nothing to remember. Reduce Motion needs no branch here
    /// either: `springAnimation` gives back nil and `Motion.animate` runs at
    /// zero duration, so both paths end on the next turn of the run loop.
    func animateOut() {
        beginClosing()
        // Anchored, and open: the glass has somewhere to go back to.
        if anchor != nil { return collapseToPill() }
        guard let scale = Tokens.Motion.commandBarIn.springAnimation(keyPath: "transform.scale") else {
            return finishClosing()
        }
        scale.fromValue = 1.0
        scale.toValue = 0.96
        // Held, because the layer is about to leave: a scale that snapped back
        // to full size for the last frame of the fade is a flicker at the one
        // moment nothing should move.
        scale.fillMode = .forwards
        scale.isRemovedOnCompletion = false
        body.layer?.add(scale, forKey: "commandBarOut")
        Tokens.Motion.animate(Tokens.Motion.commandBarIn) { _ in
            self.body.animator().alphaValue = 0
        } completion: { [weak self] in
            MainActor.assumeIsolated { self?.finishClosing() }
        }
    }

    /// `revealFromPill` in reverse: the same height constraint, the same
    /// 0.18 s, ending where the reveal started.
    ///
    /// Height only, and for the same reasons — the width and the place are the
    /// pill's own and were never animated, and a fade would be the capsule the
    /// user is looking at dimming on its way to being itself again. The list
    /// is clipped rather than scaled, which is what `masksToBounds` on an
    /// anchored body is for (`activateBodyConstraints`): the rows go under the
    /// closing edge instead of shrinking with it.
    private func collapseToPill() {
        // Whatever height it has *now*, which is not the same as the height it
        // was heading for: `esc` pressed halfway through the reveal has to
        // close from where the glass got to, not jump to full size first.
        let current = revealConstraint?.constant ?? body.frame.height
        // A bar that never opened has nothing to close. It stands at the
        // pill's own height until `openWhenReady` lets it go, and folding that
        // is 0.18 s of nothing between the press and the pill coming back.
        guard current > inputHeight else { return finishClosing() }
        let height = revealConstraint ?? body.heightAnchor.constraint(equalToConstant: current)
        revealConstraint = height
        height.constant = current
        height.isActive = true
        layoutSubtreeIfNeeded()
        Tokens.Motion.animate(Tokens.Motion.commandBarIn) { context in
            context.allowsImplicitAnimation = true
            height.animator().constant = inputHeight
        } completion: { [weak self] in
            MainActor.assumeIsolated { self?.finishClosing() }
        }
    }

    /// Off screen, out of the tree, and the pill is its own again.
    private func finishClosing() {
        revealConstraint?.isActive = false
        revealConstraint = nil
        removeFromSuperview()
        onClosed?()
        onClosed = nil
    }
}
