//
//  ControlService+Page.swift
//  Luna
//
//  Luna Control's page tools: each one a call into `ControlScripts` through
//  `callAsyncJavaScript`, except the pictures, which are `ControlCapture`'s.
//
//  None of it needs the window on screen, key, or in front. The web view may
//  be in no window at all — a tab the user is not looking at has been taken
//  out of the content card — and WebKit loads, runs script and draws a
//  snapshot for it all the same, measured on macOS 26 with a windowless view.
//  All it needs is a size, which `size(_:in:)` gives it.
//

import AppKit
import BrowserKit
import LunaControl
import WebKit

extension ControlService {

    /// How long a navigation is waited for before the call returns anyway.
    private static let loadTimeout: Duration = .seconds(20)

    func run(_ command: ControlCommand, in webView: WKWebView, controller: TabController) async throws -> ControlResult {
        if let session { size(webView, in: session) }
        // Every call, so the recorder is there from the first touch of each
        // new document on. Refused on pages with no script, which is fine.
        _ = try? await webView.callAsyncJavaScript(ControlScripts.consoleInstall, arguments: [:], in: nil, contentWorld: .page)
        await watchNetwork(of: controller, in: webView)
        if let result = try await trustedInput(command, in: webView) { return result }
        if let result = try await viaLibrary(command, in: webView) { return result }
        switch command {
        case let .navigate(navigation):
            return await navigate(navigation, controller: controller, webView: webView)
        case .screenshot, .gif:
            return try await capture(command, in: webView, tab: controller.id)
        case let .javascript(code):
            let value = try await webView.callAsyncJavaScript(
                ControlScripts.javascript, arguments: ["args": ["code": code]], in: nil, contentWorld: .page
            )
            return .text(value as? String ?? "undefined")
        case let .console(pattern, onlyErrors, clear):
            return try await readConsole(in: webView, pattern: pattern, onlyErrors: onlyErrors, clear: clear)
        case let .upload(ref, sources):
            // Read here, after the gate: the user approved these paths, and
            // the guard checks the files as they are now, not as they were.
            let denied = ControlUpload.deniedPaths(bundleIdentifier: Bundle.main.bundleIdentifier ?? "dk.novapps.luna")
            let files = try ControlUpload.resolve(sources, denied: denied).map {
                ["name": $0.name, "mimeType": $0.mimeType, "data": $0.data.base64EncodedString()]
            }
            return try await acting("upload", in: webView, ["ref": ref, "files": files])
        case let .network(pattern, includeBodies, clear):
            return try await readNetwork(of: controller, in: webView, pattern: pattern, includeBodies: includeBodies, clear: clear)
        default:
            return .error("Not a page tool.")
        }
    }

    /// A command the library carries out, or nil for one it does not.
    private func viaLibrary(_ command: ControlCommand, in webView: WKWebView) async throws -> ControlResult? {
        guard let (operation, args, acts) = Self.libraryCall(for: command) else { return nil }
        var result = acts
            ? try await acting(operation, in: webView, args)
            : .text(try await library(operation, in: webView, args))
        if command.isInput, case let .text(said)? = result.content.first {
            result.content[0] = .text(said + " (trusted: false)")
        }
        return result
    }

    private func readConsole(in webView: WKWebView, pattern: String?, onlyErrors: Bool, clear: Bool) async throws
        -> ControlResult {
        let value = try await webView.callAsyncJavaScript(
            ControlScripts.consoleRead,
            arguments: ["args": ["pattern": pattern as Any, "onlyErrors": onlyErrors, "clear": clear]],
            in: nil,
            contentWorld: .page
        )
        let text = value as? String ?? ""
        return .text(text.isEmpty ? "Nothing has been logged since Luna Control first touched this page." : text)
    }

    /// What acting would set off, from the element the call names (see
    /// `ControlRisk`), and the address of the link it lands on. Nothing for a
    /// call with no element — a navigation, a script — or a page the library
    /// cannot run in.
    func inspect(_ command: ControlCommand, tab id: UUID, in session: BrowserSession) async
        -> (Set<ControlRisk>, URL?) {
        let calls = command.inspections
        guard !calls.isEmpty, let webView = session.wakeForControl(id)?.webView else { return ([], nil) }
        size(webView, in: session)
        var risks: Set<ControlRisk> = []
        var href: URL?
        for args in calls {
            guard let json = try? await library("inspect", in: webView, args.mapValues(\.foundation)),
                  let facts = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] else { continue }
            risks.formUnion((facts["risks"] as? [String] ?? []).compactMap(ControlRisk.init(rawValue:)))
            href = href ?? (facts["href"] as? String).flatMap(URL.init(string:))
        }
        return (risks, href)
    }

    private func navigate(
        _ navigation: ControlCommand.Navigation,
        controller: TabController,
        webView: WKWebView
    ) async -> ControlResult {
        switch navigation {
        case let .url(url): controller.load(url)
        case .back: controller.goBack()
        case .forward: controller.goForward()
        case .reload: controller.reload()
        }
        await settle(webView)
        return .text("Loaded \(webView.title ?? "") — \(webView.url?.absoluteString ?? "")")
    }

    /// The library operation behind a command, its arguments, and whether
    /// it acts on the page — and so may start a navigation worth waiting for.
    private static func libraryCall(for command: ControlCommand) -> (String, [String: Any], acts: Bool)? {
        // swiftlint:disable:previous cyclomatic_complexity
        switch command {
        case let .readPage(interactiveOnly, ref, maxDepth):
            ("readPage", ["interactiveOnly": interactiveOnly, "maxDepth": maxDepth, "ref": ref as Any], false)
        case .pageText:
            ("pageText", [:], false)
        case let .find(query):
            ("find", ["query": query], false)
        case let .scroll(direction, amount, target):
            ("scroll", (target.map(arguments(for:)) ?? [:]).merging(["direction": direction.rawValue, "amount": amount]) { $1 },
             false)
        case let .click(target, clickCount, button, modifiers, _):
            ("click", arguments(for: target).merging([
                "clickCount": clickCount, "button": [.left: 0, .middle: 1, .right: 2][button] ?? 0,
                "modifiers": [(ControlInput.Modifiers.command, "meta"), (.control, "ctrl"), (.option, "alt"), (.shift, "shift")]
                    .filter { modifiers.contains($0.0) }.map(\.1)
            ]) { $1 }, true)
        case let .type(text, ref, _):
            ("type", ["text": text, "ref": ref as Any], true)
        case let .key(keys, times, _):
            ("key", ["keys": Array(repeating: keys, count: times).joined(separator: " ")], true)
        case let .hover(target):
            ("hover", arguments(for: target), false)
        case let .drag(from, to, _):
            ("drag", ["from": arguments(for: from), "to": arguments(for: to)], true)
        case let .fill(ref, value):
            ("fill", ["ref": ref, "value": value.foundation], true)
        default:
            nil
        }
    }

    /// Runs one of the library's operations and hands back what it said.
    func library(_ operation: String, in webView: WKWebView, _ args: [String: Any]) async throws -> String {
        // `callAsyncJavaScript` turns `NSNull` into `null` and leaves a
        // missing key `undefined`; the library tests for `undefined`.
        let present = args.filter { !($0.value is NSNull) && !Self.isNil($0.value) }
        let value = try await webView.callAsyncJavaScript(
            ControlScripts.call(operation), arguments: ["args": present], in: nil, contentWorld: ControlCapture.world
        )
        return value as? String ?? ""
    }

    /// An operation that may start a navigation — a link, a submit, Enter —
    /// which the call waits out, so the model's next read sees the new page.
    private func acting(_ operation: String, in webView: WKWebView, _ args: [String: Any]) async throws -> ControlResult {
        let said = try await library(operation, in: webView, args)
        try? await Task.sleep(for: .milliseconds(300))
        if webView.isLoading {
            await settle(webView)
            return .text(said + "\nThe page navigated to \(webView.url?.absoluteString ?? "").")
        }
        return .text(said)
    }

    /// Waits for the tab to stop loading, up to `loadTimeout`. Polls, because
    /// the navigation delegate is `TabController`'s and has one owner.
    func settle(_ webView: WKWebView) async {
        try? await Task.sleep(for: .milliseconds(100))
        let deadline = ContinuousClock.now + Self.loadTimeout
        while webView.isLoading, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    /// Gives a web view that is in no window the size of the page area it
    /// would have on screen. A cold tab's view is built at zero size, which
    /// lays the page out for a viewport nobody has.
    func size(_ webView: WKWebView, in session: BrowserSession) {
        guard webView.window == nil, webView.frame.width < 2 || webView.frame.height < 2 else { return }
        webView.frame = NSRect(origin: .zero, size: pageSize(in: session))
    }

    func pageSize(in session: BrowserSession) -> NSSize {
        session.hostWindow?.contentLayoutRect.size ?? NSSize(width: 1280, height: 800)
    }

    static func arguments(for target: ControlCommand.Target) -> [String: Any] {
        switch target {
        case let .ref(ref): ["ref": ref]
        case let .point(x, y): ["x": x, "y": y]
        }
    }

    private static func isNil(_ value: Any) -> Bool {
        if case Optional<Any>.none = value { return true }
        return false
    }
}

private extension ControlCommand {
    /// The calls that report whether their input was trusted.
    var isInput: Bool {
        switch self {
        case .click, .type, .key, .hover, .drag: true
        default: false
        }
    }
}

private extension JSONValue {
    /// What `callAsyncJavaScript` takes as an argument.
    var foundation: Any {
        switch self {
        case .null: NSNull()
        case let .bool(value): value
        case let .int(value): value
        case let .double(value): value
        case let .string(value): value
        case let .array(values): values.map(\.foundation)
        case let .object(values): values.mapValues(\.foundation)
        }
    }
}
