//
//  AppDelegate+Report.swift
//  Luna
//
//  Help ▸ Report a Bug and Suggest an Idea: GitHub's own issue form, filled
//  in (`ReportLink`), with a picture of the window, the page or an area put
//  on the pasteboard for the reporter to paste. The repo is public, so
//  nothing reaches it unless the reporter pastes it and posts. The five
//  commands' table entries are here too, with the feature they belong to.
//

import AppKit
import BrowserKit
import LunaControl
import WebKit

extension BrowserCommand {

    /// Short titles in Help ▸ Report a Bug (`MainMenu.helpMenu`); these whole
    /// ones in the Command Bar and Settings ▸ Shortcuts, where a row is read alone.
    static let reportBugWindow = BrowserCommand(
        "reportBugWindow", "Report a Bug with a Window Screenshot", #selector(AppDelegate.reportBugWindow(_:)),
        [KeyBinding("i", [.command, .shift])], symbol: "ladybug", keywords: bugKeywords
    )
    static let reportBugPage = BrowserCommand(
        "reportBugPage", "Report a Bug with a Page Screenshot", #selector(AppDelegate.reportBugPage(_:)),
        symbol: "ladybug", keywords: bugKeywords
    )
    static let reportBugArea = BrowserCommand(
        "reportBugArea", "Report a Bug with an Area Screenshot…", #selector(AppDelegate.reportBugArea(_:)),
        symbol: "ladybug", keywords: bugKeywords
    )
    static let reportBugNoScreenshot = BrowserCommand(
        "reportBugNoScreenshot", "Report a Bug without a Screenshot", #selector(AppDelegate.reportBugNoScreenshot(_:)),
        symbol: "ladybug", keywords: bugKeywords
    )
    static let suggestIdea = BrowserCommand(
        "suggestIdea", "Suggest an Idea…", #selector(AppDelegate.suggestIdea(_:)),
        symbol: "lightbulb", keywords: ["feature request", "feedback", "issue", "github"]
    )
    private static let bugKeywords = ["bug report", "feedback", "issue", "github", "screenshot"]
}

extension AppDelegate {

    /// Dimmed in a private window (`validateMenuItem`): it is signed out of
    /// GitHub, and its pages are not to be pictured.
    static let reportActions = [
        #selector(reportBugWindow(_:)), #selector(reportBugPage(_:)), #selector(reportBugArea(_:)),
        #selector(reportBugNoScreenshot(_:)), #selector(suggestIdea(_:))
    ]

    @objc func reportBugWindow(_ sender: Any?) { reportBug(.window) }
    @objc func reportBugPage(_ sender: Any?) { reportBug(.page) }
    @objc func reportBugArea(_ sender: Any?) { reportBug(.area) }
    @objc func reportBugNoScreenshot(_ sender: Any?) { reportBug(.none) }

    @objc func suggestIdea(_ sender: Any?) {
        application(NSApp, open: [ReportLink.idea])
    }

    /// The link is built before the shot, so its context is what was on
    /// screen when the reporter asked rather than after an area pick.
    private func reportBug(_ shot: BugShot) {
        guard let window = front, !window.isPrivate, let host = window.controller.window else { return }
        let session = window.session
        let here = Set(session.tabs(inWindow: window.id).map(\.id))
        let tab = Self.reportedTab(active: session.activeTabID(inWindow: window.id), recent: session.recentTabs) {
            here.contains($0) ? session.controller(for: $0)?.webView?.url : nil
        }.flatMap { session.controller(for: $0) }
        let page = tab?.webView
        let luna = ReportLink.lunaLine(
            version: Updater.version.description, build: Updater.build, release: Updater.shared.canInstall,
            commit: Bundle.main.object(forInfoDictionaryKey: "LunaCommit") as? String ?? "unknown"
        )
        let link = ReportLink.bug(
            luna: luna, macos: ProcessInfo.processInfo.operatingSystemVersionString, url: page?.url,
            context: reportContext(window, tab: tab)
        )
        Task {
            let taken = await BugScreenshot().take(shot, window: host.windowNumber, page: page)
            // An area pick can take minutes, and the window may have closed
            // meanwhile: then the front ordinary window, or nothing.
            let target = windows.contains { $0 === window } ? window : front.flatMap { $0.isPrivate ? nil : $0 }
            guard let target, taken != .cancelled else { return }
            let toastHost = target.controller.window
            switch taken {
            case .needsPermission:
                PageToast.screenRecordingNeeded {
                    let pane = "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture"
                    if let url = URL(string: pane) { NSWorkspace.shared.open(url) }
                }.show(in: toastHost)
            case .copied:
                open([link], in: target)
                PageToast.screenshotCopied(shot).show(in: toastHost)
            case .nothing, .cancelled:
                open([link], in: target)
            }
        }
    }

    /// The tab a report is about: the active one, unless it is one of this
    /// repo's issue pages (the form just filed, an issue being read), and then
    /// the newest other tab with a page that is not. `url` is nil for a tab
    /// with no page, or outside the window's Space. `recent` is the session's
    /// most-recently-used list, which spans windows; `url` keeps it to this one.
    static func reportedTab(active: UUID?, recent: [UUID], url: (UUID) -> URL?) -> UUID? {
        guard let active, ReportLink.isIssuePage(url(active)) else { return active }
        return recent.first { $0 != active && url($0).map { !ReportLink.isIssuePage($0) } == true } ?? active
    }

    /// `#rrggbb`, or nil while the page loads: until then WebKit reports
    /// the blank tab's colour, not the page's.
    static func pageBackground(_ colour: RGBA?, loading: Bool) -> String? {
        guard let colour, !loading else { return nil }
        return "#" + [colour.r, colour.g, colour.b].map { String(format: "%02x", min(max(Int(($0 * 255).rounded()), 0), 255)) }.joined()
    }

    /// One line each, most important first; `ReportLink` drops from the end
    /// when the link runs long, so the layout is in the first. English, as the issue is. Selectors only from
    /// the hidden elements, never their labels, which are page text.
    func reportContext(_ window: BrowserWindow, tab: TabController?) -> [String] {
        let session = window.session
        let page = tab?.webView
        let site = page?.url?.host()
        var lines: [String] = []
        if let host = window.controller.window {
            var parts: [String] = []
            if let tab, let page {
                parts.append("\"\(session.linkTitle(of: tab.id).prefix(80))\"")
                parts.append("zoom \(Int((page.pageZoom * page.magnification * 100).rounded())) %")
            }
            parts.append("window \(Int(host.frame.width))×\(Int(host.frame.height))")
            // `FindController.colourUnder`'s source.
            if let tab, let colour = Self.pageBackground(tab.topColour ?? tab.state.pageBackground, loading: tab.state.isLoading) {
                parts.append("page background \(colour)")
            }
            let dark = host.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            parts.append("Luna \(dark ? "dark" : "light")")
            parts.append("\(host.styleMask.contains(.fullScreen) ? "Full screen" : Settings.chromeLayout.title) layout")
            lines.append("Page: " + parts.joined(separator: ", "))
        }
        let recent = RecentCommands.titles
        if !recent.isEmpty { lines.append("Before this: " + recent.joined(separator: ", ")) }
        if let site {
            lines.append("Site: " + SiteMenu.toggles(host: site).map { "\($0.title) \($0.isOn ? "on" : "off")" }
                .joined(separator: ", "))
        }
        let extensions = ExtensionsCenter.shared.installed.filter { $0.enabledSpaces.contains(window.activeSpaceID) }
        if !extensions.isEmpty {
            lines.append("Extensions: " + extensions.map { info in
                [info.details?.name ?? info.id, info.details?.version ?? ""].filter { !$0.isEmpty }.joined(separator: " ")
            }.joined(separator: ", "))
        }
        let hidden = session.hiddenElements.elements(onHost: site)
        if !hidden.isEmpty {
            lines.append("Hidden here: " + hidden.map { String($0.selector.prefix(60)) }.joined(separator: ", "))
        }
        return lines
    }
}

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
    /// Every page a window or area shot can take in: an area can reach
    /// across Luna's windows, private ones included.
    var onScreen: @MainActor () -> [WKWebView] = {
        NSApp.windows.filter(\.isVisible).compactMap(\.contentView).flatMap { BugScreenshot.webViews(in: $0) }
    }
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
            let pages = ([page].compactMap { $0 } + onScreen()).reduce(into: [WKWebView]()) { all, view in
                if !all.contains(view) { all.append(view) }
            }
            await Self.masking(pages[...]) {
                try? await run(URL(filePath: "/usr/sbin/screencapture"), arguments)
            }
            if pasteboard.changeCount != before { return .copied }
            // An area pick that copied nothing was Esc.
            return shot == .area ? .cancelled : .nothing
        }
    }

    static func webViews(in view: NSView) -> [WKWebView] {
        view.subviews.flatMap { ($0 as? WKWebView).map { [$0] } ?? webViews(in: $0) }
    }

    /// `ControlCapture.whileMasked` around each page in turn.
    private static func masking(_ pages: ArraySlice<WKWebView>, _ body: () async -> Void) async {
        guard let first = pages.first else { return await body() }
        await ControlCapture.whileMasked(first) { await masking(pages.dropFirst(), body) }
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
