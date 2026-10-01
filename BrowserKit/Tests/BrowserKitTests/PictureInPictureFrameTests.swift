import Foundation
import Testing
import WebKit
@testable import BrowserKit

/// §18.4a: Picture in Picture reaches a video in an embedded player — the
/// frames that have one say so, and a frame that has gone leaves the list.
@Suite("Picture in Picture in frames (§18.4a)")
@MainActor
struct PictureInPictureFrameTests {

    private func page(frame: String) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "luna-pip-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try "<p>article</p><iframe src=\"player.html\"></iframe>"
            .write(to: folder.appending(path: "index.html"), atomically: true, encoding: .utf8)
        try frame.write(to: folder.appending(path: "player.html"), atomically: true, encoding: .utf8)
        return folder.appending(path: "index.html")
    }

    private func loaded(_ url: URL) async throws -> TabController {
        let controller = TabController(id: UUID(), dataStore: .nonPersistent())
        controller.activate()
        controller.load(url)
        for _ in 0..<100 where controller.state.isLoading || controller.state.url != url {
            try await Task.sleep(for: .milliseconds(100))
        }
        return controller
    }

    @Test func aFrameWithAVideoSaysSo() async throws {
        let controller = try await loaded(try page(frame: "<video></video>"))
        for _ in 0..<30 where controller.videoFrames.isEmpty { try await Task.sleep(for: .milliseconds(100)) }
        #expect(controller.videoFrames.count == 1)
        #expect(controller.videoFrames.first?.isMainFrame == false)
    }

    @Test func aFrameWithoutOneDoesNot() async throws {
        let controller = try await loaded(try page(frame: "<p>no player here</p>"))
        try await Task.sleep(for: .milliseconds(500))
        #expect(controller.videoFrames.isEmpty)
    }

    /// The toggle asks the frame, finds nothing that can float, says so — and a
    /// frame the page has since removed is dropped from the list on the way.
    @Test func aRemovedFrameLeavesTheList() async throws {
        let controller = try await loaded(try page(frame: "<video></video>"))
        for _ in 0..<30 where controller.videoFrames.isEmpty { try await Task.sleep(for: .milliseconds(100)) }
        #expect(controller.videoFrames.count == 1)

        var answer: PictureInPictureAnswer?
        controller.togglePictureInPicture { answer = $0 }
        for _ in 0..<30 where answer == nil { try await Task.sleep(for: .milliseconds(100)) }
        #expect(answer == .noVideo)

        _ = try await controller.webView?.evaluateJavaScript("document.querySelector('iframe').remove(); 0")
        answer = nil
        controller.togglePictureInPicture { answer = $0 }
        for _ in 0..<30 where answer == nil { try await Task.sleep(for: .milliseconds(100)) }
        #expect(answer == .noVideo)
        #expect(controller.videoFrames.isEmpty, "a removed frame stayed on the list")
    }
}
