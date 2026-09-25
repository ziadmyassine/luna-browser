import Foundation
import WebKit

/// What an extension says about itself, in the form an install prompt or a
/// list row shows it. Permissions and patterns are WebKit's own strings.
public struct ExtensionDetails: Sendable, Hashable {
    public let name: String
    public let version: String
    public let summary: String
    /// Everything the prompt must list: required permissions, and every host
    /// pattern including content scripts' `matches` — the one cmux's review
    /// caught missing was `<all_urls>` (docs/EXTENSIONS.md §3.4).
    public let permissions: [String]
    public let hostPatterns: [String]
    /// Asked for later, at runtime, through ``ExtensionUI/promptForAccess(_:)``.
    public let optionalPermissions: [String]
    public let optionalHostPatterns: [String]
    /// In the manifest but unknown to WebKit, which drops them silently (§1).
    /// Worth a line in the prompt: the extension may not work without them.
    public let unsupportedPermissions: [String]
    /// The largest icon the manifest names, as the file's bytes.
    public let iconData: Data?

    @MainActor
    init(_ webExtension: WKWebExtension, directory: URL) {
        let manifest = webExtension.manifest
        name = webExtension.displayName ?? directory.lastPathComponent
        version = webExtension.displayVersion ?? webExtension.version ?? ""
        summary = webExtension.displayDescription ?? ""
        permissions = webExtension.requestedPermissions.map(\.rawValue).sorted()
        hostPatterns = webExtension.allRequestedMatchPatterns.map(\.string).sorted()
        optionalPermissions = webExtension.optionalPermissions.map(\.rawValue).sorted()
        optionalHostPatterns = webExtension.optionalPermissionMatchPatterns.map(\.string).sorted()

        let known = Set(webExtension.requestedPermissions.union(webExtension.optionalPermissions).map(\.rawValue))
        let declared = ["permissions", "optional_permissions"].flatMap { manifest[$0] as? [String] ?? [] }
        // Host patterns may sit in `permissions` in MV2; they are not permissions.
        unsupportedPermissions = Set(declared.filter { !$0.contains(":") && $0 != "<all_urls>" })
            .subtracting(known).sorted()
        iconData = Self.icon(manifest["icons"] as? [String: String], in: directory)
    }

    private static func icon(_ icons: [String: String]?, in directory: URL) -> Data? {
        guard let largest = icons?.max(by: { (Int($0.key) ?? 0) < (Int($1.key) ?? 0) })?.value,
              ExtensionArchive.isSafe(largest)
        else { return nil }
        return try? Data(contentsOf: directory.appending(path: largest))
    }
}

/// An extension unpacked, checked and read, waiting on the user's answer.
/// Hand it back to ``ExtensionManager/install(_:granting:inSpace:)`` or
/// ``ExtensionManager/cancelInstall(_:)``.
public struct ExtensionInstallRequest: Sendable {
    public let id: String
    public let source: ExtensionSource
    public let details: ExtensionDetails
    /// An extension with this id is already installed; this replaces it.
    public let isUpdate: Bool
    let staged: StagedExtension

    /// The answer when the user accepts the prompt as shown.
    public var grantingEverything: ExtensionGrants {
        ExtensionGrants(grantedPermissions: Set(details.permissions), grantedPatterns: Set(details.hostPatterns))
    }
}

/// One installed extension, for a list.
public struct ExtensionInfo: Sendable {
    public let id: String
    public let source: ExtensionSource
    /// Nil when the copy on disk could not be read, which also means it is not running.
    public let details: ExtensionDetails?
    public let enabledSpaces: Set<UUID>
    public let grants: [UUID: ExtensionGrants]
}
