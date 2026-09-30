//
//  WebStoreOffer.swift
//  Luna
//
//  On a Chrome Web Store extension's page, a toast offers to add it to Luna.
//  The page is the store's own and says "Add to Chrome", which in Luna does
//  nothing; the address is all Settings' link field needs, so the toast hands
//  it the same way. Only Luna's toast starts it, and the install prompt still
//  asks, so docs/EXTENSIONS.md §3.7's rule holds: nothing a page does installs
//  anything.
//

import AppKit
import BrowserKit

@MainActor
final class WebStoreOffer {

    static let shared = WebStoreOffer()

    private var observation: ObservationToken?
    /// The extension each tab was last offered, so the toast comes once per
    /// page rather than on every title or progress change of it.
    private var offered: [UUID: String] = [:]

    func watch(_ session: BrowserSession) {
        observation = session.addTabStateObserver { [weak self, weak session] id, state in
            guard let self, let session, id == session.activeTabID else { return }
            offer(for: state.url, tab: id, in: session)
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

    private func offer(for url: URL?, tab: UUID, in session: BrowserSession) {
        guard let url, let id = Self.extensionID(on: url) else {
            offered[tab] = nil
            return
        }
        guard offered[tab] != id, !ExtensionsCenter.shared.installed.contains(where: { $0.id == id }) else { return }
        offered[tab] = id
        let window = session.hostWindow
        PageToast.addExtension {
            Task { @MainActor in
                let outcome = await ExtensionInstaller.install(webStoreLink: url.absoluteString, window: window)
                PageToast.extensionAdded(outcome)?.show(in: window)
            }
        }.show(in: window)
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
