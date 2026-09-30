import Foundation
import WebKit

/// What WebKit asks a Space's controller. The protocol is `@objc` and all
/// optional, so a misspelt method compiles and is never called (Ora's PR #137
/// had two); every name here is checked against `WKWebExtensionControllerDelegate.h`.
extension ExtensionHost: WKWebExtensionControllerDelegate {

    // MARK: - Windows and tabs

    /// Without this and the next, `tabs.query({})` answers with nothing (§2, Ora).
    /// WebKit wants the focused window first.
    public func webExtensionController(
        _ controller: WKWebExtensionController,
        openWindowsFor extensionContext: WKWebExtensionContext
    ) -> [any WKWebExtensionWindow] {
        let focused = snapshot.focused.map { [$0] } ?? []
        return (focused + snapshot.windows.filter { $0 != snapshot.focused }).map(windowAdapter)
    }

    public func webExtensionController(
        _ controller: WKWebExtensionController,
        focusedWindowFor extensionContext: WKWebExtensionContext
    ) -> (any WKWebExtensionWindow)? {
        snapshot.focused.map(windowAdapter)
    }

    public func webExtensionController(
        _ controller: WKWebExtensionController,
        openNewTabUsing configuration: WKWebExtension.TabConfiguration,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping ((any WKWebExtensionTab)?, (any Error)?) -> Void
    ) {
        let id = openTab(configuration.url, for: extensionContext, activate: configuration.shouldBeActive)
        completionHandler(id.flatMap(tabAdapter), id == nil ? ExtensionError.notAvailable("Opening a tab here") : nil)
    }

    /// Luna's windows are the app's to make, so a new window's pages open as
    /// tabs in this Space and the window holding them is the answer.
    public func webExtensionController(
        _ controller: WKWebExtensionController,
        openNewWindowUsing configuration: WKWebExtension.WindowConfiguration,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping ((any WKWebExtensionWindow)?, (any Error)?) -> Void
    ) {
        let urls = configuration.tabURLs.isEmpty ? [nil] : configuration.tabURLs.map(Optional.some)
        for (index, url) in urls.enumerated() {
            _ = openTab(url, for: extensionContext, activate: index == 0 && configuration.shouldBeFocused)
        }
        completionHandler(primaryWindowAdapter, nil)
    }

    public func webExtensionController(
        _ controller: WKWebExtensionController,
        openOptionsPageFor extensionContext: WKWebExtensionContext,
        completionHandler: @escaping ((any Error)?) -> Void
    ) {
        guard let url = extensionContext.optionsPageURL, openTab(url, for: extensionContext, activate: true) != nil else {
            return completionHandler(ExtensionError.notAvailable("This options page"))
        }
        completionHandler(nil)
    }

    /// An extension's own page loads only in a view built from its context's
    /// configuration (§4), so that is what it is opened with.
    private func openTab(_ url: URL?, for context: WKWebExtensionContext, activate: Bool) -> UUID? {
        let isOwnPage = url.map { $0.scheme == context.baseURL.scheme && $0.host() == context.baseURL.host() } ?? false
        let id = browser?.openExtensionTab(
            url: url,
            inSpace: spaceID,
            configuration: isOwnPage ? context.webViewConfiguration : nil,
            activate: activate
        )
        sync()
        return id
    }

    // MARK: - Prompts

    public func webExtensionController(
        _ controller: WKWebExtensionController,
        promptForPermissions permissions: Set<WKWebExtension.Permission>,
        in tab: (any WKWebExtensionTab)?,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Set<WKWebExtension.Permission>, Date?) -> Void
    ) {
        prompt(.permissions, Set(permissions.map(\.rawValue)), tab, extensionContext) { allowed in
            completionHandler(Set(allowed.map(WKWebExtension.Permission.init(rawValue:))), nil)
        }
    }

    public func webExtensionController(
        _ controller: WKWebExtensionController,
        promptForPermissionMatchPatterns matchPatterns: Set<WKWebExtension.MatchPattern>,
        in tab: (any WKWebExtensionTab)?,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Set<WKWebExtension.MatchPattern>, Date?) -> Void
    ) {
        prompt(.matchPatterns, Set(matchPatterns.map(\.string)), tab, extensionContext) { allowed in
            completionHandler(Set(matchPatterns.filter { allowed.contains($0.string) }), nil)
        }
    }

    public func webExtensionController(
        _ controller: WKWebExtensionController,
        promptForPermissionToAccess urls: Set<URL>,
        in tab: (any WKWebExtensionTab)?,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Set<URL>, Date?) -> Void
    ) {
        prompt(.urls, Set(urls.map(\.absoluteString)), tab, extensionContext) { allowed in
            completionHandler(urls.filter { allowed.contains($0.absoluteString) }, nil)
        }
    }

    /// With no UI, nothing more is granted: WebKit asks Safari-style with
    /// nobody having touched anything, and Chrome never asks there (§2, Search).
    /// An answer the user did give is remembered — URLs excepted, which are
    /// one-off by nature.
    private func prompt(
        _ kind: ExtensionPermissionPrompt.Kind,
        _ items: Set<String>,
        _ tab: (any WKWebExtensionTab)?,
        _ context: WKWebExtensionContext,
        answer: @escaping (Set<String>) -> Void
    ) {
        guard let ui else { return answer([]) }
        let id = context.uniqueIdentifier
        let request = ExtensionPermissionPrompt(
            kind: kind, items: items, extensionID: id, spaceID: spaceID, tabID: (tab as? ExtensionTab)?.id
        )
        Task {
            let allowed = await ui.promptForAccess(request).intersection(items)
            answer(allowed)
            guard kind != .urls, var grants = loaded[id]?.grants else { return }
            let refused = items.subtracting(allowed)
            if kind == .permissions {
                grants.grantedPermissions.formUnion(allowed)
                grants.deniedPermissions = grants.deniedPermissions.union(refused).subtracting(allowed)
            } else {
                grants.grantedPatterns.formUnion(allowed)
                grants.deniedPatterns = grants.deniedPatterns.union(refused).subtracting(allowed)
            }
            loaded[id]?.grants = grants
            onGrantsChanged?(id, grants)
        }
    }

    // MARK: - Actions

    public func webExtensionController(
        _ controller: WKWebExtensionController,
        didUpdate action: WKWebExtension.Action,
        forExtensionContext context: WKWebExtensionContext
    ) {
        ui?.extensionActionDidUpdate(action, extensionID: context.uniqueIdentifier, spaceID: spaceID)
    }

    public func webExtensionController(
        _ controller: WKWebExtensionController,
        presentActionPopup action: WKWebExtension.Action,
        for context: WKWebExtensionContext,
        completionHandler: @escaping ((any Error)?) -> Void
    ) {
        guard let ui else { return completionHandler(ExtensionError.notAvailable("Extension popups")) }
        do {
            try ui.presentPopup(for: action, extensionID: context.uniqueIdentifier, spaceID: spaceID)
            completionHandler(nil)
        } catch {
            completionHandler(error)
        }
    }

    // MARK: - Native messaging (§14.7, docs/EXTENSIONS.md §5)

    /// `runtime.sendNativeMessage`. To "luna": the APIs WebKit lacks, answered
    /// by the shim's other half. To anything else: a Chrome native messaging
    /// host on this Mac, spoken to the way Chrome would.
    public func webExtensionController(
        _ controller: WKWebExtensionController,
        sendMessage message: Any,
        toApplicationWithIdentifier applicationIdentifier: String?,
        for extensionContext: WKWebExtensionContext,
        replyHandler: @escaping (Any?, (any Error)?) -> Void
    ) {
        nonisolated(unsafe) let message = message
        nonisolated(unsafe) let reply = replyHandler
        guard let name = applicationIdentifier, name != ExtensionShim.application else {
            Task { reply(await answerShim(message, from: extensionContext), nil) }
            return
        }
        guard asksForNative(extensionContext) else { return reply(nil, Self.nativeRefusal) }
        let id = extensionContext.uniqueIdentifier
        let native = native
        Task {
            do {
                nonisolated(unsafe) let answer = try await native.send(message, to: name, from: id)
                reply(answer, nil)
            } catch {
                // An extension asking for an app that isn't there, over and
                // over, is answered slowly once it has asked a dozen times in a
                // second, so a retry loop can't swamp Luna.
                let key = id + "\u{2192}" + name, now = Date()
                shim.nativeFailures[key] = (shim.nativeFailures[key] ?? []).filter { now.timeIntervalSince($0) < 1 } + [now]
                if (shim.nativeFailures[key]?.count ?? 0) > Self.nativeRetriesPerSecond { try? await Task.sleep(for: .seconds(1)) }
                reply(nil, error)
            }
        }
    }

    /// `runtime.connectNative`, and the two ports the shim opens to Luna
    /// itself: one for a worker's WebSocket, and one it lets go of at once,
    /// opened only to find what every port shares.
    public func webExtensionController(
        _ controller: WKWebExtensionController,
        connectUsing port: WKWebExtension.MessagePort,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping ((any Error)?) -> Void
    ) {
        switch port.applicationIdentifier {
        case ExtensionSocket.name:
            ExtensionSocket.connect(port, from: extensionContext.uniqueIdentifier)
            completionHandler(nil)
        case ExtensionShim.application:
            completionHandler(nil)
        default:
            guard asksForNative(extensionContext) else { return completionHandler(Self.nativeRefusal) }
            do {
                try native.connect(port, from: extensionContext.uniqueIdentifier)
                completionHandler(nil)
            } catch {
                completionHandler(error)
            }
        }
    }

    static let nativeRetriesPerSecond = 12

    private static var nativeRefusal: ExtensionNative.Refused {
        ExtensionNative.Refused(why: "Access to native messaging requires the nativeMessaging permission.")
    }

    /// Its own manifest asked to talk to apps on this Mac, and the user did not
    /// refuse it: WebKit's grant, which every extension has for the shim's
    /// sake, does not say.
    private func asksForNative(_ context: WKWebExtensionContext) -> Bool {
        let id = context.uniqueIdentifier
        let added = loaded[id].map { ExtensionShim.addedPermissions(in: $0.directory) } ?? []
        let named = context.webExtension.requestedPermissions.union(context.webExtension.optionalPermissions)
        let refused = loaded[id]?.grants.deniedPermissions.contains(WKWebExtension.Permission.nativeMessaging.rawValue) ?? false
        return named.contains(.nativeMessaging) && !added.contains(WKWebExtension.Permission.nativeMessaging.rawValue) && !refused
    }
}
