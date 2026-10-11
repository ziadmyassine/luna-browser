//
//  AppDelegate+TestHost.swift
//  Luna
//
//  The unit-test host runs on a Mac somebody is using. It is an accessory app
//  that never activates, and every window it orders in, the tests' own
//  included, is moved off every screen on the way. `TestHostFocusTests` holds
//  it to that.
//

import AppKit
import ObjectiveC

extension AppDelegate {

    /// XCTest is loaded into this process. A UI test's copy of the app is not
    /// this: it is driven through the window server and has to be in front.
    static var isUnitTestHost: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// `NSApp.activate()`, which the unit-test host never does.
    static func bringToFront() {
        guard !isUnitTestHost else { return }
        NSApp.activate()
    }

    /// Once, before the first window. A window is moved where it is ordered
    /// in rather than where it is made, because the app and the tests both
    /// place windows on the main screen and order them in from a dozen places;
    /// a shift rather than a fixed origin keeps windows' positions relative to
    /// each other, as Settings over its browser window or a cascade.
    static func keepTestHostOffScreen() {
        func swap(_ original: Selector, _ replacement: Selector) {
            guard let one = class_getInstanceMethod(NSWindow.self, original),
                  let other = class_getInstanceMethod(NSWindow.self, replacement)
            else { return }
            method_exchangeImplementations(one, other)
        }
        // AppKit pulls a titled window back until its title bar is on a
        // screen, on ordering in and on every move after.
        swap(#selector(NSWindow.constrainFrameRect(_:to:)), #selector(NSWindow.offScreenConstrain(_:to:)))
        swap(#selector(NSWindow.order(_:relativeTo:)), #selector(NSWindow.offScreenOrder(_:relativeTo:)))
        // A window on screen can be moved back onto it: a restored frame, a
        // cascade, a centring after `showWindow`.
        swap(#selector(NSWindow.setFrame(_:display:)), #selector(NSWindow.offScreenSetFrame(_:display:)))
        // Its own route: it does not pass through `order(_:relativeTo:)`.
        swap(#selector(NSWindow.orderFrontRegardless), #selector(NSWindow.offScreenOrderFrontRegardless))
    }
}

extension NSWindow {

    private static let testHostShift: CGFloat = -20_000

    // Each calls its own name, which after the exchange is AppKit's original.

    @objc fileprivate func offScreenConstrain(_ rect: NSRect, to screen: NSScreen?) -> NSRect { rect }

    @objc fileprivate func offScreenOrder(_ place: NSWindow.OrderingMode, relativeTo other: Int) {
        if place != .out { setFrameOrigin(offScreen(frame).origin) }
        offScreenOrder(place, relativeTo: other)
    }

    @objc fileprivate func offScreenOrderFrontRegardless() {
        setFrameOrigin(offScreen(frame).origin)
        offScreenOrderFrontRegardless()
    }

    @objc fileprivate func offScreenSetFrame(_ rect: NSRect, display: Bool) {
        offScreenSetFrame(isVisible ? offScreen(rect) : rect, display: display)
    }

    /// A window with nothing to show may stay. Off every screen, a mouse event
    /// posted to a window's queue comes back out of it displaced by thousands
    /// of points (measured: posted at x 197, read at x -20221), so a test that
    /// drives a drag through the queue keeps its window on screen at zero
    /// alpha (`TopBarTabDragTests`).
    private func offScreen(_ rect: NSRect) -> NSRect {
        guard alphaValue > 0, NSScreen.screens.contains(where: { $0.frame.intersects(rect) }) else { return rect }
        return rect.offsetBy(dx: Self.testHostShift, dy: Self.testHostShift)
    }
}
