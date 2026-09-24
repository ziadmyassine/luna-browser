import Foundation
import WebKit

/// What the extension host needs from the browser around it. `BrowserSession`
/// is the implementation; the host lives here so it can be tested without one.
@MainActor
public protocol ExtensionBrowser: AnyObject {
    /// The browser windows standing in `space`, in an order that does not
    /// change while they stay, and which of them has keyboard focus, if any does.
    func extensionWindows(inSpace space: UUID) -> (ids: [UUID], focused: UUID?)
    /// The tabs extensions may see in `space`, in list order. Hibernated tabs
    /// are included; a saved row whose page has been closed is not.
    func extensionTabs(inSpace space: UUID) -> [Tab]
    func activeTabID(inWindow window: UUID) -> UUID?
    /// The live controller, or nil for a hibernated tab.
    func controller(for id: UUID) -> TabController?
    func activateTab(_ id: UUID)
    func closeTab(_ id: UUID)
    func loadURL(_ url: URL, inTab id: UUID)
    /// Opens a real tab in `space`. `configuration` is set for an extension's own
    /// page, which loads only in a view built from its context's configuration.
    func openExtensionTab(url: URL?, inSpace space: UUID, configuration: WKWebViewConfiguration?, activate: Bool) -> UUID?
}

/// The decisions the host cannot make without a person. Until the UI sets
/// ``ExtensionManager/ui``, each has a safe answer: prompts deny whatever is not
/// already granted, a popup fails, and action updates go nowhere.
@MainActor
public protocol ExtensionUI: AnyObject {
    /// An action's icon, badge, title or enablement changed.
    func extensionActionDidUpdate(_ action: WKWebExtension.Action, extensionID: String, spaceID: UUID)
    /// WebKit has built the popup's web view and wants it on screen.
    func presentPopup(for action: WKWebExtension.Action, extensionID: String, spaceID: UUID) throws
    /// An extension asked at runtime for more than it was granted. Returns
    /// what the user allowed, in the prompt's own strings.
    func promptForAccess(_ prompt: ExtensionPermissionPrompt) async -> Set<String>
}

/// A runtime request: permission names, match patterns or URLs, never mixed.
public struct ExtensionPermissionPrompt: Sendable {
    public enum Kind: Sendable { case permissions, matchPatterns, urls }

    public let kind: Kind
    public let items: Set<String>
    public let extensionID: String
    public let spaceID: UUID
    public let tabID: UUID?
}

public enum ExtensionError: LocalizedError, Equatable {
    case notAvailable(String)
    case unknownExtension

    public var errorDescription: String? {
        switch self {
        case .notAvailable(let what): "\(what) is not available in Luna yet."
        case .unknownExtension: "That extension is not installed."
        }
    }
}
