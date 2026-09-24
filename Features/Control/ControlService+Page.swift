//
//  ControlService+Page.swift
//  Luna
//
//  Luna Control's page tools: each one a call into `ControlScripts` through
//  `callAsyncJavaScript`, except the screenshot, which is WebKit's own.
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

    /// Luna Control's own content world: the page cannot see the library's
    /// globals or the ref table, and cannot replace the functions it calls.
    private static let world = WKContentWorld.world(name: "luna-control")

    /// How long a navigation is waited for before the call returns anyway.
    private static let loadTimeout: Duration = .seconds(20)

    func run(_ command: ControlCommand, in webView: WKWebView, controller: TabController) async throws -> ControlResult {
        if let session { size(webView, in: session) }
        // Every call, so the recorder is there from the first touch of each
        // new document on. Refused on pages with no script, which is fine.
        _ = try? await webView.callAsyncJavaScript(ControlScripts.consoleInstall, arguments: [:], in: nil, contentWorld: .page)
        if let (operation, args, acts) = Self.libraryCall(for: command) {
            return acts
                ? try await acting(operation, in: webView, args)
                : .text(try await library(operation, in: webView, args))
        }
        switch command {
        case let .navigate(navigation):
            return await navigate(navigation, controller: controller, webView: webView)
        case .screenshot:
            return try await screenshot(webView)
        case let .javascript(code):
            let value = try await webView.callAsyncJavaScript(
                ControlScripts.javascript, arguments: ["args": ["code": code]], in: nil, contentWorld: .page
            )
            return .text(value as? String ?? "undefined")
        case let .console(pattern, onlyErrors, clear):
            let value = try await webView.callAsyncJavaScript(
                ControlScripts.consoleRead,
                arguments: ["args": ["pattern": pattern as Any, "onlyErrors": onlyErrors, "clear": clear]],
                in: nil,
                contentWorld: .page
            )
            let text = value as? String ?? ""
            return .text(text.isEmpty ? "Nothing has been logged since Luna Control first touched this page." : text)
        case let .upload(ref, sources):
            // Read here, after the gate: the user approved these paths, and
            // the guard checks the files as they are now, not as they were.
            let denied = ControlUpload.deniedFolders(bundleIdentifier: Bundle.main.bundleIdentifier ?? "dk.novapps.luna")
            let files = try ControlUpload.resolve(sources, denied: denied).map {
                ["name": $0.name, "mimeType": $0.mimeType, "data": $0.data.base64EncodedString()]
            }
            return try await acting("upload", in: webView, ["ref": ref, "files": files])
        default:
            return .error("Not a page tool.")
        }
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
        case let .click(target, clickCount):
            ("click", arguments(for: target).merging(["clickCount": clickCount]) { $1 }, true)
        case let .type(text, ref):
            ("type", ["text": text, "ref": ref as Any], true)
        case let .key(keys):
            ("key", ["keys": keys], true)
        case let .fill(ref, value):
            ("fill", ["ref": ref, "value": value.foundation], true)
        default:
            nil
        }
    }

    /// Runs one of the library's operations and hands back what it said.
    private func library(_ operation: String, in webView: WKWebView, _ args: [String: Any]) async throws -> String {
        // `callAsyncJavaScript` turns `NSNull` into `null` and leaves a
        // missing key `undefined`; the library tests for `undefined`.
        let present = args.filter { !($0.value is NSNull) && !Self.isNil($0.value) }
        let value = try await webView.callAsyncJavaScript(
            ControlScripts.call(operation), arguments: ["args": present], in: nil, contentWorld: Self.world
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
        let fallback = NSSize(width: 1280, height: 800)
        webView.frame = NSRect(origin: .zero, size: session.hostWindow?.contentLayoutRect.size ?? fallback)
    }

    /// The viewport at one pixel per CSS pixel, so a point in the picture is
    /// the point `click` takes, whatever the display's scale.
    ///
    /// Card, one-time-code and other secret fields are drawn as dots for the
    /// picture and put back after, so their values are not in it.
    private func screenshot(_ webView: WKWebView) async throws -> ControlResult {
        let configuration = WKSnapshotConfiguration()
        configuration.afterScreenUpdates = true
        // A page this cannot run in — a PDF, an image — has no fields to hide.
        _ = try? await library("mask", in: webView, [:])
        let image: NSImage
        do {
            image = try await webView.takeSnapshot(configuration: configuration)
            _ = try? await library("unmask", in: webView, [:])
        } catch {
            _ = try? await library("unmask", in: webView, [:])
            throw error
        }
        let width = Int(webView.bounds.width.rounded())
        let height = Int(webView.bounds.height.rounded())
        guard width > 0, height > 0, let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return .error("The tab has no size to take a picture of.") }
        bitmap.size = NSSize(width: width, height: height)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        image.draw(in: NSRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.restoreGraphicsState()
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            return .error("The screenshot could not be encoded.")
        }
        return ControlResult([.png(png), .text("\(width)×\(height), \(webView.url?.absoluteString ?? "")")])
    }

    private static func arguments(for target: ControlCommand.Target) -> [String: Any] {
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
