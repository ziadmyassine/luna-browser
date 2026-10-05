//
//  AgentEdgeBlur.swift
//  Luna
//
//  The conversation's two edges, where it scrolls under the task's pill and
//  the field: rather than a line it is cut at, the words blur more and more
//  and fade out as they go, a progressive blur. Two parts: a mask on the
//  scroll view that takes the words' alpha down to nothing at the edge, and
//  over each edge a band whose background is blurred, its own mask fading
//  the blur in toward the edge.
//
//  The blur is a fixed radius over a band a few dozen points tall, redrawn
//  only when what is under it moves — not the full-viewport Core Image pass
//  per frame `ReloadBloomArc` warns of.
//

import AppKit
import CoreImage

@MainActor
final class AgentEdgeBlur: NSView {

    enum Edge { case top, bottom }

    /// How far in from each edge the fade and the blur reach.
    static let depth: CGFloat = 28
    private static let radius: CGFloat = 5

    private let edge: Edge
    private let ramp = CAGradientLayer()

    init(edge: Edge) {
        self.edge = edge
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layerUsesCoreImageFilters = true
        if let blur = CIFilter(name: "CIGaussianBlur") {
            blur.setValue(Self.radius, forKey: kCIInputRadiusKey)
            backgroundFilters = [blur]
        }
        // Opaque at the edge, clear inward: the blur is strongest where the
        // words leave. Layer space is y up.
        ramp.colors = [NSColor.black.cgColor, NSColor.clear.cgColor]
        ramp.startPoint = CGPoint(x: 0.5, y: edge == .top ? 1 : 0)
        ramp.endPoint = CGPoint(x: 0.5, y: edge == .top ? 0 : 1)
        layer?.mask = ramp
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        Tokens.Motion.immediately { ramp.frame = bounds }
    }

    /// The alpha half: a mask for the scroll view that fades the words to
    /// nothing over `depth` at both ends.
    static func fadeMask(for bounds: CGRect) -> CAGradientLayer {
        let mask = CAGradientLayer()
        mask.frame = bounds
        let edge = bounds.height > 0 ? min(depth / bounds.height, 0.25) : 0
        mask.colors = [NSColor.clear.cgColor, NSColor.black.cgColor, NSColor.black.cgColor, NSColor.clear.cgColor]
        mask.locations = [0, NSNumber(value: Double(edge)), NSNumber(value: Double(1 - edge)), 1]
        return mask
    }
}
