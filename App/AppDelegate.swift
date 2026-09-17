//
//  AppDelegate.swift
//  Luna
//
//  Entry point. No storyboard, no nib — the app is built in code.
//

import AppKit

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// `NSApplicationMain` only installs an app delegate when it loads a main
    /// nib, and Luna has none — so we stand the app up ourselves. Verified: the
    /// inherited `NSApplicationDelegate.main()` leaves `NSApp.delegate` nil and
    /// the app launches to a dead run loop.
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        // `NSApplication.delegate` is weak and nothing else owns us.
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }

    /// AppKit's `NSWindow.windowController` is weak, so somebody has to own the
    /// controller. For M0 that is this one property; a window manager arrives
    /// when there is more than one window to manage.
    private var browserWindow: BrowserWindowController?

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Both must be in place before the app finishes launching, or the first
        // frame shows up without a menu bar.
        NSApp.setActivationPolicy(.regular)
        MainMenu.install(into: NSApp)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = BrowserWindowController(url: Self.startPage)
        browserWindow = controller
        controller.showWindow(self)
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Drop the window controller (and with it the web view) while AppKit is
        // still running, rather than leaving it to process teardown.
        browserWindow = nil
    }

    private static let startPage = URL(string: "https://example.com")!
}
