//
//  AppDelegate+Report.swift
//  Luna
//
//  Help ▸ Report a Bug and Suggest an Idea: GitHub's own issue form, filled
//  in (`ReportLink`), with a picture of the window, the page or an area put
//  on the pasteboard for the reporter to paste. The repo is public, so
//  nothing reaches it unless the reporter pastes it and posts.
//

import AppKit
import LunaControl
import WebKit

/// What Report a Bug puts on the pasteboard.
enum BugShot {
    case window, page, area, none
}

/// Takes a `BugShot` onto the pasteboard, secret fields masked whichever it
/// is. Window and area shots are `screencapture`'s, because
/// `CGWindowListCreateImage` is obsolete, and need Screen Recording; the
/// page is WebKit's own snapshot and needs nothing.
@MainActor
struct BugScreenshot {

    enum Taken {
        case copied, nothing, cancelled, needsPermission
    }

    var pasteboard = NSPasteboard.general
    /// Asks once when the answer is no; macOS shows its prompt only the first time.
    var canRecord: () -> Bool = { CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() }
    /// Five minutes: an area pick waits for the user.
    var run: @MainActor (URL, [String]) async throws -> Void = {
        _ = try await ControlCLI.run($0, arguments: $1, timeout: 300)
    }

    /// The longest side of a page picture, in pixels.
    private static let pageSide = 1_600.0

    func take(_ shot: BugShot, window: Int, page: WKWebView?) async -> Taken {
        switch shot {
        case .none:
            return .nothing
        case .page:
            guard let page, let png = await Self.picture(of: page) else { return .nothing }
            pasteboard.clearContents()
            pasteboard.setData(png, forType: .png)
            return .copied
        case .window, .area:
            guard canRecord() else { return .needsPermission }
            let before = pasteboard.changeCount
            let arguments = shot == .window ? ["-l", "\(window)", "-c", "-o", "-x"] : ["-i", "-c", "-x"]
            await ControlCapture.whileMasked(page) {
                try? await run(URL(filePath: "/usr/sbin/screencapture"), arguments)
            }
            if pasteboard.changeCount != before { return .copied }
            // An area pick that copied nothing was Esc.
            return shot == .area ? .cancelled : .nothing
        }
    }

    /// At most `pageSide` on the long side, and at most two pixels per CSS pixel.
    private static func picture(of page: WKWebView) async -> Data? {
        let zoom = page.pageZoom * page.magnification
        let longest = max(page.bounds.width, page.bounds.height) / zoom
        guard longest > 0, let image = try? await ControlCapture.image(of: page, scale: min(2, pageSide / longest)) else {
            return nil
        }
        return ControlCapture.png(image)
    }
}
