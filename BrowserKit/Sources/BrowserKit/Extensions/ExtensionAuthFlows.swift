import Foundation

// Adapted from Search's ExtensionAuth (github.com/driceroland/Search), MIT
// License, Copyright (c) 2026 Office Commun; the full notice is at the top of
// Resources/ExtensionShim.js.

/// `chrome.identity.launchWebAuthFlow`: a tab for the provider's sign-in, and
/// the moment it tries to go to `https://<id>.chromiumapp.org/`, that address
/// is the answer and the tab goes. `TabController` asks `finish` about every
/// navigation; nothing is ever loaded from chromiumapp.org.
@MainActor
enum ExtensionAuthFlows {

    struct Declined: LocalizedError {
        var errorDescription: String? { "The user did not approve access." }
    }

    private struct Flow {
        let tab: UUID
        let space: UUID
        weak var browser: (any ExtensionBrowser)?
        let finish: (Result<URL, any Error>) -> Void
    }

    private static var waiting: [String: Flow] = [:]
    private static var watches: [String: Timer] = [:]

    /// Nobody finishing a sign-in in this long means it was abandoned: its
    /// address is no longer watched for.
    static let abandonedAfter: TimeInterval = 600

    static func run(_ url: URL, extensionID id: String, inSpace space: UUID, browser: any ExtensionBrowser) async throws -> URL {
        guard ["https", "http"].contains(url.scheme?.lowercased() ?? "") else {
            throw ExtensionShimRefusal(why: "Authorization page could not be loaded.")
        }
        guard let tab = browser.openExtensionTab(url: url, inSpace: space, configuration: nil, activate: true) else {
            throw ExtensionShimRefusal(why: "Authorization page could not be loaded.")
        }
        return try await withCheckedThrowingContinuation { continuation in
            // A second flow from the same extension replaces the first, as in Chrome.
            end(id, with: .failure(Declined()))
            waiting[id] = Flow(tab: tab, space: space, browser: browser) { continuation.resume(with: $0) }
            let started = Date()
            // Closing the tab is saying no.
            watches[id] = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                MainActor.assumeIsolated {
                    guard let flow = waiting[id], flow.tab == tab else { return }
                    let open = flow.browser?.extensionTabs(inSpace: flow.space).contains { $0.id == tab } ?? false
                    if !open || Date().timeIntervalSince(started) > abandonedAfter { end(id, with: .failure(Declined())) }
                }
            }
        }
    }

    /// True when `url` is an extension's sign-in coming back in the tab that
    /// began it, which is then handed over and never loaded. Any page can go
    /// to an address shaped like one of these, and what it carries would be
    /// the flow's answer: only the flow's own tab may finish it.
    static func finish(_ url: URL, fromTab tab: UUID) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host()?.lowercased(), host.hasSuffix(suffix) else { return false }
        let id = String(host.dropLast(suffix.count))
        guard let flow = waiting[id], flow.tab == tab else { return false }
        end(id, with: .success(url))
        flow.browser?.closeTab(tab)
        return true
    }

    private static let suffix = ".chromiumapp.org"

    private static func end(_ id: String, with result: Result<URL, any Error>) {
        watches.removeValue(forKey: id)?.invalidate()
        waiting.removeValue(forKey: id)?.finish(result)
    }
}
