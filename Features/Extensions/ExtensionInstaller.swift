//
//  ExtensionInstaller.swift
//  Luna
//
//  §16.2's two ways in — a Chrome Web Store link, and a file or folder on
//  disk — each ending at the same prompt and the same install.
//
//  Failures come back as a sentence rather than an alert: Settings shows it
//  under the field it came from, where the user is already looking.
//
//  Nothing a page can reach calls this: both start from Luna's own controls,
//  which is docs/EXTENSIONS.md §3.7's rule.
//

import AppKit
import BrowserKit
import UniformTypeIdentifiers

@MainActor
enum ExtensionInstaller {

    enum Outcome: Equatable {
        case installed(name: String)
        case cancelled
        case failed(String)
    }

    /// A store page's address, or the bare id, typed or pasted.
    static func install(webStoreLink text: String, window: NSWindow?) async -> Outcome {
        guard let manager = ExtensionsCenter.shared.manager else { return .failed(notReady) }
        guard let id = ExtensionWebStoreLink.id(from: text) else {
            return .failed(String(localized: "That isn’t a Chrome Web Store link. Copy the address of the extension’s page."))
        }
        return await install(from: { try await manager.prepareInstall(webStoreID: id) }, window: window)
    }

    /// A folder, a `.zip` or a `.crx`, chosen in an open panel.
    static func chooseFile(for window: NSWindow?) async -> Outcome {
        guard let manager = ExtensionsCenter.shared.manager else { return .failed(notReady) }
        let panel = NSOpenPanel()
        panel.message = String(localized: "Choose an extension’s folder, or a .zip or .crx file")
        panel.prompt = String(localized: "Add")
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.folder, .zip] + (UTType(filenameExtension: "crx").map { [$0] } ?? [])
        let response: NSApplication.ModalResponse
        if let window {
            response = await panel.beginSheetModal(for: window)
        } else {
            response = panel.runModal()
        }
        guard response == .OK, let url = panel.url else { return .cancelled }
        return await install(from: { try await manager.prepareInstall(from: url) }, window: window)
    }

    private static var notReady: String { String(localized: "Extensions are still starting. Try again in a moment.") }

    /// Unpacks and reads it, asks, then installs in the Space the front
    /// browser window is showing — docs/EXTENSIONS.md §3.1: a new install runs
    /// in one Space.
    private static func install(from prepare: () async throws -> ExtensionInstallRequest, window: NSWindow?) async -> Outcome {
        guard let session = ExtensionsCenter.shared.session, let manager = ExtensionsCenter.shared.manager else {
            return .failed(notReady)
        }
        let request: ExtensionInstallRequest
        do {
            request = try await prepare()
        } catch {
            return .failed(String(localized: "Luna couldn’t add it: \(error.localizedDescription)"))
        }
        let space = session.activeSpaceID
        let spaceName = session.space(space)?.name ?? String(localized: "this Space")
        guard await ExtensionInstallPrompt.run(request, spaceName: spaceName, on: window) else {
            await manager.cancelInstall(request)
            return .cancelled
        }
        do {
            // Not pinned: the bar is the user's to fill, and the pop-out is
            // where a new one is found.
            try await ExtensionsCenter.shared.install(request, granting: request.grantingEverything, inSpace: space)
            return .installed(name: request.details.name)
        } catch {
            return .failed(String(localized: "Luna couldn’t add “\(request.details.name)”: \(error.localizedDescription)"))
        }
    }
}
