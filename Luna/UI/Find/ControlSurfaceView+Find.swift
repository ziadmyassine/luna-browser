//
//  ControlSurfaceView+Find.swift
//  Luna
//
//  Where §18.1's find field stands on the layer over the page: a gap under
//  the bar in the top trailing corner, under §3.2b's extensions cylinder when
//  the page bar is up. It drops in and goes back up the way a toast does.
//

import AppKit

extension ControlSurfaceView {

    func showFindBar(_ view: FindBarView) {
        guard findBar !== view else { return }
        findBar?.removeFromSuperview()
        view.alphaValue = 0
        addSubview(view)
        let top = view.topAnchor.constraint(equalTo: topAnchor, constant: findBarTopConstant(shown: false))
        NSLayoutConstraint.activate([
            view.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Tokens.Metric.pageBarInset),
            view.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: Tokens.Metric.pageBarInset),
            top
        ])
        findBar = view
        findBarTop = top
        // Placed where it starts before anything moves, or it would fly in
        // from the layer's corner.
        Tokens.Motion.immediately { layoutSubtreeIfNeeded() }
        let shown = findBarTopConstant(shown: true)
        Tokens.Motion.animate(Tokens.Motion.agentSheet) { _ in
            top.animator().constant = shown
            view.animator().alphaValue = 1
        }
    }

    func hideFindBar() {
        guard let view = findBar, let top = findBarTop else { return }
        findBar = nil
        findBarTop = nil
        let hidden = findBarTopConstant(shown: false)
        Tokens.Motion.animate(Tokens.Motion.agentSheet) { _ in
            top.animator().constant = hidden
            view.animator().alphaValue = 0
        } completion: {
            MainActor.assumeIsolated { view.removeFromSuperview() }
        }
    }

    /// Shown, a gap under the bar; hidden, wholly under it.
    func findBarTopConstant(shown: Bool) -> CGFloat {
        shown ? topInset + Tokens.Metric.chromeGap : topInset - Tokens.Metric.capsuleHeight
    }

    /// Whether a toast `width` wide, centred, would land on the find field. A
    /// toast that would then drops under the field instead of over it.
    func toastMeetsFindBar(width: CGFloat) -> Bool {
        guard findBar != nil else { return false }
        let fieldLeading = bounds.width - Tokens.Metric.pageBarInset - Tokens.Metric.findBarWidth
        return bounds.midX + width / 2 + Tokens.Metric.chromeGap > fieldLeading
    }
}
