//
//  WindowRootView.swift
//  Luna
//
//  A Luna window's shape, and nothing else. Split out of
//  `BrowserWindowController` to keep that file under SwiftLint's length limit —
//  it started as that window's root view and is now every window's, Settings
//  included: one app has one corner radius, and a second window wearing the
//  system's instead is the kind of difference you see without being able to
//  name it.
//

import AppKit

/// The window's shape: a rounded, clipping plane that everything else lives
/// inside (§1 `windowCornerRadius`, §30.1). 25 pt, measured off the reference's
/// own macOS 26 window — and the radius the content pane matches, so the two
/// sets of corners nest.
///
/// It only shows on a window that is `isOpaque = false` with a clear
/// background: the system's own mask is rounder than this, so what makes the
/// corner Luna's is the content stopping short of it.
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
