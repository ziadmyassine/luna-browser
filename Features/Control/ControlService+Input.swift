//
//  ControlService+Input.swift
//  Luna
//
//  Trusted input: click, type, key and pointer drags through `ControlStage`,
//  so the page sees a person's events rather than script's. Everything else,
//  and these whenever the stage cannot be used, goes as page events through
//  the library (`ControlService+Page.swift`); each result says which with
//  `trusted: true` or `trusted: false`.
//
//  The stage is used only for a tab in no window. A tab on the user's screen
//  gets page events, never the stage, which would take it and their first
//  responder with it; an agent's own tab on screen is refused before this by
//  the gate's takeover check.
//

import AppKit
import LunaControl
import WebKit

extension ControlService {

    /// A trusted result for `command`, or nil when it goes as page events.
    func trustedInput(_ command: ControlCommand, in webView: WKWebView) async throws -> ControlResult? {
        guard webView.window == nil || webView.window is ControlStageWindow else { return nil }
        switch command {
        case let .click(target, count, button, modifiers, true) where button != .middle:
            let spot = try await locate(target, in: webView)
            if let refusal = ControlInput.refusal(routing: spot.route) { return .error(refusal) }
            return try await onStage(webView) { stage in
                try stage.click(at: spot.point, right: button == .right, count: count, modifiers: modifiers)
                return "Clicked \(spot.name)"
            }
        case let .type(text, ref, true):
            let field = try await library("focusEnd", in: webView, ref.map { ["ref": $0] } ?? [:])
            return try await onStage(webView) { stage in
                try await stage.type(ControlInput.keys(typing: text))
                return "Typed into \(field)"
            }
        case let .key(keys, times, true):
            let presses = try keys.split(separator: " ").map { try ControlInput.key(String($0)) }
            return try await onStage(webView) { stage in
                for _ in 0 ..< times { try await stage.type(presses) }
                return "Pressed \(keys)\(times > 1 ? " ×\(times)" : "")"
            }
        case let .drag(from, to, true):
            let start = try await locate(from, in: webView)
            // A draggable element would start a real drag session following
            // the user's pointer; the library synthesises drag and drop.
            guard !start.draggable else { return nil }
            let end = try await locate(to, in: webView)
            return try await onStage(webView) { stage in
                try await stage.drag(from: start.point, to: end.point)
                return "Dragged from \(start.name) to \(end.name)"
            }
        default:
            return nil
        }
    }

    /// Lends the tab to a stage for `body`, with the library's stage mode on
    /// so the page's own menus and pickers stay closed, and waits out a
    /// navigation the input started.
    private func onStage(_ webView: WKWebView, _ body: (ControlStage) async throws -> String) async throws -> ControlResult {
        let stage = try ControlStage(adopting: webView)
        _ = try? await library("stage", in: webView, ["on": true])
        let said: String
        do {
            said = try await body(stage)
            // Long enough for WebKit's resends of unhandled keys to come
            // back while the stage is still up (`ControlStage.absorbs`).
            try? await Task.sleep(for: .milliseconds(300))
        } catch {
            stage.release()
            _ = try? await library("stage", in: webView, ["on": false])
            throw error
        }
        stage.release()
        _ = try? await library("stage", in: webView, ["on": false])
        var text = said + " (trusted: true)"
        if let focus = try? await library("focused", in: webView, [:]), !focus.isEmpty { text += "; focus is on \(focus)" }
        if webView.isLoading {
            await settle(webView)
            text += "\nThe page navigated to \(webView.url?.absoluteString ?? "")."
        }
        return .text(text)
    }

    private struct Spot {
        var point: CGPoint
        var route: String?
        var draggable: Bool
        var name: String
    }

    private func locate(_ target: ControlCommand.Target, in webView: WKWebView) async throws -> Spot {
        let json = try await library("locate", in: webView, Self.arguments(for: target))
        guard let object = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
              let x = object["x"] as? Double, let y = object["y"] as? Double
        else { throw ControlError("Luna could not find where that is on the page.") }
        return Spot(
            point: CGPoint(x: x, y: y), route: object["route"] as? String,
            draggable: object["draggable"] as? Bool ?? false, name: object["name"] as? String ?? ""
        )
    }
}
