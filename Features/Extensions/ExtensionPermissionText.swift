//
//  ExtensionPermissionText.swift
//  Luna
//
//  What an extension may do, in words a person reads: the install prompt, a
//  runtime request and an extension's card in Settings all say it this way.
//
//  WebKit's own strings are manifest keys — `tabs`, `<all_urls>`,
//  `declarativeNetRequest` — and a prompt that lists those asks the user to
//  consent to vocabulary. The sentences follow Chrome's install warnings where
//  Chrome has one, because that is the wording an extension's own listing was
//  written against. A permission Chrome does not warn about is left out of the
//  list, as it is there: `storage` and `alarms` are not something to consent to.
//

import Foundation

enum ExtensionPermissionText {

    /// One line per thing the extension could do, most far-reaching first.
    /// Sites come before permissions, because "every website" is the line that
    /// matters most.
    static func lines(permissions: [String], hostPatterns: [String]) -> [String] {
        var lines: [String] = []
        if let sites = sites(hostPatterns) { lines.append(sites) }
        var seen = Set<String>()
        for permission in permissions {
            guard let line = sentence(for: permission), seen.insert(line).inserted else { continue }
            lines.append(line)
        }
        return lines
    }

    /// The patterns as one line: every website, a handful by name, or a count.
    static func sites(_ patterns: [String]) -> String? {
        guard !patterns.isEmpty else { return nil }
        if patterns.contains(where: isEveryWebsite) {
            return String(localized: "Read and change your data on every website")
        }
        let hosts = orderedHosts(patterns)
        switch hosts.count {
        case 0: return String(localized: "Read and change your data on some websites")
        case 1: return String(localized: "Read and change your data on \(hosts[0])")
        case 2: return String(localized: "Read and change your data on \(hosts[0]) and \(hosts[1])")
        default:
            return String(localized: "Read and change your data on \(hosts[0]), \(hosts[1]) and \(hosts.count - 2) more")
        }
    }

    /// Short, for a card's subtitle: where it runs, not what it does there.
    static func siteSummary(_ patterns: [String]) -> String {
        if patterns.isEmpty { return String(localized: "No website access") }
        if patterns.contains(where: isEveryWebsite) { return String(localized: "Every website") }
        let count = orderedHosts(patterns).count
        return count == 1 ? orderedHosts(patterns)[0] : String(localized: "\(count) websites")
    }

    static func isEveryWebsite(_ pattern: String) -> Bool {
        ["<all_urls>", "*://*/*", "http://*/*", "https://*/*", "*://*/"].contains(pattern)
    }

    /// `*://*.example.com/*` reads as `example.com`.
    private static func orderedHosts(_ patterns: [String]) -> [String] {
        var hosts: [String] = []
        for pattern in patterns {
            guard let schemeEnd = pattern.range(of: "://") else { continue }
            var host = String(pattern[schemeEnd.upperBound...].prefix { $0 != "/" })
            if host.hasPrefix("*.") { host.removeFirst(2) }
            guard !host.isEmpty, host != "*", !hosts.contains(host) else { continue }
            hosts.append(host)
        }
        return hosts
    }

    private static func sentence(for permission: String) -> String? {
        sentences.first { $0.keys.contains(permission) }?.text
    }

    private static let sentences: [(keys: Set<String>, text: String)] = [
        (["tabs", "webNavigation", "declarativeNetRequestFeedback"], String(localized: "Read your browsing history")),
        (["history"], String(localized: "Read and change your browsing history")),
        (["bookmarks"], String(localized: "Read and change your bookmarks")),
        (["declarativeNetRequest", "declarativeNetRequestWithHostAccess", "webRequestBlocking"],
         String(localized: "Block content on any page")),
        (["clipboardRead"], String(localized: "Read what you copy and paste")),
        (["clipboardWrite"], String(localized: "Change what you copy and paste")),
        (["nativeMessaging"], String(localized: "Talk to apps on this Mac that work with it")),
        (["notifications"], String(localized: "Show notifications")),
        (["geolocation"], String(localized: "See where you are")),
        (["downloads"], String(localized: "Manage your downloads")),
        (["cookies"], String(localized: "Read and change cookies on the sites it can reach")),
        (["privacy"], String(localized: "Change your privacy settings")),
        (["topSites"], String(localized: "See the sites you visit most")),
        (["management"], String(localized: "Manage your other extensions"))
    ]
}

/// A Chrome Web Store link, or a bare id, turned into the id the store knows
/// the extension by: 32 letters from `a` to `p`.
enum ExtensionWebStoreLink {

    static func id(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidates = [trimmed] + (URL(string: trimmed)?.pathComponents.reversed() ?? [])
        return candidates.first(where: isID)
    }

    static func isID(_ text: String) -> Bool {
        text.count == 32 && text.allSatisfy { ("a"..."p").contains($0) }
    }
}
