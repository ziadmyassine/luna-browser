import Foundation
import WebKit

// Adapted from Search's ExtensionShims.swift (github.com/driceroland/Search),
// MIT License, Copyright (c) 2026 Office Commun; the full notice is at the top
// of Resources/ExtensionShim.js.

/// What the shim asks of the browser that BrowserKit cannot answer from the
/// store or the system. `BrowserSession` is the implementation; until it is
/// set, those calls fail the way Chrome answers an API it does not have.
@MainActor
public protocol ExtensionServices: AnyObject {
    /// The address the default search engine gives for `text`, or nil for text
    /// that is not a search.
    func extensionSearchURL(for text: String) -> URL?
    /// Starts a download in `spaceID`, named `filename` when one is given.
    func extensionDownload(_ url: URL, filename: String?, inSpace spaceID: UUID) async throws -> ExtensionDownload
    /// The Space's downloads, oldest first.
    func extensionDownloads(inSpace spaceID: UUID) -> [ExtensionDownload]
    func extensionRevealDownload(_ id: UUID)
    func extensionOpenDownload(_ id: UUID)
    func extensionShowDownloadsFolder()
    /// Moves a tab to `index` among the Space's tabs as extensions see them.
    func extensionMoveTab(_ id: UUID, to index: Int)
    /// Puts a tab to sleep, as hibernating does; the tab stays open.
    func extensionDiscardTab(_ id: UUID)
    /// The group a tab is in, if any.
    func extensionGroupID(ofTab id: UUID) -> UUID?
    func extensionGroups(inSpace spaceID: UUID) -> [TabGroup]
    /// Puts `tabs` into `group`, or into a new group when it is nil; returns the group.
    func extensionGroup(_ tabs: [UUID], into group: UUID?, inSpace spaceID: UUID) -> UUID?
    func extensionUngroup(_ tabs: [UUID])
    func extensionUpdateGroup(_ id: UUID, title: String?, collapsed: Bool?)
    /// Reopens a closed tab of the Space — `id`, or the one closed last.
    func extensionRestoreClosed(_ id: UUID?, inSpace spaceID: UUID) -> ExtensionClosedTab?
}

/// A download as `chrome.downloads` describes one.
public struct ExtensionDownload: Sendable {
    public enum State: String, Sendable { case inProgress = "in_progress", complete, interrupted }

    public let id: UUID
    public let url: URL
    public let path: String
    public let state: State
    public let exists: Bool
    public let startTime: Date
    public let bytesReceived: Int64
    public let totalBytes: Int64

    public init(
        id: UUID, url: URL, path: String, state: State, exists: Bool, startTime: Date, bytesReceived: Int64, totalBytes: Int64
    ) {
        self.id = id
        self.url = url
        self.path = path
        self.state = state
        self.exists = exists
        self.startTime = startTime
        self.bytesReceived = bytesReceived
        self.totalBytes = totalBytes
    }
}

/// A closed tab, for `chrome.sessions`.
public struct ExtensionClosedTab: Sendable {
    public let id: UUID
    public let url: URL
    public let title: String
    public let closedAt: Date

    public init(id: UUID, url: URL, title: String, closedAt: Date) {
        self.id = id
        self.url = url
        self.title = title
        self.closedAt = closedAt
    }
}

/// An answer the shim reads as Chrome's error for a call it cannot make.
struct ExtensionShimRefusal: LocalizedError {
    let why: String
    var errorDescription: String? { why }

    static func unavailable(_ api: String) -> Self { Self(why: "\(api) isn't available in Luna") }
    static func notAsked(_ permission: String) -> Self { Self(why: "The extension never asked for \u{201C}\(permission)\u{201D}") }
}

/// The shim's calls, as the native messages it sends to "luna": `{api, args}`
/// in, `{value}` or `{error}` out. Grouped by family across the
/// `ExtensionShimAnswers+…` files.
extension ExtensionHost {

    /// The families whose answers leave the extension's own origin: what the
    /// browser knows about the person using it. WebKit keeps no permission
    /// object for them, so the gate reads the names the extension's own
    /// manifest asked for. The checks inside the shim are a courtesy to honest
    /// code; the shim runs beside the extension's own, so this one counts.
    static let gatedFamilies: [String: String] = [
        "bookmarks": "bookmarks", "history": "history", "downloads": "downloads", "sessions": "sessions",
        "topSites": "topSites", "browsingData": "browsingData", "readingList": "readingList",
        "userScripts": "userScripts", "identity": "identity", "search": "search", "notifications": "notifications",
        "idle": "idle", "power": "power", "tts": "tts", "tabGroups": "tabGroups", "offscreen": "offscreen"
    ]

    /// Every permission name the shim can stand behind, beyond WebKit's own:
    /// an install prompt should not call these unsupported.
    public static let shimPermissions: Set<String> = [
        "history", "downloads", "downloads.open", "downloads.shelf", "downloads.ui", "tabGroups", "sidePanel",
        "offscreen", "notifications", "tts", "fontSettings", "management", "idle", "power", "privacy", "sessions",
        "topSites", "search", "system.cpu", "system.memory", "system.storage", "system.display", "readingList",
        "contentSettings", "proxy", "favicon", "userScripts", "declarativeContent", "browsingData", "identity",
        "identity.email"
    ]

    func answerShim(_ message: Any, from context: WKWebExtensionContext) async -> Any {
        guard let body = message as? [String: Any], let api = body["api"] as? String else {
            return ["error": "Not a message Luna understands"]
        }
        let args = body["args"] as? [Any] ?? []
        do {
            return ["value": try await runShim(api, args, context: context) ?? NSNull()]
        } catch {
            return ["error": error.localizedDescription]
        }
    }

    /// What this extension asked for: the names in its manifest, before Luna
    /// added its own, and any the shim granted since.
    func shimAllowed(_ context: WKWebExtensionContext) -> Set<String> {
        let id = context.uniqueIdentifier
        let declared = (context.webExtension.manifest["permissions"] as? [Any] ?? []).compactMap { $0 as? String }
        let added = loaded[id].map { ExtensionShim.addedPermissions(in: $0.directory) } ?? []
        return Set(declared).subtracting(added).union(shimGrants(id))
    }

    private func runShim(_ api: String, _ args: [Any], context: WKWebExtensionContext) async throws -> Any? {
        let family = String(api.prefix { $0 != "." })
        if api.hasPrefix("setting.") {
            // A browser setting (chrome.privacy…) belongs to the family its
            // name starts with, and only an extension that asked for that
            // family may read or change it, as in Chrome.
            let name = api.split(separator: ":", maxSplits: 1).dropFirst().first.map(String.init) ?? ""
            let settingFamily = String(name.prefix { $0 != "." })
            guard !settingFamily.isEmpty, shimAllowed(context).contains(settingFamily) else {
                throw ExtensionShimRefusal.notAsked(settingFamily)
            }
            return shimSetting(api, args.first as? [String: Any] ?? [:], extensionID: context.uniqueIdentifier)
        }
        // The one call in a family WebKit owns whose permission guards reading
        // a tab rather than moving one; WebKit keeps that permission.
        if api == "tabs.describe", !context.hasPermission(.tabs) { throw ExtensionShimRefusal.notAsked("tabs") }
        if let needed = Self.gatedFamilies[family], !shimAllowed(context).contains(needed) {
            throw ExtensionShimRefusal.notAsked(needed)
        }
        if let answer = try await answerExtensionFamily(api, args, context: context) { return answer.value }
        if let answer = try await answerDeviceFamily(api, args, context: context) { return answer.value }
        if let answer = try await answerBrowserFamily(api, args, context: context) { return answer.value }
        throw ExtensionShimRefusal.unavailable(api)
    }
}

/// A family handler's answer: nil when the call is not one of its own, so the
/// next family is asked. A call that is its own and answers nothing is
/// `ShimAnswer(nil)`.
struct ShimAnswer {
    nonisolated(unsafe) let value: Any?
    init(_ value: Any?) { self.value = value }
}
