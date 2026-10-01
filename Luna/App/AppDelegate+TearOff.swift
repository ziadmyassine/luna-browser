//
//  AppDelegate+TearOff.swift
//  Luna
//
//  §6.6: where a tab pulled out of a window's list goes. The gesture and the
//  drag are `TabTearOff`'s; this is the app's half, because only the app
//  knows the other windows and can make a new one.
//
//  Let go of over another window onto the same session, the tab is shown
//  there; back in the list it came from, it stays. Let go of anywhere else
//  nothing took it — its own window's page, the desktop — it is a new window,
//  standing where the hand let go and showing the same live page, not a
//  reload of it. Taken by another app, it was a link, and nothing here
//  changes.
//

import AppKit
import BrowserKit

extension AppDelegate {

    /// Not in a §5.6 window: its session ends with the window, so a second
    /// window on it would lose its pages the moment the first one closed.
    func wireTearOff(in window: BrowserWindow) {
        guard !window.isPrivate else { return }
        let tearOff: (TabTearOff.Request) -> Void = { [weak self, weak window] request in
            guard let self, let window else { return }
            tearOff(request, from: window)
        }
        window.sidebar?.drag?.onTearOff = tearOff
        window.topBar?.drag?.onTearOff = tearOff
    }

    private func tearOff(_ request: TabTearOff.Request, from source: BrowserWindow) {
        guard let tab = source.session.tab(request.tabID), let frame = source.controller.window?.frame else { return }
        // Measured from the window's top-left, the corner a window is placed by.
        let grab = NSRect(x: request.press.x, y: frame.height - request.press.y, width: frame.width, height: frame.height)
        TabTearOff.begin(tab, as: request) { [weak self, weak source] landing, point in
            guard let self, let source else { return }
            land(request, from: source, landing: landing, at: point, grab: grab)
        }
    }

    /// - Parameter grab: where the press was, from the source window's
    ///   top-left, at the size of that window.
    private func land(
        _ request: TabTearOff.Request, from source: BrowserWindow, landing: TabTearOff.Landing, at point: NSPoint, grab: NSRect
    ) {
        switch landing {
        case .anotherApp:
            return
        case let .window(number) where number == source.controller.window?.windowNumber:
            // Back in the list it left is a drag that went nowhere; anywhere
            // else in its own window — over the page — it has left the list,
            // and it is a window of its own, as it is anywhere else.
            guard isClearOfItsList(request, at: point, in: source) else { return }
            openWindow(showing: request.tabID, from: source, at: point, grab: grab)
        case let .window(number):
            // Over a window on another session — a §5.6 one, Settings — it
            // has nowhere to be.
            guard let target = windows.first(where: { $0.controller.window?.windowNumber == number }),
                  target.session === source.session
            else { return }
            source.session.showTab(request.tabID, onlyInWindow: target.id)
            target.controller.window?.makeKeyAndOrderFront(nil)
        case .nowhere:
            openWindow(showing: request.tabID, from: source, at: point, grab: grab)
        }
    }

    /// The threshold that let the tab out, asked again where it was let go.
    private func isClearOfItsList(_ request: TabTearOff.Request, at point: NSPoint, in source: BrowserWindow) -> Bool {
        guard let window = source.controller.window, let content = window.contentView else { return false }
        return TabTearOff.hasTornOff(
            pointer: window.convertPoint(fromScreen: point),
            run: request.view.convert(request.view.bounds, to: nil),
            along: request.axis,
            window: content.convert(content.bounds, to: nil)
        )
    }

    private func openWindow(showing id: UUID, from source: BrowserWindow, at point: NSPoint, grab: NSRect) {
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? source.controller.window?.screen
        guard let visible = screen?.visibleFrame else { return }
        let window = BrowserWindow(session: source.session, controller: BrowserWindowController(remembersFrame: false))
        adopt(window, frame: Self.tornOffFrame(size: grab.size, droppedAt: point, grab: grab.origin, on: visible))
        source.session.showTab(id, onlyInWindow: window.id)
        window.render()
    }

    /// The new window's frame: the size of the window the tab came out of,
    /// held by the hand where the hand held that one, and kept on the screen
    /// it was let go on.
    /// - Parameter grab: the press, from the window's top-left corner.
    static func tornOffFrame(size: NSSize, droppedAt point: NSPoint, grab: NSPoint, on visible: NSRect) -> NSRect {
        let width = min(size.width, visible.width)
        let height = min(size.height, visible.height)
        let x = min(max(point.x - grab.x, visible.minX), visible.maxX - width)
        let top = min(max(point.y + grab.y, visible.minY + height), visible.maxY)
        return NSRect(x: x, y: top - height, width: width, height: height)
    }
}
