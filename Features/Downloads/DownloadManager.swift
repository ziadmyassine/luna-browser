//
//  DownloadManager.swift
//  Luna
//
//  TODO.md §15.1/§15.3/§15.4 — the `WKDownloadDelegate` plumbing, the
//  quarantine record, and the confirmation for files that run when you open
//  them. Wave 1 already decided whether something is a download
//  (`NavigationPolicy.shouldDownload`, which is also where §15.4's
//  background-frame rule lives); this file owns everything after that point.
//
//  THREE THINGS THAT ARE NOT OBVIOUS AND COST A DAY EACH:
//
//  1. `WKDownload.delegate` is `weak`. A delegate that is only referenced by
//     the download is deallocated before WebKit asks for a destination, and the
//     download stalls with no error, no callback and nothing in the log. The
//     `tasks` dictionary below is the strong reference that keeps it alive, and
//     the only reason that dictionary exists.
//
//  2. `decideDestinationUsing` takes no `Bool` on macOS 26.5. TODO.md §15.1
//     records a trap — "must answer `(url, true)`; the second value grants the
//     sandbox extension" — that came from an older SDK. Verified against
//     `MacOSX26.5.sdk/.../WKDownloadDelegate.h`: the protocol's one required
//     method completes with `(NSURL * _Nullable destination)` and nothing else,
//     and the `(URL, Bool)` spelling does not compile. The async form is used
//     here because §15.4's confirmation has to be awaited mid-decision.
//
//  3. There is no byte-count callback. The modern protocol dropped
//     `download(_:didReceive:)`, so `WKDownload.progress` (it is
//     `NSProgressReporting`) is the only progress there is — hence the KVO.
//
//  Everything in this file is `@MainActor` because `WKDownload` and
//  `WKDownloadDelegate` are (`WK_SWIFT_UI_ACTOR` in the SDK). That is what
//  makes it warning-free under strict concurrency with no escape hatches.
//

import AppKit
import Foundation
import WebKit

@MainActor
final class DownloadManager {

    /// Newest first — the order §15.3's list reads.
    private(set) var items: [DownloadItem] = []

    /// Strong references to the per-download delegates. See trap 1.
    private var tasks: [ObjectIdentifier: DownloadTask] = [:]

    /// Any observer re-reads `items` and re-renders. Set by the list panel
    /// while it is open; nil the rest of the time, which is what keeps
    /// progress KVO from costing anything when nothing is watching.
    var onChange: (() -> Void)?

    /// A download landed. The host puts §15.3's list up on whichever
    /// Downloads button its layout is showing, standing on the same button the
    /// file was thrown at (§5.0) and showing the same row finishing.
    ///
    /// The choice is the host's because this file cannot see the chrome, and
    /// the one build where it guessed is the reason the hook exists: it asked
    /// the top bar for an anchor unconditionally, so in the sidebar layout
    /// every completed download put a surface above the window's top-left
    /// corner with its tail pointing into the sidebar toggle. It was answering
    /// the right event at the wrong end of the window.
    var onFinish: ((DownloadItem) -> Void)?

    /// §5.0: the destination is settled and the bytes are on their way, so the
    /// file can be thrown at the Downloads button and the list opened under it.
    ///
    /// Fired here rather than from `begin`, which is where the download
    /// arrives: between the two, §15.4 may have put a confirmation up and the
    /// user may have said no. A file nobody agreed to download must not be
    /// thrown anywhere, and a flight that plays behind a modal sheet is a
    /// flight the user never sees.
    var onBegin: ((DownloadItem) -> Void)?

    /// A live web view to re-issue a retry through. `WKDownload.webView` is
    /// weak and the originating tab may have been hibernated since, so the host
    /// hands us the active tab's web view instead — resume data is
    /// self-contained and any web view can resume it.
    var webViewProvider: (() -> WKWebView?)?

    // MARK: - Entry point

    /// Call from `BrowserSession.onDownload`, i.e. from
    /// `TabControllerDelegate.tabController(_:didStartDownload:)`. The delegate
    /// is set here, before returning, as that contract requires.
    ///
    /// `pageURL` defaults to the originating frame's own URL, so the host does
    /// not have to look up which tab this came from.
    func begin(_ download: WKDownload, pageURL: URL? = nil) {
        // §15.4 — no silent auto-downloads from background frames. Wave 1's
        // `NavigationPolicy.shouldDownload` covers the response path; this
        // covers `<a download>` in a hidden iframe, which never reaches it.
        guard download.isUserInitiated || download.originatingFrame.isMainFrame else {
            download.cancel()
            return
        }
        let suggested = download.originalRequest?.url?.lastPathComponent ?? DownloadDestination.fallbackName
        let item = DownloadItem(
            request: download.originalRequest,
            pageURL: pageURL ?? download.originatingFrame.request.url,
            filename: DownloadDestination.sanitize(suggested)
        )
        items.insert(item, at: 0)
        adopt(download, for: item)
        onChange?()
    }

    private func adopt(_ download: WKDownload, for item: DownloadItem) {
        let task = DownloadTask(manager: self, item: item, download: download)
        tasks[ObjectIdentifier(download)] = task
        download.delegate = task
    }

    // MARK: - User actions (§15.3)

    func reveal(_ item: DownloadItem) {
        guard let url = item.destination, item.isOnDisk else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func open(_ item: DownloadItem) {
        guard let url = item.destination, item.isOnDisk else { return }
        NSWorkspace.shared.open(url)
    }

    func remove(_ item: DownloadItem) {
        items.removeAll { $0 === item }
        onChange?()
    }

    /// Clears finished and failed entries. A live download is not history.
    func clearCompleted() {
        items.removeAll { $0.state != .inProgress }
        onChange?()
    }

    /// Resume where the bytes stopped when the server allows it, otherwise
    /// re-issue the original request (§15.1a).
    func retry(_ item: DownloadItem) {
        guard item.canRetry, let webView = webViewProvider?() else { return }
        item.restart()
        onChange?()
        Task { @MainActor in
            let download: WKDownload? = if let data = item.resumeData {
                await webView.resumeDownload(fromResumeData: data)
            } else if let request = item.request {
                await webView.startDownload(using: request)
            } else {
                nil
            }
            guard let download else { return }
            self.adopt(download, for: item)
        }
    }

    // MARK: - Called back by `DownloadTask`

    fileprivate func progressChanged() {
        onChange?()
    }

    /// The destination is decided and the first byte is on its way. See
    /// `onBegin` for why this is not `begin`.
    fileprivate func started(_ item: DownloadItem) {
        onChange?()
        onBegin?(item)
    }

    fileprivate func finished(_ item: DownloadItem, download: WKDownload) {
        tasks[ObjectIdentifier(download)] = nil
        item.finish()
        Self.quarantine(item)
        onChange?()
        // §5: completion is the only thing that gets an announcement of its
        // own — a failure belongs in the list, not over the window. A list
        // already standing open on the button is already showing this row
        // finish, and `onFinish`'s host does nothing in that case.
        onFinish?(item)
    }

    fileprivate func failed(_ item: DownloadItem, download: WKDownload, error: any Error, resumeData: Data?) {
        tasks[ObjectIdentifier(download)] = nil
        item.fail(error, resumeData: resumeData)
        onChange?()
    }

    // MARK: - §15.3 quarantine

    /// Writes the `com.apple.quarantine` record so Gatekeeper still protects the
    /// user.
    ///
    /// Luna is not sandboxed (TODO.md §22.1, D8) — the App Sandbox is what
    /// normally has the OS stamp downloads for you. Without this, a `.dmg`
    /// Luna downloads opens with no "downloaded from the internet" check at
    /// all, which is a security regression against every other browser.
    ///
    /// Written through `URLResourceValues.quarantineProperties` rather than a
    /// hand-formatted `setxattr`: the xattr's payload is
    /// `flags;hex-time;agent;uuid` and getting a field wrong produces a record
    /// LaunchServices ignores — silently, which is the worst possible failure
    /// for a security control. `kLSQuarantineOriginURLKey` is what puts the
    /// originating page into the Gatekeeper dialog.
    private static func quarantine(_ item: DownloadItem) {
        guard var url = item.destination else { return }
        var values = URLResourceValues()
        var properties: [String: Any] = [
            kLSQuarantineTypeKey as String: kLSQuarantineTypeWebDownload as String,
            kLSQuarantineAgentNameKey as String: Bundle.main.bundleIdentifier ?? "Luna",
            kLSQuarantineTimeStampKey as String: Date() as NSDate
        ]
        if let page = item.pageURL { properties[kLSQuarantineOriginURLKey as String] = page as NSURL }
        if let source = item.request?.url { properties[kLSQuarantineDataURLKey as String] = source as NSURL }
        values.quarantineProperties = properties
        try? url.setResourceValues(values)
    }
}

// MARK: - The delegate WebKit talks to

/// One per download, retained by `DownloadManager.tasks`. See trap 1.
@MainActor
private final class DownloadTask: NSObject, WKDownloadDelegate {

    private unowned let manager: DownloadManager
    private let item: DownloadItem
    private let download: WKDownload
    private var progressObservation: NSKeyValueObservation?

    init(manager: DownloadManager, item: DownloadItem, download: WKDownload) {
        self.manager = manager
        self.item = item
        self.download = download
        super.init()
    }

    // MARK: Destination

    func download(
        _ download: WKDownload,
        decideDestinationUsing response: URLResponse,
        suggestedFilename: String
    ) async -> URL? {
        let name = DownloadDestination.sanitize(
            suggestedFilename.isEmpty ? item.filename : suggestedFilename
        )

        // §15.4 — ask before writing anything that runs when it is opened.
        // Awaited here on purpose: WebKit holds the download until we answer,
        // so a declined warning cancels it before a byte hits the disk.
        if DownloadRisk.isRisky(filename: name), await !confirmRisky(name) {
            return nil
        }

        let destination = DownloadDestination.unique(
            DownloadDestination.folder.appending(path: name, directoryHint: .notDirectory),
            exists: { FileManager.default.fileExists(atPath: $0.path) }
        )
        item.willWrite(to: destination, progress: download.progress)
        observeProgress(download.progress)
        manager.started(item)
        return destination
    }

    private func confirmRisky(_ name: String) async -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Download “\(name)”?")
        alert.informativeText = String(
            localized: "This file can run programs on your Mac. Only open it if you trust where it came from."
        )
        alert.addButton(withTitle: String(localized: "Download"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        // Escape must map to Cancel, and the destructive answer must not be the
        // one a stray Return press picks.
        alert.buttons.last?.keyEquivalent = "\u{1b}"

        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            return await alert.beginSheetModal(for: window) == .alertFirstButtonReturn
        }
        return alert.runModal() == .alertFirstButtonReturn
    }

    // MARK: Progress (trap 3)

    private func observeProgress(_ progress: Progress) {
        // WebKit updates `Progress` on the main thread; `assumeIsolated` states
        // that rather than hiding it behind an unchecked conformance — same
        // pattern as `TabController.attach`.
        progressObservation = progress.observe(\.fractionCompleted, options: [.new]) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.manager.progressChanged() }
        }
    }

    // MARK: Completion

    func downloadDidFinish(_ download: WKDownload) {
        progressObservation?.invalidate()
        progressObservation = nil
        manager.finished(item, download: download)
    }

    func download(_ download: WKDownload, didFailWithError error: any Error, resumeData: Data?) {
        progressObservation?.invalidate()
        progressObservation = nil
        manager.failed(item, download: download, error: error, resumeData: resumeData)
    }

    // MARK: Redirects and auth

    func download(
        _ download: WKDownload,
        decidedPolicyForHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> WKDownload.RedirectPolicy {
        .allow
    }

    /// Without this the default is `rejectProtectionSpace`, which breaks every
    /// download behind basic auth or a client certificate.
    func download(
        _ download: WKDownload,
        respondTo challenge: URLAuthenticationChallenge
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        (.performDefaultHandling, nil)
    }
}
