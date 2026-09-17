//
//  WindowRootView.swift
//  Luna
//
//  The browser window's shape, and nothing else. Split out of
//  `BrowserWindowController` to keep that file under SwiftLint's length limit —
//  it is the window controller's root view and belongs to it.
//

import AppKit

/// The window's shape: a rounded, clipping plane that everything else lives
/// inside (§1 `windowCornerRadius`, §30.1). 25 pt, measured off the reference's
/// own macOS 26 window — and the radius the content pane matches, so the two
/// sets of corners nest.
final class WindowRootView: NSView {

    var isWindowFullScreen = false {
        didSet {
            guard isWindowFullScreen != oldValue else { return }
            updateCornerRadius()
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        updateCornerRadius()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its views in code")
    }

    private func updateCornerRadius() {
        layer?.cornerRadius = isWindowFullScreen ? 0 : Tokens.Metric.windowCornerRadius
    }
}
