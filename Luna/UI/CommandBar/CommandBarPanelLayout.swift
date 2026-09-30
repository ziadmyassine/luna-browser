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
        let span = anchorSpan ?? bounds.insetBy(dx: margin, dy: 0)
        let leading = max(bounds.minX + margin, span.minX)
        let trailing = max(min(bounds.maxX - margin, span.maxX) - width, leading)
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

    /// How far an anchored bar's glass rises above its anchor: the margin
    /// below it, unless the window's top edge is nearer than that. The field
    /// stays on the anchor's centre line either way; what gives is the air
    /// above it.
    var inputRise: CGFloat {
        guard let rect = anchorRect else { return inputPadding }
        let room = bounds.maxY - rect.maxY - CommandBarMetrics.edgeClearance
        return min(inputPadding, max(room, 0))
    }

    /// `CommandBarAnchor.span`, in this view's coordinates.
    private var anchorSpan: NSRect? {
        guard let view = anchor?.span, view.window === window, window != nil else { return nil }
        return convert(view.bounds, from: view)
    }

    /// UI-SPEC §6 anchors the panel to a fraction of the surface it is over,
    /// and the window resizes and the sidebar is dragged under an open bar, so
    /// both constants are re-derived on every pass, against the page rather
    /// than the window.
    ///
    /// Derived before `super.layout()`, never after. AppKit marks this view
    /// clean the moment `layout()` returns, so a constant set on the way out
    /// reaches nothing this pass and schedules no other. Both start at zero,
    /// which is the window's top edge centred on the window: in a 1200×800
    /// window that held the bar 112 pt to the left and 189 pt too high until
    /// something else dirtied the panel.
    override func layout() {
        // Anchored, there is no fraction to derive: the pill says where, and
        // its rect is re-read every pass because the pill moves too. `morph`
        // runs each constant from the anchor's value to the bar's, with the
        // field held on the anchor's centre line: the top rises by `inputRise`
        // as the field's offset from it grows by the same.
        if let rect = anchorRect {
            let width = anchoredWidth(for: rect)
            let open = morph
            func toward(_ closed: CGFloat, _ opened: CGFloat) -> CGFloat { closed + (opened - closed) * open }
            let rise = inputRise
            // Closed is where the anchor was pressed, while it is still moving
            // to where it opens from — see `CommandBarAnchor.startFrame`.
            let from = openingFrom ?? rect
            set(topAnchorConstraint, to: toward(bounds.maxY - from.maxY, bounds.maxY - rect.maxY - rise))
            set(centreConstraint, to: toward(from.midX, anchoredCentre(for: rect, width: width)) - bounds.midX)
            set(widthConstraint, to: toward(from.width, width))
            set(fieldCentreConstraint, to: toward(from.height / 2, rise + rect.height / 2))
            set(resultsTopConstraint, to: inputHeight)
            bodyGlass?.cornerRadius = toward(min(anchor?.cornerRadius ?? bodyRadius, from.height / 2), bodyRadius)
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
    /// and drawn at the pill's own size, so the first composite is the capsule
    /// the user just clicked, in its place, with their caret in it.
    ///
    /// The first frame is expensive in a way tuning does not fix: a fresh
    /// `NSGlassEffectView` over a live page, eight rows of text, and a field
    /// taking first responder. Measured from click to commit, 65 ms — 20 of it
    /// the commit, 15 `makeFirstResponder` — which is four dropped frames. They
    /// land here, before the animation and on a pill-sized bar, so the glass
    /// the reveal grows is already built. Done on the reveal's first frame, at
    /// full size under an alpha ramp, the bar stalled halfway open.
    ///
    /// The floating bar keeps its fade: there is no pill under it to be the
    /// first frame.
    func prepareToOpen() {
        alphaValue = 1
        guard anchorRect != nil else {
            body.alphaValue = 0
            layoutSubtreeIfNeeded()
            return
        }
        body.alphaValue = 1
        morph = 0
        layoutSubtreeIfNeeded()
        let height = body.heightAnchor.constraint(equalToConstant: anchorHeight)
        revealConstraint = height
        height.isActive = true
        layoutSubtreeIfNeeded()
    }

    /// The anchor's own height, which is where the bar starts and ends — or
    /// the height it was pressed at, while it is on its way to this one.
    var anchorHeight: CGFloat {
        openingFrom?.height ?? anchor?.view.bounds.height ?? inputHeight
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

    /// `commandBarMorph`, spent on more glass rather than a new pane: the glass
    /// grows from the pill's frame and corner to the bar's, with the rows
    /// already behind it. No scale and no fade — the pill was already on
    /// screen and the bar is standing in it (`prepareToOpen`), so either would
    /// shrink or dim the thing the user just clicked.
    ///
    /// Width, place and corner move with the height (`morph`); height alone was
    /// a jump on §4's tab, which is a third of the bar's width. The glass itself
    /// has to grow: a rounded `masksToBounds` clip does not hold
    /// `NSGlassEffectView`, and the rows opened with no panel behind them.
    ///
    /// - Parameter height: the constraint holding the bar at the pill's height,
    ///   from `prepareToOpen`. Let go of at the end, because the list keeps
    ///   changing size as suggestions land and keystrokes re-rank; held, it
    ///   clipped a fullscreen page bar's rows below the glass.
    private func revealFromPill(_ height: NSLayoutConstraint) {
        // Asked of the list rather than read off `body.frame`, which means
        // letting the height constraint go, laying out and putting it back —
        // 26 ms on the animation's first frame. Read here rather than in
        // `prepareToOpen`, because the store's answer has landed since. The
        // sum is the one the constraints below `results` make.
        let target = inputHeight + results.fittingSize.height + CommandBarMetrics.padding
        Tokens.Motion.animate(Tokens.Motion.commandBarMorph) { context in
            context.allowsImplicitAnimation = true
            height.animator().constant = target
            animator().morph = 1
        } completion: { [weak self] in
            MainActor.assumeIsolated {
                self?.revealConstraint?.isActive = false
                self?.revealConstraint = nil
                self?.finishOpening()
            }
        }
    }

    // MARK: - Closing

    /// `animateIn` run backwards: the floating bar shrinks and fades the way it
    /// grew, and the anchored one closes back down onto its pill. Not a bare
    /// `removeFromSuperview()` — a bar that vanishes to reveal the pill under
    /// it was never the pill at all, which withdraws what the way in said.
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

    /// `revealFromPill` in reverse: the same height constraint and `morph`, on
    /// the same spec, ending in the anchor's own frame and corner.
    ///
    /// No fade, for the reveal's reason: it would be the capsule the user is
    /// looking at dimming on its way to being itself again. The list
    /// is clipped rather than scaled, which is what `masksToBounds` on an
    /// anchored body is for (`activateBodyConstraints`): the rows go under the
    /// closing edge instead of shrinking with it.
    private func collapseToPill() {
        // The height it has now, which is not the height it was heading for: `esc` pressed halfway through the reveal has to
        // close from where the glass got to, not jump to full size first.
        let current = revealConstraint?.constant ?? body.frame.height
        // A bar that never opened has nothing to close. It stands in the
        // anchor's own frame until `openWhenReady` lets it go, and folding that
        // is a fold of nothing between the press and the pill coming back.
        guard current > anchorHeight else { return finishClosing() }
        let height = revealConstraint ?? body.heightAnchor.constraint(equalToConstant: current)
        revealConstraint = height
        height.constant = current
        height.isActive = true
        layoutSubtreeIfNeeded()
        Tokens.Motion.animate(Tokens.Motion.commandBarMorph) { context in
            context.allowsImplicitAnimation = true
            height.animator().constant = anchorHeight
            animator().morph = 0
        } completion: { [weak self] in
            MainActor.assumeIsolated { self?.finishClosing() }
        }
    }

    /// Out of the tree on this line, with `onClosed` — for a close nobody
    /// should have to watch (`CommandBarController.dismiss`).
    func closeAtOnce() {
        beginClosing()
        onOpened = nil
        body.layer?.removeAllAnimations()
        finishClosing()
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
