//
//  TabTearOff.swift
//  Luna
//
//  §6.6's way out of the list. A lifted tab is locked to its column (or, on
//  §4's bar, to its line) and the lock stays: only once the pointer is
//  `Metric.tabTearOffDistance` clear of the column, or of the window, does
//  the tab leave it. From there it is an AppKit drag carrying the tab's link,
//  so another app can take it — Finder makes a .webloc, Mail and Notes the
//  address — and wherever nothing takes it, it becomes a window of its own.
//
//  Luna's own views refuse it (`sourceOperationMask` offers nothing inside the
//  app), so a release over one of Luna's windows is decided here, at the
//  source, and not by whichever view happens to be under the pointer: a page
//  would otherwise load the link over itself.
//
//  The desktop is Finder's, and Finder would take the link and leave a .webloc
//  on it. A tab let go of over the desktop is a tab let go of nowhere, so the
//  link is withheld there and the tab becomes a window, as it does in every
//  other browser.
//

import AppKit
import BrowserKit

@MainActor
final class TabTearOff: NSObject {

    /// Where the torn-off tab came down.
    enum Landing: Equatable {
        /// Over one of Luna's own windows.
        case window(Int)
        /// Another app took the link.
        case anotherApp
        /// The desktop, or anywhere nothing took it.
        case nowhere
    }

    /// The pasteboard type that says "this is a tab, not just a link" — what
    /// Luna's own drop targets look for so they can refuse it.
    nonisolated static let tabType = NSPasteboard.PasteboardType("dev.novapps.luna.tab")
    /// Finder names a .webloc after this.
    nonisolated static let urlNameType = NSPasteboard.PasteboardType("public.url-name")

    /// The one tear-off in the air. Held here because `NSDraggingSession` does
    /// not keep its source alive.
    private static var current: TabTearOff?

    let tabID: UUID
    /// The two things another app is handed, read from the pasteboard's
    /// callback, which AppKit declares outside the main actor.
    nonisolated private let link: String
    nonisolated private let name: String
    private let ended: (Landing, NSPoint) -> Void

    private init(tab: Tab, title: String, ended: @escaping (Landing, NSPoint) -> Void) {
        tabID = tab.id
        link = tab.url.absoluteString
        name = title
        self.ended = ended
    }

    /// A lift that has crossed the threshold, as the gesture hands it over.
    struct Request {
        let tabID: UUID
        /// What the lift was drawing, for the drag image.
        let content: SidebarRowContent
        /// The view the drag starts from — the column or the bar, which is the
        /// run it left — and the drag image's frame in it.
        let view: NSView
        let frame: NSRect
        /// Which way that run is locked.
        let axis: Axis
        /// The press that started the gesture, in its window's coordinates —
        /// where the hand held the window, which is where a new one is held.
        let press: NSPoint
        /// The drag event that crossed the threshold.
        let event: NSEvent
    }

    // MARK: - The threshold

    /// Which way a list runs, and so which way the lock holds a lift.
    enum Axis { case vertical, horizontal }

    /// Whether a lift has gone far enough out to leave its list: clear of the
    /// run across the way it is locked, or clear of the window in any
    /// direction, by `tabTearOffDistance`. Everything is in one coordinate
    /// space — the window's.
    ///
    /// The run is the whole column or the whole bar, not the row's pill: a
    /// reorder stays inside it however wide the hand's arc, and only a pull
    /// out of it is a pull away from the list.
    static func hasTornOff(pointer: NSPoint, run: NSRect, along axis: Axis, window: NSRect) -> Bool {
        let distance = Tokens.Metric.tabTearOffDistance
        let across = switch axis {
        case .vertical: max(run.minX - pointer.x, pointer.x - run.maxX)
        case .horizontal: max(run.minY - pointer.y, pointer.y - run.maxY)
        }
        let outside = max(
            window.minX - pointer.x, pointer.x - window.maxX,
            window.minY - pointer.y, pointer.y - window.maxY
        )
        return across >= distance || outside >= distance
    }

    // MARK: - Starting one

    /// Hands the tab to AppKit's drag, standing where the request says. AppKit
    /// takes the drag over once the press that started it returns.
    /// - Parameter ended: where it came down, and the screen point it was let
    ///   go at.
    static func begin(_ tab: Tab, as request: Request, ended: @escaping (Landing, NSPoint) -> Void) {
        let source = TabTearOff(tab: tab, title: request.content.title, ended: ended)
        let item = NSDraggingItem(pasteboardWriter: source.pasteboardItem())
        let image = dragImage(request.content, size: request.frame.size, in: request.view.effectiveAppearance)
        item.setDraggingFrame(request.frame, contents: image)
        let session = request.view.beginDraggingSession(with: [item], event: request.event, source: source)
        // A tab that went nowhere becomes a window there, so it must not be
        // seen sliding home first.
        session.animatesToStartingPositionsOnCancelOrFail = false
        current = source
    }

    private func pasteboardItem() -> NSPasteboardItem {
        let item = NSPasteboardItem()
        item.setString(tabID.uuidString, forType: Self.tabType)
        // Promised rather than written, so the desktop can be refused at the
        // moment it asks — see `pasteboard(_:item:provideDataForType:)`.
        item.setDataProvider(self, forTypes: [.URL, .string, Self.urlNameType])
        return item
    }

    // MARK: - Where it came down

    /// The window a mouse-down at `point` would land in, looking through the
    /// drag image if the window server answers with it.
    static func windowNumber(at point: NSPoint) -> Int {
        var number = NSWindow.windowNumber(at: point, belowWindowWithWindowNumber: 0)
        while number > 0, layer(ofWindow: number) == Int(CGWindowLevelForKey(.draggingWindow)) {
            number = NSWindow.windowNumber(at: point, belowWindowWithWindowNumber: number)
        }
        return number
    }

    /// Whether `point` is on the desktop: no window there, or only the ones
    /// below every app's — Finder's icons and the wallpaper sit at negative
    /// levels, measured at −2147483603 and −2147483625.
    static func isDesktop(at point: NSPoint) -> Bool {
        let number = windowNumber(at: point)
        guard number > 0, let layer = layer(ofWindow: number) else { return true }
        return isDesktopLayer(layer)
    }

    static func isDesktopLayer(_ layer: Int) -> Bool {
        layer < Int(CGWindowLevelForKey(.normalWindow))
    }

    private static func layer(ofWindow number: Int) -> Int? {
        let info = CGWindowListCopyWindowInfo(.optionIncludingWindow, CGWindowID(number)) as? [[String: Any]]
        return info?.first?[kCGWindowLayer as String] as? Int
    }

    /// What a release means, from where it was and whether anyone took it.
    static func landing(at point: NSPoint, accepted: Bool) -> Landing {
        let number = windowNumber(at: point)
        if number > 0, NSApp.window(withWindowNumber: number) != nil { return .window(number) }
        if isDesktop(at: point) { return .nowhere }
        return accepted ? .anotherApp : .nowhere
    }

    // MARK: - The drag image

    /// The row as it was lifted, on an opaque plate: the page under a drag
    /// outside the window is anything at all, and §3.4's translucent pill
    /// over it was a title nobody could read.
    private static func dragImage(_ content: SidebarRowContent, size: NSSize, in appearance: NSAppearance) -> NSImage {
        var plate = NSColor.clear
        var rim = NSColor.clear
        var ink = NSColor.clear
        appearance.performAsCurrentDrawingAppearance {
            plate = NSColor(cgColor: Tokens.Surface.raised.cgColor) ?? .clear
            rim = NSColor(cgColor: Tokens.Line.border.cgColor) ?? .clear
            ink = NSColor(cgColor: Tokens.Text.primary.cgColor) ?? .clear
        }
        let icon = content.favicon ?? NSImage(systemSymbolName: content.symbolName, accessibilityDescription: nil)
        let title = NSAttributedString(
            string: content.title,
            attributes: [.font: Tokens.TypeScale.sidebarRow, .foregroundColor: ink]
        )
        let image = NSImage(size: size, flipped: false) { rect in
            let radius = Tokens.Metric.rowCornerRadius
            let shape = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
            plate.setFill()
            shape.fill()
            rim.setStroke()
            shape.stroke()
            let side = Tokens.Metric.faviconSize
            let inset = Tokens.Metric.rowFaviconInset - Tokens.Metric.rowInset
            let iconRect = NSRect(x: rect.minX + inset, y: rect.midY - side / 2, width: side, height: side)
            icon?.draw(in: iconRect)
            let titleX = iconRect.maxX + Tokens.Metric.rowTitleGap
            let titleSize = title.size()
            title.draw(
                with: NSRect(
                    x: titleX,
                    y: rect.midY - titleSize.height / 2,
                    width: max(rect.maxX - inset - titleX, 0),
                    height: titleSize.height
                ),
                options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine]
            )
            return true
        }
        return image
    }
}

// MARK: - NSDraggingSource

extension TabTearOff: NSDraggingSource {

    /// Nothing inside Luna: its own views would open the link as a page, and
    /// a tab is not a link to them. Outside, a copy or a link, as a link from
    /// any other app offers — and nothing over the desktop.
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        guard context == .outsideApplication, !Self.isDesktop(at: NSEvent.mouseLocation) else { return [] }
        return [.copy, .link, .generic]
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        Self.current = nil
        ended(Self.landing(at: screenPoint, accepted: !operation.isEmpty), screenPoint)
    }
}

// MARK: - NSPasteboardItemDataProvider

extension TabTearOff: NSPasteboardItemDataProvider {

    nonisolated func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
        // AppKit asks on the main thread, where the drag runs; anywhere else
        // there is no pointer to ask about, and the link is simply given.
        let desktop = Thread.isMainThread && MainActor.assumeIsolated { Self.isDesktop(at: NSEvent.mouseLocation) }
        guard let string = Self.string(for: type, link: link, name: name, overDesktop: desktop) else { return }
        item.setString(string, forType: type)
    }

    /// What the pasteboard hands over for `type`: the page's name for Finder
    /// to call the .webloc, the address for everything else, and nothing at
    /// all over the desktop.
    nonisolated static func string(
        for type: NSPasteboard.PasteboardType, link: String, name: String, overDesktop: Bool
    ) -> String? {
        guard !overDesktop else { return nil }
        return type == urlNameType ? name : link
    }
}
