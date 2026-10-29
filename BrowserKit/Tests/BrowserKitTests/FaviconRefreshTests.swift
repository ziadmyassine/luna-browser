import CoreGraphics
import Foundation
import ImageIO
import Network
import Testing
import UniformTypeIdentifiers
import WebKit
@testable import BrowserKit

/// §4.7: a cached icon is not forever. A page that declares a different icon gets
/// it on that load; the same icon URL is fetched again once the cached copy is
/// `refetchAfter` old, and not before.
@Suite("Favicon refresh (§4.7)")
@MainActor
struct FaviconRefreshTests {

    /// Serves `files` by path and counts what was asked for. Anything else is a 404.
    private final class IconServer: @unchecked Sendable {
        let listener: NWListener
        private let lock = NSLock()
        private var files: [String: Data] = [:]
        private var counts: [String: Int] = [:]

        init() throws {
            listener = try NWListener(using: .tcp, on: .any)
            listener.newConnectionHandler = { [unowned self] connection in
                connection.start(queue: .main)
                connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { request, _, _, _ in
                    let line = request.flatMap { String(data: $0, encoding: .utf8) }?.split(separator: " ")
                    let path = line.map { $0.count > 1 ? String($0[1]) : "" } ?? ""
                    let body = self.answer(path)
                    let head = (body == nil ? "HTTP/1.1 404 Not Found\r\n" : "HTTP/1.1 200 OK\r\nContent-Type: image/png\r\n")
                        + "Content-Length: \(body?.count ?? 0)\r\nConnection: close\r\n\r\n"
                    connection.send(content: Data(head.utf8) + (body ?? Data()), completion: .contentProcessed { _ in
                        connection.cancel()
                    })
                }
            }
            listener.start(queue: .main)
        }

        func serve(_ data: Data?, at path: String) { lock.withLock { files[path] = data } }
        func requests(for path: String) -> Int { lock.withLock { counts[path, default: 0] } }

        private func answer(_ path: String) -> Data? {
            lock.withLock {
                counts[path, default: 0] += 1
                return files[path]
            }
        }
    }

    /// The owner's case: the page moves from `/a.png` to `/b.png`, and the next
    /// load shows B however fresh A is.
    @Test func aPageThatDeclaresANewIconGetsItOnTheNextLoad() async throws {
        let (service, webView, server) = try await makeServiceAndPage()
        let red = try Self.png(red: 1), blue = try Self.png(red: 0)
        server.serve(red, at: "/a.png")
        server.serve(blue, at: "/b.png")

        try await load(href: "/a.png", in: webView, server)
        #expect(await service.fetchFavicon(for: webView, host: host) == FaviconService.png(from: red))

        try await load(href: "/b.png", in: webView, server)
        #expect(await service.fetchFavicon(for: webView, host: host) == FaviconService.png(from: blue))
        #expect(service.favicon(forHost: host) == FaviconService.png(from: blue))
        #expect(service.revision == 1, "the app's image caches are not told the icon changed")
    }

    /// The same URL with new bytes behind it is only noticed once the cache ages,
    /// and until then a load costs no request.
    @Test func theSameIconURLIsFetchedAgainOnceAWeekOld() async throws {
        let (service, webView, server) = try await makeServiceAndPage()
        let red = try Self.png(red: 1), blue = try Self.png(red: 0)
        server.serve(red, at: "/a.png")

        try await load(href: "/a.png", in: webView, server)
        #expect(await service.fetchFavicon(for: webView, host: host) == FaviconService.png(from: red))

        server.serve(blue, at: "/a.png")
        try await load(href: "/a.png", in: webView, server)
        #expect(await service.fetchFavicon(for: webView, host: host) == FaviconService.png(from: red))
        #expect(server.requests(for: "/a.png") == 1, "a fresh icon was fetched again")

        try age(service, by: FaviconService.refetchAfter + 60)
        #expect(await service.fetchFavicon(for: webView, host: host) == FaviconService.png(from: blue))
    }

    /// A refresh that finds nothing keeps the icon the user knows, and does not ask
    /// again on the next load.
    @Test func aFailedRefreshKeepsTheOldIconAndIsNotRetriedEveryLoad() async throws {
        let (service, webView, server) = try await makeServiceAndPage()
        let red = try Self.png(red: 1)
        server.serve(red, at: "/a.png")

        try await load(href: "/a.png", in: webView, server)
        _ = await service.fetchFavicon(for: webView, host: host)

        // A new icon that is not there.
        try await load(href: "/missing.png", in: webView, server)
        #expect(await service.fetchFavicon(for: webView, host: host) == FaviconService.png(from: red))
        try await load(href: "/missing.png", in: webView, server)
        #expect(await service.fetchFavicon(for: webView, host: host) == FaviconService.png(from: red))
        #expect(server.requests(for: "/missing.png") == 1)

        // The old icon, aged, gone from the server.
        server.serve(nil, at: "/a.png")
        try await load(href: "/a.png", in: webView, server)
        try age(service, by: FaviconService.refetchAfter + 60)
        #expect(await service.fetchFavicon(for: webView, host: host) == FaviconService.png(from: red))
        let file = try #require(service.fileURL(for: host))
        let checked = try #require(try file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
        #expect(Date.now.timeIntervalSince(checked) < 60, "the next load would ask again")
    }

    /// An icon cached before Luna saved where icons came from has no URL to differ
    /// from, so it waits for its age rather than every host refetching at once.
    @Test func anIconWithNoSavedURLWaitsForItsAge() async throws {
        let (service, webView, server) = try await makeServiceAndPage()
        let red = try #require(FaviconService.png(from: Self.png(red: 1)))
        try red.write(to: #require(service.fileURL(for: host)))
        server.serve(try Self.png(red: 0), at: "/b.png")

        try await load(href: "/b.png", in: webView, server)
        #expect(await service.fetchFavicon(for: webView, host: host) == red)
        #expect(server.requests(for: "/b.png") == 0)
    }

    // MARK: - Helpers

    /// The page's host. Its `/favicon.ico` fallback is https on port 443, where
    /// nothing listens, so the declared icon is the only one that can arrive.
    private let host = "127.0.0.1"

    private func makeServiceAndPage() async throws -> (FaviconService, WKWebView, IconServer) {
        let directory = URL.temporaryDirectory.appending(path: "luna-favicon-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let server = try IconServer()
        for _ in 0 ..< 250 where server.listener.state != .ready { try await Task.sleep(for: .milliseconds(20)) }
        return (FaviconService(directory: directory), WKWebView(frame: .zero, configuration: configuration), server)
    }

    private func load(href: String, in webView: WKWebView, _ server: IconServer) async throws {
        let port = try #require(server.listener.port)
        let marker = UUID().uuidString
        webView.loadHTMLString(
            "<link rel=\"icon\" href=\"\(href)\"><title>\(marker)</title>",
            baseURL: URL(string: "http://\(host):\(port.rawValue)/")
        )
        for _ in 0 ..< 250 where webView.isLoading || webView.title != marker {
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    private func age(_ service: FaviconService, by interval: TimeInterval) throws {
        let file = try #require(service.fileURL(for: host))
        try FileManager.default.setAttributes(
            [.modificationDate: Date.now.addingTimeInterval(-interval)],
            ofItemAtPath: file.path(percentEncoded: false)
        )
    }

    /// A one-pixel PNG of the given red, so two icons differ in their bytes.
    private static func png(red: CGFloat) throws -> Data {
        let context = try #require(CGContext(
            data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(red: red, green: 0, blue: 1 - red, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        let image = try #require(context.makeImage())
        let output = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return output as Data
    }
}
