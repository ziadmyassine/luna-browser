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

/// The window's corner as the Appearance setting has it: the reference's by
/// default, the one macOS gives its own windows when `Settings.macWindowCorners`
/// is on (`Design/Metrics.swift` has both measurements).
///
/// The content pane's corners are this too. The pane is flush against three of
/// the window's edges, so any other radius leaves a crescent of glass showing
/// inside each window corner.
@MainActor
enum WindowCorner {
    static var radius: CGFloat {
        Settings.macWindowCorners ? Tokens.Metric.windowCornerRadiusSystem : Tokens.Metric.windowCornerRadius
    }
}

/// The window's shape: a rounded, clipping plane that everything else lives
/// inside (§1 `windowCornerRadius`, §30.1).
///
/// It only shows on a window that is `isOpaque = false` with a clear
/// background: at Luna's own radius, what makes the corner Luna's is the
/// content stopping short of the system's mask. At the macOS radius it lies on
/// that mask.
final class WindowRootView: NSView {

    var isWindowFullScreen = false {
        didSet {
            guard isWindowFullScreen != oldValue else { return }
            updateCornerRadius()
        }
    }

    /// A view kept in front of anything added after it: fullscreen's traffic
    /// lights, which stand over every panel the way the titlebar's do in a
    /// window.
    weak var frontmost: NSView?

    // After the add rather than in `didAddSubview`: a reorder made from
    // inside that callback is undone by the add it is answering.
    override func addSubview(_ view: NSView) {
        super.addSubview(view)
        keepFrontmost(over: view)
    }

    override func addSubview(_ view: NSView, positioned place: NSWindow.OrderingMode, relativeTo other: NSView?) {
        super.addSubview(view, positioned: place, relativeTo: other)
        keepFrontmost(over: view)
    }

    private func keepFrontmost(over view: NSView) {
        guard let frontmost, view !== frontmost, frontmost.superview === self, subviews.last !== frontmost else { return }
        super.addSubview(frontmost, positioned: .above, relativeTo: nil)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        updateCornerRadius()
        // Held weakly by NotificationCenter, so there is nothing to remove.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(settingsDidChange),
            name: Settings.didChange,
            object: nil
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its views in code")
    }

    @objc private func settingsDidChange() {
        updateCornerRadius()
    }

    private func updateCornerRadius() {
        let radius = isWindowFullScreen ? 0 : WindowCorner.radius
        guard layer?.cornerRadius != radius else { return }
        layer?.cornerRadius = radius
        // The shadow of a clear window is cut from what it draws, and is not
        // recomputed until something asks.
        window?.invalidateShadow()
    }
}
