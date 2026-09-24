//
//  ControlService+Capture.swift
//  Luna
//
//  `screenshot`, `gif` and `viewport` on a tab: the pictures themselves are
//  `ControlCapture`'s; this is what the service keeps about them per tab —
//  the last screenshot's scale, the recording — and the agent tab laid out
//  at another size.
//
//  `viewport` sets the frame of a web view in no window, so no window of the
//  user's, and no other tab, changes size. A tab the user shows is pinned to
//  their content card's edges, which ends the override without Luna doing
//  anything.
//

import AppKit
import LunaControl
import WebKit

extension ControlService {

    /// Where `gif` writes, beside the activity log in Luna's Control folder.
    var recordingsFolder: URL { auditURL.deletingLastPathComponent().appending(path: "Recordings", directoryHint: .isDirectory) }

    func capture(_ command: ControlCommand, in webView: WKWebView, tab id: UUID) async throws -> ControlResult {
        switch command {
        case let .screenshot(scale, region):
            let image = try await ControlCapture.image(of: webView, scale: scale, region: region)
            guard let png = ControlCapture.png(image) else { return .error("The screenshot could not be encoded.") }
            // A region is a zoom for reading; only a whole-viewport picture
            // sets the space the next coordinates are read in.
            var said = "\(image.width)×\(image.height)"
            if region == nil {
                shotScales[id] = scale < 1 ? scale : nil
                if scale < 1 { said += " at \(scale)×: give coordinates in this picture's pixels" }
            }
            return ControlResult([.png(png), .text("\(said), \(webView.url?.absoluteString ?? "")")])
        case let .gif(action):
            return try await record(action, in: webView, tab: id)
        default:
            return .error("Not a capture tool.")
        }
    }

    private func record(_ action: ControlCommand.Recording, in webView: WKWebView, tab id: UUID) async throws
        -> ControlResult {
        switch action {
        case .start:
            recordings[id] = ControlRecording()
            await recordFrame(of: webView, tab: id, marks: [])
            return .text("Recording tab \(number(id)): a frame after each call that changes the page. Export when done.")
        case .stop:
            guard recordings[id] != nil else { return .error("Tab \(number(id)) is not being recorded.") }
            recordings[id]?.isOn = false
            return .text("Paused with \(recordings[id]?.frames.count ?? 0) frames. Export to write them, or start again.")
        case .export:
            guard let frames = recordings[id]?.frames, !frames.isEmpty else {
                return .error("Tab \(number(id)) has no recording. Start one with gif start.")
            }
            let url = recordingsFolder.appending(path: "tab-\(number(id))-\(Int(Date().timeIntervalSince1970)).gif")
            try ControlCapture.writeGIF(frames, to: url)
            recordings[id] = nil
            return .text("Wrote \(frames.count) frames to \(url.path(percentEncoded: false))")
        }
    }

    /// Adds a frame to the tab's recording, if it has one running. Not under
    /// a dialog, which would hold the masking script until it is answered.
    func recordFrame(of webView: WKWebView, tab id: UUID, marks: [CGPoint]) async {
        guard recordings[id]?.isOn == true, dialogs[id] == nil,
              let frame = try? await ControlCapture.frame(of: webView, marks: marks) else { return }
        recordings[id]?.add(frame)
    }

    /// Where a recorded call points, in CSS pixels, read before it runs: a
    /// click may take its element away.
    func marks(for command: ControlCommand, in webView: WKWebView, tab id: UUID) async -> [CGPoint] {
        guard recordings[id]?.isOn == true else { return [] }
        let targets: [ControlCommand.Target] = switch command {
        case let .click(target, _, _, _, _), let .hover(target): [target]
        case let .drag(from, to, _): [from, to]
        default: []
        }
        var points: [CGPoint] = []
        for target in targets {
            if case let .point(x, y) = target {
                points.append(CGPoint(x: x, y: y))
            } else if let json = try? await library("locate", in: webView, Self.arguments(for: target)),
                      let spot = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
                      let x = spot["x"] as? Double, let y = spot["y"] as? Double {
                points.append(CGPoint(x: x, y: y))
            }
        }
        return points
    }

    /// Only a tab in the client's own folder, and only while it is in no
    /// window: on the user's screen its size is their window's.
    func viewport(_ size: ControlCommand.Size?, tab id: UUID?, for client: ControlClient, in session: BrowserSession) async
        -> ControlResult {
        guard let id, let folder = folders[client.displayName], session.tab(id)?.groupID == folder else {
            return .error("viewport changes only tabs you opened, in your folder. Open one with tab_open.")
        }
        guard let webView = session.wakeForControl(id)?.webView else { return .error("That tab could not be woken.") }
        if webView.window is ControlStageWindow {
            return .error("Another call is driving this tab. Wait for it to finish, then retry.")
        }
        guard webView.window == nil, session.activeTabID != id else {
            return .error("The user has this tab on screen, so its size is their window's. Wait until they leave it.")
        }
        let zoom = webView.pageZoom * webView.magnification
        let points = size.map { NSSize(width: CGFloat($0.width) * zoom, height: CGFloat($0.height) * zoom) }
            ?? pageSize(in: session)
        webView.frame = NSRect(origin: .zero, size: points)
        await recordFrame(of: webView, tab: id, marks: [])
        let css = "\(Int((points.width / zoom).rounded()))×\(Int((points.height / zoom).rounded()))"
        return .text(size == nil ? "Tab \(number(id)) is back at \(css)." : "Tab \(number(id)) is laid out at \(css) CSS pixels.")
    }
}
