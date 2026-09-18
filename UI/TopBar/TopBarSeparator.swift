//
//  TopBarSeparator.swift
//  Luna
//
//  §4's vertical hairline, dividing the tab strip from the action capsule.
//
//  Its own file only because `TopBarView` reached SwiftLint's 400-line limit
//  when History joined the capsule; it was already a separate class.
//

import AppKit

/// §4's vertical hairline, dividing the tab strip from the action capsule.
@MainActor
final class TopBarSeparator: NSView, TopBarThemed {

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(
            width: Tokens.Metric.hairline,
            height: Tokens.Metric.topBarHeight - TopBarMetrics.clusterGap * 2
        )
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = Tokens.Line.hairline.cgColor
    }

    func applyTokens() { needsDisplay = true }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}
