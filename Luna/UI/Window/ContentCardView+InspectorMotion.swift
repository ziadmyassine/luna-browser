//
//  ContentCardView+InspectorMotion.swift
//  Luna
//
//  A docked Web Inspector arriving and leaving. WebKit moves both frames in
//  one step either way, so the motion is laid over what it does: the
//  inspector fades in once it is styled, fades out before it closes, and the
//  page takes its place back the way a hidden sidebar's place is taken — laid
//  out at its new size at once, its edge sliding out to meet it. The timings
//  are the sidebar's.
//

import AppKit
import BrowserKit
import WebKit

extension ContentCardView {

    /// Shows an inspector that has been held back until it wears the
    /// stylesheet.
    static func fadeIn(_ inspector: WKWebView?) {
        guard let inspector else { return }
        Tokens.Motion.animate(Tokens.Motion.sidebarCollapse) { _ in
            inspector.animator().alphaValue = 1
        }
    }

    /// Luna's own way to close an inspector, ⌥⌘I and the Develop menu. One
    /// docked in a card fades first, as its own close button does
    /// (`InspectorStyle.script`); one in a window of its own, or under Reduce
    /// Motion, closes at once.
    static func closeInspector(of webView: WKWebView?) {
        var card = webView?.superview
        while let view = card, !(view is ContentCardView) { card = view.superview }
        guard let inspector = (card as? ContentCardView)?.dockedInspector, !Tokens.Motion.reduceMotion else {
            return WebInspector.close(for: webView)
        }
        Tokens.Motion.animate(Tokens.Motion.sidebarCollapseOpacity) { _ in
            inspector.animator().alphaValue = 0
        } completion: { [weak webView] in
            MainActor.assumeIsolated { WebInspector.close(for: webView) }
        }
    }

    /// The page taking back a closed inspector's place, from `page`, where it
    /// stood, with `corners` rounded.
    ///
    /// Grown a frame at a time, the page would re-flow every frame. So it
    /// takes its whole size now, re-flowing once, and a mask on it — and on
    /// the bar and Luna Control's layer over it — grows from where it stood
    /// to the whole card, its corners squaring as it goes. The card stays
    /// clear behind it until the mask has finished.
    func revealPage(from page: NSRect, corners: CACornerMask) {
        let card = bounds
        guard !page.isEmpty, abs(page.width - card.width) + abs(page.height - card.height) > 0.5 else { return }
        Tokens.Motion.immediately { layoutSubtreeIfNeeded() }
        let spec = Tokens.Motion.sidebarCollapse
        var masks: [CALayer] = []
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for view in pageViews {
            view.wantsLayer = true
            guard let layer = view.layer else { continue }
            let mask = CALayer()
            mask.backgroundColor = NSColor.black.cgColor
            mask.cornerCurve = .continuous
            mask.maskedCorners = Self.layerCorners(corners, of: view)
            mask.frame = view.bounds
            layer.mask = mask
            let from = view.convert(page, from: self)
            let start = NSValue(rect: NSRect(origin: .zero, size: from.size))
            mask.add(Self.tween("bounds", from: start, to: NSValue(rect: mask.bounds), on: spec), forKey: "bounds")
            let centre = NSValue(point: NSPoint(x: from.midX, y: from.midY))
            mask.add(Self.tween("position", from: centre, to: NSValue(point: mask.position), on: spec), forKey: "position")
            mask.add(Self.tween("cornerRadius", from: WindowCorner.radius, to: 0, on: spec), forKey: "cornerRadius")
            masks.append(mask)
        }
        CATransaction.setCompletionBlock { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.revealMasks.first === masks.first else { return }
                self.endPageReveal()
            }
        }
        CATransaction.commit()
        revealMasks = masks
    }

    /// Takes the reveal's masks off at its end, or at once when an inspector
    /// docks again before it has finished — changing sides is a removal and
    /// an addition in one turn.
    func endPageReveal() {
        guard !revealMasks.isEmpty else { return }
        for view in pageViews where revealMasks.contains(where: { $0 === view.layer?.mask }) {
            view.layer?.mask = nil
        }
        revealMasks = []
    }

    private static func tween(_ keyPath: String, from: Any, to: Any, on spec: MotionSpec) -> CABasicAnimation {
        let tween = CABasicAnimation(keyPath: keyPath)
        tween.fromValue = from
        tween.toValue = to
        tween.duration = spec.duration
        tween.timingFunction = spec.timingFunction
        return tween
    }
}
