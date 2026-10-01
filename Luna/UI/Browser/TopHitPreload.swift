//
//  TopHitPreload.swift
//  Luna
//
//  Safari's Preload Top Hit. While the command bar completes an address from
//  a site the user has been to, that page loads in a tab nobody can see yet;
//  Return then opens a page that is already there instead of starting one.
//  Chromium browsers do the same from the omnibox, and it is the head start
//  WebKit still allows: measured on the real web, speculation rules and
//  preconnecting changed nothing in a `WKWebView`.
//
//  Only a completion from history or the adaptive table counts — a site the
//  user went to before, never a half-typed host or a search. A page that is
//  never opened goes when the bar does.
//
//  The page loads at the size it will be shown at. At no size at all some
//  sites stall: measured, Wikipedia took 1.8 s and 19 s to finish after
//  Return instead of 3 to 6 ms, and 360 ms opened without a preload.
//

import BrowserKit
import WebKit

@MainActor
final class TopHitPreload {

    /// Typing past one completion and on to the next is not a reason to start
    /// a load for each; the address has to hold this long first.
    static let settle: Duration = .milliseconds(150)

    private(set) var url: URL?
    private var spaceID: UUID?
    private var controller: TabController?
    private var starting: Task<Void, Never>?

    /// The page the bar would open on Return, or nil when it would not open a
    /// remembered site. Starts the load once the address has settled.
    /// - Parameter size: the page area's, so the page lays out as it will be shown.
    func want(_ url: URL?, inSpace spaceID: UUID, size: CGSize, session: BrowserSession) {
        guard let url, ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            cancel()
            return
        }
        guard url != self.url || spaceID != self.spaceID else { return }
        cancel()
        self.url = url
        self.spaceID = spaceID
        starting = Task { [weak self, weak session] in
            do { try await Task.sleep(for: Self.settle) } catch { return }
            guard let self, let session, self.url == url else { return }
            self.start(url, inSpace: spaceID, size: size, session: session)
        }
    }

    private func start(_ url: URL, inSpace spaceID: UUID, size: CGSize, session: BrowserSession) {
        // The id is the tab's own from the start: `TabController` keeps the id
        // it was made with, and an adopted page becomes that tab.
        let controller = TabController(
            id: UUID(),
            dataStore: session.dataStore(forSpace: spaceID),
            favicons: session.favicons,
            webExtensionController: session.extensionController(forSpace: spaceID)
        )
        controller.load(url)
        controller.webView?.frame = CGRect(origin: .zero, size: size)
        self.controller = controller
    }

    /// The loaded page for `url` in `spaceID`, handed over once. Nil when the
    /// user chose something else, or chose it before the load had started.
    func take(_ url: URL?, inSpace spaceID: UUID) -> TabController? {
        guard let url, url == self.url, spaceID == self.spaceID, let controller else { return nil }
        self.controller = nil
        cancel()
        return controller
    }

    func cancel() {
        starting?.cancel()
        starting = nil
        url = nil
        spaceID = nil
        controller?.hibernate()
        controller = nil
    }
}
