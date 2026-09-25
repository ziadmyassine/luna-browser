//
//  ExtensionPrompts.swift
//  Luna
//
//  §16.3's two questions: "add this extension?" and, later, "let it do more?".
//
//  Both are the system's alert, on the window the user is looking at. It is
//  the one surface every Mac user already reads as "an app is asking me for
//  something", and consent is not the place to be novel. What Luna adds is the
//  wording (`ExtensionPermissionText`) and the extension's own icon, so the
//  prompt is plainly about that extension and not about Luna.
//

import AppKit
import BrowserKit

@MainActor
enum ExtensionInstallPrompt {

    /// Whether the user said yes to installing `request` in the Space named.
    static func run(
        _ request: ExtensionInstallRequest,
        spaceName: String,
        on window: NSWindow?
    ) async -> Bool {
        let details = request.details
        let alert = NSAlert()
        alert.icon = details.iconData.flatMap(NSImage.init(data:)) ?? ExtensionsSymbol.image
        alert.messageText = request.isUpdate
            ? String(localized: "Update “\(details.name)”?")
            : String(localized: "Add “\(details.name)”?")
        alert.informativeText = informativeText(for: details, spaceName: spaceName)
        alert.addButton(withTitle: request.isUpdate ? String(localized: "Update") : String(localized: "Add Extension"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        guard await answer(alert, on: window) == .alertFirstButtonReturn else { return false }
        return true
    }

    static func informativeText(for details: ExtensionDetails, spaceName: String) -> String {
        var parts: [String] = []
        let lines = ExtensionPermissionText.lines(permissions: details.permissions, hostPatterns: details.hostPatterns)
        if lines.isEmpty {
            parts.append(String(localized: "It asks for no access to your data."))
        } else {
            parts.append(String(localized: "It will be able to:") + "\n" + lines.map { "• \($0)" }.joined(separator: "\n"))
        }
        parts.append(String(localized: "It will run in \(spaceName). You can turn it on in other Spaces in Settings."))
        if !details.unsupportedPermissions.isEmpty {
            let missing = details.unsupportedPermissions.joined(separator: ", ")
            parts.append(String(localized: "Luna does not support some of what it uses (\(missing)), so parts of it may not work."))
        }
        return parts.joined(separator: "\n\n")
    }

    /// A sheet when there is a window to hang it on, a modal alert when not.
    static func answer(_ alert: NSAlert, on window: NSWindow?) async -> NSApplication.ModalResponse {
        guard let window, window.isVisible else { return alert.runModal() }
        return await withCheckedContinuation { continuation in
            alert.beginSheetModal(for: window) { continuation.resume(returning: $0) }
        }
    }
}

@MainActor
enum ExtensionAccessPrompt {

    /// An extension asking at runtime for more than it was given. Everything
    /// or nothing: a checklist of manifest keys is not a choice anyone can make
    /// well, and the extension has said it needs all of them for what it is
    /// about to do.
    static func ask(_ prompt: ExtensionPermissionPrompt, extensionName name: String) async -> Set<String> {
        let alert = NSAlert()
        alert.icon = ExtensionsSymbol.image
        alert.messageText = String(localized: "“\(name)” wants more access")
        let items = prompt.items.sorted()
        let lines: [String] = switch prompt.kind {
        case .permissions:
            ExtensionPermissionText.lines(permissions: items, hostPatterns: [])
        case .matchPatterns:
            ExtensionPermissionText.sites(items).map { [$0] } ?? []
        case .urls:
            [String(localized: "Read and change your data on \(items.compactMap { URL(string: $0)?.host() }.joined(separator: ", "))")]
        }
        let described = lines.isEmpty ? items : lines
        alert.informativeText = String(localized: "It is asking to:") + "\n" + described.map { "• \($0)" }.joined(separator: "\n")
        alert.addButton(withTitle: String(localized: "Allow"))
        alert.addButton(withTitle: String(localized: "Don’t Allow"))
        let window = NSApp.keyWindow ?? NSApp.mainWindow
        return await ExtensionInstallPrompt.answer(alert, on: window) == .alertFirstButtonReturn ? prompt.items : []
    }
}
