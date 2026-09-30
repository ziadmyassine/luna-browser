import Foundation
import IOKit.pwr_mgt
import WebKit

// Adapted from Search's ExtensionShims.swift (github.com/driceroland/Search),
// MIT License, Copyright (c) 2026 Office Commun; the full notice is at the top
// of Resources/ExtensionShim.js.

/// What the shim's answers remember about each extension in one Space while
/// Luna runs. What has to outlive a launch — settings, granted permissions —
/// is in the user's defaults instead.
@MainActor
final class ExtensionShimState {
    /// The last things that went wrong inside each extension, newest last.
    var errors: [String: [String]] = [:]
    /// Keep-awake assertions, one per extension that asked.
    var keepAwake: [String: IOPMAssertionID] = [:]
    /// Loaded at least once since launch, and loaded again since.
    var loadsThisRun: Set<String> = []
    var loadedBefore: Set<String> = []
    /// When the extension's button was last pressed: a permission request
    /// WebKit lost the click for is honoured only just after one.
    var lastPress: [String: Date] = [:]
    /// Recent failed native messages, per extension and host.
    var nativeFailures: [String: [Date]] = [:]
    /// Chrome's ids are numbers where Luna's are UUIDs: one per group and per
    /// download, given the first time an extension sees it.
    var groupNumbers: [UUID: Int] = [:]
    var downloadNumbers: [UUID: Int] = [:]
    /// The downloads each extension started, the only ones it may open.
    var ownDownloads: [String: Set<UUID>] = [:]
    /// The side panel each extension set, and whether its button opens it.
    var panelPath: [String: String] = [:]
    var panelOnPress: Set<String> = []
    /// Each extension's offscreen document, from the moment it is asked for:
    /// two made at once must not leave two pages alive.
    var offscreen: [String: ExtensionOffscreen] = [:]

    static let errorsKept = 50

    func note(_ error: String, for id: String) {
        errors[id, default: []].append(error)
        if errors[id, default: []].count > Self.errorsKept { errors[id]?.removeFirst() }
    }

    /// Lets go of what an extension kept going outside WebKit.
    func release(_ id: String) {
        if let assertion = keepAwake.removeValue(forKey: id) { IOPMAssertionRelease(assertion) }
        offscreen[id]?.close(because: ExtensionOffscreen.Refused(why: "The extension was unloaded."))
    }
}

extension ExtensionHost {

    // MARK: - Remembered across launches

    private static func defaultsKey(_ kind: String, _ id: String) -> String { "luna.extensions.\(kind).\(id)" }

    /// Permissions the shim answers for that the user granted after install.
    func shimGrants(_ id: String) -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: Self.defaultsKey("shimGrants", id)) ?? [])
    }

    func setShimGrants(_ names: Set<String>, for id: String) {
        UserDefaults.standard.set(names.sorted(), forKey: Self.defaultsKey("shimGrants", id))
    }

    /// Forgets what the shim kept for an extension being removed.
    static func forgetShimState(of id: String) {
        for kind in ["shimGrants", "settings"] { UserDefaults.standard.removeObject(forKey: defaultsKey(kind, id)) }
    }

    /// chrome.privacy and chrome.proxy: what each extension set, kept across
    /// launches as Chrome keeps it. Luna acts on none of them — an extension
    /// turning off the browser's own password saving is asking Chrome to step
    /// aside, and Luna's password manager is the user's to turn off.
    func shimSetting(_ api: String, _ details: [String: Any], extensionID id: String) -> Any? {
        let parts = api.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        let name = parts[1]
        let key = Self.defaultsKey("settings", id)
        var mine = UserDefaults.standard.dictionary(forKey: key) ?? [:]
        switch parts[0] {
        case "setting.set":
            mine[name] = details["value"].flatMap { JSONSerialization.isValidJSONObject([$0]) ? $0 : nil }
        case "setting.clear":
            mine[name] = nil
        default:
            let value = mine[name] ?? Self.defaultSetting(name)
            let control = mine[name] != nil ? "controlled_by_this_extension" : "controllable_by_this_extension"
            return ["value": value ?? NSNull(), "levelOfControl": control]
        }
        UserDefaults.standard.set(mine, forKey: key)
        return nil
    }

    private static func defaultSetting(_ name: String) -> Any? {
        switch name {
        case "privacy.network.webRTCIPHandlingPolicy": "default"
        case "privacy.websites.doNotTrackEnabled", "privacy.websites.adMeasurementEnabled",
             "privacy.websites.fledgeEnabled", "privacy.websites.topicsEnabled",
             "privacy.services.safeBrowsingExtendedReportingEnabled": false
        case "proxy.settings": ["mode": "system"]
        default: true
        }
    }

    // MARK: - The extension itself

    func answerExtensionFamily(_ api: String, _ args: [Any], context: WKWebExtensionContext) async throws -> ShimAnswer? {
        switch String(api.prefix { $0 != "." }) {
        case "background", "debug", "clients", "runtime": try await answerWorker(api, args, context: context)
        case "offscreen": try await answerOffscreen(api, args, context: context)
        case "management": try Self.answerManagement(api, context: context)
        case "permissions": try await answerPermissions(api, args, context: context)
        case "scripting", "userScripts": try answerScripts(api, args, in: try folder(of: context.uniqueIdentifier))
        default: nil
        }
    }

    /// The worker, its errors, and the extension's own pages.
    private func answerWorker(_ api: String, _ args: [Any], context: WKWebExtensionContext) async throws -> ShimAnswer? {
        let id = context.uniqueIdentifier
        switch api {
        case "background.wake":
            return ShimAnswer(await wakeBackground(context))
        // Whether this extension was loaded before in this run of Luna: an
        // "install" then is really a restart (see onInstalled in the script).
        case "background.loadedBefore":
            return ShimAnswer(shim.loadedBefore.contains(id))
        // A page found the worker gone though WebKit believes it runs.
        case "background.revive":
            shim.note("restarted: its worker stopped answering", for: id)
            await recover(id)
            return ShimAnswer(nil)
        case "debug.error":
            shim.note(args.first as? String ?? "?", for: id)
            return ShimAnswer(nil)
        case "clients.pages":
            var pages = ownPages(of: context).map { page in
                ["id": page.id, "url": page.url.absoluteString, "visible": page.visible, "focused": page.visible] as [String: Any]
            }
            // Its offscreen document too, as Chrome lists it.
            if let document = shim.offscreen[id], document.isReady {
                pages.append(["id": "offscreen", "url": document.url.absoluteString, "visible": false, "focused": false])
            }
            return ShimAnswer(pages)
        case "runtime.getContexts":
            return ShimAnswer(contexts(of: context, matching: args.first as? [String: Any] ?? [:]))
        default:
            return nil
        }
    }

    private func answerOffscreen(_ api: String, _ args: [Any], context: WKWebExtensionContext) async throws -> ShimAnswer? {
        let id = context.uniqueIdentifier
        switch api {
        case "offscreen.createDocument":
            try await createOffscreen(args.first as? [String: Any] ?? [:], context: context)
            return ShimAnswer(nil)
        case "offscreen.closeDocument":
            shim.offscreen[id]?.close(because: ExtensionOffscreen.Refused(why: "The offscreen document was closed."))
            return ShimAnswer(nil)
        case "offscreen.hasDocument":
            return ShimAnswer(shim.offscreen[id] != nil)
        case "offscreen.sendMessage":
            guard args.count == 3, let token = args[0] as? String, let sender = args[2] as? [String: Any],
                  let document = shim.offscreen[id]
            else { return ShimAnswer(["handled": false]) }
            return ShimAnswer(try await document.send(args[1], sender: sender, token: token))
        default:
            return nil
        }
    }

    /// Only itself: Luna does not show one extension the others.
    private static func answerManagement(_ api: String, context: WKWebExtensionContext) throws -> ShimAnswer? {
        switch api {
        case "management.getSelf", "management.get": return ShimAnswer(describe(context))
        case "management.getAll": return ShimAnswer([describe(context)])
        case "management.setEnabled", "management.uninstallSelf":
            throw ExtensionShimRefusal(why: "Extensions are turned on and off in Luna's Settings \u{203A} Extensions")
        default: return nil
        }
    }

    private func answerPermissions(_ api: String, _ args: [Any], context: WKWebExtensionContext) async throws -> ShimAnswer? {
        let id = context.uniqueIdentifier
        let names = args.first as? [String] ?? []
        switch api {
        case "permissions.granted":
            return ShimAnswer(shimGrants(id).sorted())
        case "permissions.request":
            return ShimAnswer(try await requestShimPermissions(names, context: context))
        case "permissions.afterClick":
            return ShimAnswer(try await requestAfterPress(names, args.dropFirst().first as? [String] ?? [], context: context))
        case "permissions.remove":
            setShimGrants(shimGrants(id).subtracting(names), for: id)
            return ShimAnswer(true)
        default:
            return nil
        }
    }

    private func answerScripts(_ api: String, _ args: [Any], in folder: URL) throws -> ShimAnswer? {
        let first = args.first
        switch api {
        case "scripting.file":
            let arguments = args.dropFirst().first as? [Any] ?? []
            return ShimAnswer(try Self.scriptingFile(first as? String ?? "", arguments: arguments, in: folder))
        case "userScripts.file":
            return ShimAnswer(try ExtensionUserScripts.file(first as? [String: Any] ?? [:], in: folder))
        case "userScripts.list":
            return ShimAnswer(ExtensionUserScripts.list(in: folder))
        case "userScripts.save":
            try ExtensionUserScripts.save(first as? [[String: Any]] ?? [], in: folder)
            return ShimAnswer(nil)
        case "userScripts.worlds":
            return ShimAnswer(ExtensionUserScripts.worlds(in: folder))
        case "userScripts.world":
            try ExtensionUserScripts.configureWorld(first as? [String: Any] ?? [:], in: folder)
            return ShimAnswer(nil)
        default:
            return nil
        }
    }

    private func createOffscreen(_ spec: [String: Any], context: WKWebExtensionContext) async throws {
        let id = context.uniqueIdentifier
        guard shim.offscreen[id] == nil else {
            throw ExtensionShimRefusal(why: "Only a single offscreen document may be created.")
        }
        guard let path = spec["url"] as? String else { throw ExtensionShimRefusal(why: "No page for the offscreen document") }
        let document = try ExtensionOffscreen.create(path, for: context) { [weak self] gone in
            guard self?.shim.offscreen[gone.extensionID] === gone else { return }
            self?.shim.offscreen[gone.extensionID] = nil
        }
        shim.offscreen[id] = document
        try await document.load()
    }

    private func folder(of id: String) throws -> URL {
        guard let directory = loaded[id]?.directory else { throw ExtensionError.unknownExtension }
        return directory
    }

    /// WebKit sometimes fails to start a worker again after unloading it, and
    /// then never tries again: every message waits for ever. Tried twice more,
    /// then the extension is taken up afresh.
    private func wakeBackground(_ context: WKWebExtensionContext) async -> Any? {
        guard context.webExtension.hasBackgroundContent else { return nil }
        for attempt in 0 ..< 3 {
            if await Self.startBackground(context) { return nil }
            if attempt < 2 { try? await Task.sleep(for: .milliseconds(400)) }
        }
        shim.note("restarted: its worker would not start", for: context.uniqueIdentifier)
        await recover(context.uniqueIdentifier)
        return nil
    }

    /// One of the extension's own pages, as `clients.matchAll` and
    /// `runtime.getContexts` list it.
    struct OwnPage {
        let id: String
        let url: URL
        let visible: Bool
        /// Chrome's context type: POPUP or TAB.
        let type: String
    }

    /// The extension's own pages open in this Space's tabs, and its popup while it is up.
    func ownPages(of context: WKWebExtensionContext) -> [OwnPage] {
        let id = context.uniqueIdentifier
        var pages: [OwnPage] = []
        if let popup = openPopupURL(of: context) { pages.append(OwnPage(id: "popup", url: popup, visible: true, type: "POPUP")) }
        for tab in snapshot.tabs {
            guard let url = browser?.controller(for: tab)?.webView?.url, url.scheme == context.baseURL.scheme,
                  url.host()?.lowercased() == id.lowercased()
            else { continue }
            pages.append(OwnPage(id: tab.uuidString, url: url, visible: tab == snapshot.activeTab && snapshot.focused != nil, type: "TAB"))
        }
        return pages
    }

    private func openPopupURL(of context: WKWebExtensionContext) -> URL? {
        let actions = [context.action(for: nil)] + snapshot.tabs.compactMap { tabAdapter($0) }.map { context.action(for: $0) }
        return actions.lazy.compactMap { $0?.popupWebView?.url }.first
    }

    /// `runtime.getContexts`: its worker, its popup while it is up, its pages
    /// in tabs. Bitwarden asks for these to know where to send its messages.
    private func contexts(of context: WKWebExtensionContext, matching filter: [String: Any]) -> [[String: Any]] {
        let id = context.uniqueIdentifier
        let types = filter["contextTypes"] as? [String]
        let urls = filter["documentUrls"] as? [String]
        var found: [[String: Any]] = []
        func add(_ type: String, _ url: URL?, tab: Int = -1) {
            guard types.map({ $0.contains(type) }) ?? true else { return }
            let address = url?.absoluteString ?? ""
            guard urls.map({ $0.contains(address) }) ?? true else { return }
            found.append([
                "contextType": type, "contextId": "\(id)-\(type)-\(found.count)", "tabId": tab, "windowId": -1,
                "frameId": type == "BACKGROUND" ? -1 : 0, "documentUrl": address,
                "documentOrigin": url.map { "\($0.scheme ?? "")://\($0.host() ?? "")" } ?? "", "incognito": false
            ])
        }
        if context.webExtension.hasBackgroundContent {
            let background = context.webExtension.manifest["background"] as? [String: Any] ?? [:]
            let script = background["service_worker"] as? String ?? background["page"] as? String
            add("BACKGROUND", script.map { context.baseURL.appending(path: $0) })
        }
        for page in ownPages(of: context) { add(page.type, page.url) }
        if let document = shim.offscreen[id]?.context(matching: filter) { found.append(document) }
        return found
    }

    private static func describe(_ context: WKWebExtensionContext) -> [String: Any] {
        let found = context.webExtension
        return [
            "id": context.uniqueIdentifier, "name": found.displayName ?? "", "shortName": found.displayShortName ?? "",
            "version": found.version ?? "", "description": found.displayDescription ?? "", "enabled": true,
            "type": "extension", "installType": "normal", "mayDisable": true, "offlineEnabled": true, "isApp": false,
            "hostPermissions": [String](), "permissions": [String]()
        ]
    }

    // MARK: - Permissions the shim answers for

    /// Those Chrome grants without a word, having nothing to warn of.
    private static let silentPermissions: Set<String> = [
        "tabGroups", "sidePanel", "offscreen", "idle", "power", "fontSettings", "search",
        "system.cpu", "system.memory", "system.display", "favicon"
    ]

    /// As in Chrome, only what the manifest named, required or optional:
    /// what was agreed to at install still describes the extension.
    private func requestShimPermissions(_ wanted: [String], context: WKWebExtensionContext) async throws -> Bool {
        let manifest = context.webExtension.manifest
        let named = Set(["permissions", "optional_permissions"].flatMap { (manifest[$0] as? [Any] ?? []).compactMap { $0 as? String } })
        guard wanted.allSatisfy(named.contains) else {
            throw ExtensionShimRefusal(why: "Only permissions specified in the manifest may be requested.")
        }
        let id = context.uniqueIdentifier
        var allowed = Set(wanted).intersection(Self.silentPermissions)
        let asked = Set(wanted).subtracting(allowed)
        if !asked.isEmpty {
            guard let ui else { return false }
            allowed.formUnion(await ui.promptForAccess(ExtensionPermissionPrompt(
                kind: .permissions, items: asked, extensionID: id, spaceID: spaceID, tabID: nil
            )).intersection(asked))
        }
        setShimGrants(shimGrants(id).union(allowed), for: id)
        return allowed == Set(wanted)
    }

    /// `permissions.request` for WebKit's own permissions and sites, made from
    /// a press on the extension's button whose moment WebKit lost while the
    /// shim filled in the tab it was given. Only within seconds of that press,
    /// once, and only what the manifest names.
    private func requestAfterPress(_ names: [String], _ origins: [String], context: WKWebExtensionContext) async throws -> Bool {
        let id = context.uniqueIdentifier
        guard let pressed = shim.lastPress[id], Date().timeIntervalSince(pressed) < Self.pressWindow else {
            throw ExtensionShimRefusal(why: "Invalid call to permissions.request(). Must be called during a user gesture.")
        }
        shim.lastPress[id] = nil
        let found = context.webExtension
        let wanted = names.map(WKWebExtension.Permission.init(rawValue:))
        let patterns = origins.compactMap { try? WKWebExtension.MatchPattern(string: $0) }
        let places = Set(found.allRequestedMatchPatterns.union(found.optionalPermissionMatchPatterns).map(\.string))
        guard wanted.allSatisfy(found.requestedPermissions.union(found.optionalPermissions).contains),
              patterns.allSatisfy({ places.contains($0.string) })
        else { throw ExtensionShimRefusal(why: "Only permissions specified in the manifest may be requested.") }
        let missing = wanted.filter { context.permissionStatus(for: $0) != .grantedExplicitly }
        let unreached = patterns.filter { context.permissionStatus(for: $0) != .grantedExplicitly }
        guard !missing.isEmpty || !unreached.isEmpty else { return true }
        guard let ui else { return false }
        var grants = loaded[id]?.grants ?? ExtensionGrants()
        if !missing.isEmpty {
            let items = Set(missing.map(\.rawValue))
            let allowed = await ui.promptForAccess(ExtensionPermissionPrompt(
                kind: .permissions, items: items, extensionID: id, spaceID: spaceID, tabID: nil
            )).intersection(items)
            guard allowed == items else { return false }
            grants.grantedPermissions.formUnion(allowed)
            grants.deniedPermissions.subtract(allowed)
        }
        if !unreached.isEmpty {
            let items = Set(unreached.map(\.string))
            let allowed = await ui.promptForAccess(ExtensionPermissionPrompt(
                kind: .matchPatterns, items: items, extensionID: id, spaceID: spaceID, tabID: nil
            )).intersection(items)
            guard allowed == items else { return false }
            grants.grantedPatterns.formUnion(allowed)
            grants.deniedPatterns.subtract(allowed)
        }
        apply(grants, to: id)
        onGrantsChanged?(id, grants)
        return true
    }

    static let pressWindow: TimeInterval = 10

    // MARK: - Files the shim writes

    /// A function sent by an extension page inside a website's frame cannot
    /// survive the JSON message to its worker, so it is written as a file for
    /// WebKit's scripting API, with its JSON arguments.
    static func scriptingFile(_ function: String, arguments: [Any], in folder: URL) throws -> String {
        // A megabyte of source at most: a page gone wrong can't fill the
        // extension's folder with big files.
        guard !function.isEmpty, function.utf8.count <= 1_000_000, JSONSerialization.isValidJSONObject(arguments),
              let data = try? JSONSerialization.data(withJSONObject: arguments),
              let json = String(data: data, encoding: .utf8)
        else { throw ExtensionShimRefusal(why: "Invalid script function or arguments") }
        let source = "(\(function))(...\(json))\n"
        return try ExtensionUserScripts.write(source, prefix: "script-", in: folder)
    }
}
