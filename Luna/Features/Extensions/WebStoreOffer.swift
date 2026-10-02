//
//  WebStoreOffer.swift
//  Luna
//
//  The hybrid "Add to Luna" on a Chrome Web Store extension's page. The store is
//  sent a Chrome UA (`WebViewFactory.userAgent(for:)`) so Google's own button
//  renders, and a page script (`TabController+WebStore.swift`) relabels it "Add
//  to Luna" and turns its click into our install. When that button can be
//  hijacked this object does nothing visible; when it cannot — a Google
//  redesign, the SPA not yet rendered, a script error — a short timer fires and
//  the toast below offers Add instead. Both paths call one `ExtensionInstaller`
//  endpoint, and the install prompt still asks, so docs/EXTENSIONS.md §3.7
//  holds: nothing a page does installs anything.
//

import AppKit
import BrowserKit
import Combine

@MainActor
final class WebStoreOffer {

    static let shared = WebStoreOffer()

    private var observation: ObservationToken?
    /// The session being watched, for the window `add` and the fallback toast
    /// open on. The observer already holds it; this is for the button-hijack
    /// callbacks, which arrive by tab id alone.
    private weak var session: BrowserSession?
    /// The extension each tab was last offered, so the offer comes once per page
    /// rather than on every title or progress change of it, and no page is
    /// installed twice.
    private var offered: [UUID: String] = [:]
    /// Each tab's pending fallback, cancelled when the hijacked button reports
    /// in or when an install starts.
    private var fallback: [UUID: any Cancellable] = [:]

    /// How long to wait for Google's button to place itself before offering the
    /// toast. A first-render budget for the store's SPA, not a motion timing, so
    /// it is not a `Tokens.Motion` value: measured page loads settle well inside
    /// it, and overshooting only delays a fallback that rarely fires.
    static let fallbackDelay: TimeInterval = 2.5

    /// Seam for tests: how the fallback is scheduled. The default is a cancellable
    /// delayed hop to the main actor; a test swaps in one it fires by hand.
    var schedule: (TimeInterval, @escaping @MainActor () -> Void) -> any Cancellable = { delay, body in
        let task = Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            body()
        }
        return AnyCancellable { task.cancel() }
    }

    /// Seam for tests: how a toast reaches the screen, and how the install runs.
    /// Both default to the real thing and are faked so `WebStoreOfferTests` puts
    /// no UI on screen and starts no installer.
    var present: (PageToast, NSWindow?) -> Void = { toast, window in toast.show(in: window) }
    var install: (URL, NSWindow?, @escaping @MainActor () -> Void) -> Void = { url, window, onInstalled in
        Task { @MainActor in
            let outcome = await ExtensionInstaller.install(webStoreLink: url.absoluteString, window: window)
            PageToast.extensionAdded(outcome)?.show(in: window)
            if case .installed = outcome { onInstalled() }
        }
    }

    /// Seam for tests: whether an extension id is already in. Defaults to the live
    /// register, so a store page the user already has reads "Added" on arrival.
    var isInstalled: (String) -> Bool = { id in
        ExtensionsCenter.shared.installed.contains { $0.id == id }
    }

    func watch(_ session: BrowserSession) {
        self.session = session
        observation = session.addTabStateObserver { [weak self, weak session] id, state in
            guard let self, let session, id == session.activeTabID else { return }
            offer(for: state.url, tab: id, window: session.hostWindow)
        }
    }

    /// The extension id on a store page, or nil for any other address. Both
    /// the store's own host and its old home under chrome.google.com.
    static func extensionID(on url: URL?) -> String? {
        guard let url, url.scheme == "https", let host = url.host()?.lowercased() else { return nil }
        let parts = url.pathComponents
        let onStore = host == "chromewebstore.google.com" && parts.contains("detail")
            || host == "chrome.google.com" && parts.starts(with: ["/", "webstore", "detail"])
        guard onStore, let id = parts.last, ExtensionWebStoreLink.isID(id) else { return nil }
        return id
    }

    /// Reaching a store detail page arms the fallback rather than showing the
    /// toast at once: the hijacked button usually places itself first and cancels
    /// it. Internal, not private, so `WebStoreOfferTests` can drive it with a nil
    /// window and a faked `schedule`.
    func offer(for url: URL?, tab: UUID, window: NSWindow?) {
        guard let url, let id = Self.extensionID(on: url) else {
            offered[tab] = nil
            cancelFallback(tab)
            return
        }
        guard offered[tab] != id, !isInstalled(id) else { return }
        offered[tab] = id
        fallback[tab] = schedule(Self.fallbackDelay) { [weak self] in
            guard let self else { return }
            fallback[tab] = nil
            // The toast only shows when no button was hijacked, so there is no page
            // button to turn to "Added" — the toast says the outcome itself.
            present(PageToast.addExtension { [weak self] in self?.install(url, window, {}) }, window)
        }
    }

    /// The hijacked button placed itself, so the toast is not needed. And if this
    /// page's extension is already in, turn the button straight to "Added" rather
    /// than inviting an add that is already done — the state, not a session flag.
    func buttonReady(url: URL?, tab: UUID, markAdded: @MainActor () -> Void) {
        cancelFallback(tab)
        if let id = Self.extensionID(on: url), isInstalled(id) { markAdded() }
    }

    /// The user pressed the hijacked "Add to Luna" button. The URL is the one
    /// native read from the web view, never one the page sent. `onInstalled` runs
    /// only when the install goes through, to turn that button to "Added".
    func add(url: URL, tab: UUID, onInstalled: @escaping @MainActor () -> Void) {
        cancelFallback(tab)
        install(url, session?.hostWindow, onInstalled)
    }

    private func cancelFallback(_ tab: UUID) {
        fallback[tab]?.cancel()
        fallback[tab] = nil
    }
}

extension PageToast {

    static func addExtension(_ add: @escaping @MainActor () -> Void) -> PageToast {
        PageToast(
            symbol: ExtensionsSymbol.name,
            text: String(localized: "Add this extension to Luna?"),
            actions: [Action(title: String(localized: "Add"), run: add)]
        )
    }

    /// What became of it, or nothing when the prompt was cancelled.
    static func extensionAdded(_ outcome: ExtensionInstaller.Outcome) -> PageToast? {
        switch outcome {
        case let .installed(name): PageToast(symbol: "checkmark", text: String(localized: "Added"), detail: name)
        case let .failed(reason): PageToast(symbol: "exclamationmark.triangle", text: reason)
        case .cancelled: nil
        }
    }
}
