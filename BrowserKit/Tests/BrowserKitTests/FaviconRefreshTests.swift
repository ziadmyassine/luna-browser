import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
import WebKit
@testable import BrowserKit

/// §4.7: a cached icon is not forever. A site that changes its icon shows the new
/// one on a visit once the cached copy is `refetchAfter` old, and not before.
@Suite("Favicon refresh (§4.7)")
@MainActor
struct FaviconRefreshTests {

    /// `.invalid` never resolves, so the `/favicon.ico` fallback fails fast and the
    /// page's declared `data:` icon is the only one that can arrive.
    private let host = "icons.invalid"

    @Test func aChangedIconShowsOnceTheCachedOneIsAWeekOld() async throws {
        let (service, webView) = try makeServiceAndPage()
        let red = try Self.png(red: 1), blue = try Self.png(red: 0)

        try await load(icon: red, in: webView)
        #expect(await service.fetchFavicon(for: webView, host: host) == FaviconService.png(from: red))

        // The site changes its icon. A fresh cache answers without asking again.
        try await load(icon: blue, in: webView)
        #expect(await service.fetchFavicon(for: webView, host: host) == FaviconService.png(from: red))
        #expect(service.revision == 0)

        try age(service, by: FaviconService.refetchAfter + 60)
        #expect(await service.fetchFavicon(for: webView, host: host) == FaviconService.png(from: blue))
        #expect(service.favicon(forHost: host) == FaviconService.png(from: blue))
        #expect(service.revision == 1, "the app's image caches are not told the icon changed")
    }

    /// A refresh that finds nothing keeps the icon the user knows, and does not ask
    /// again on the next load.
    @Test func aFailedRefreshKeepsTheOldIcon() async throws {
        let (service, webView) = try makeServiceAndPage()
        let red = try Self.png(red: 1)

        try await load(icon: red, in: webView)
        _ = await service.fetchFavicon(for: webView, host: host)

        try await load(href: "data:,not-an-image", in: webView)
        try age(service, by: FaviconService.refetchAfter + 60)
        #expect(await service.fetchFavicon(for: webView, host: host) == FaviconService.png(from: red))
        #expect(service.favicon(forHost: host) == FaviconService.png(from: red))

        let file = try #require(service.fileURL(for: host))
        let checked = try #require(try file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
        #expect(Date.now.timeIntervalSince(checked) < 60, "the next load would ask again")
    }

    // MARK: - Helpers

    private func makeServiceAndPage() throws -> (FaviconService, WKWebView) {
        let directory = URL.temporaryDirectory.appending(path: "luna-favicon-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        return (FaviconService(directory: directory), WKWebView(frame: .zero, configuration: configuration))
    }

    private func load(icon: Data, in webView: WKWebView) async throws {
        try await load(href: "data:image/png;base64,\(icon.base64EncodedString())", in: webView)
    }

    private func load(href: String, in webView: WKWebView) async throws {
        let marker = UUID().uuidString
        webView.loadHTMLString(
            "<link rel=\"icon\" href=\"\(href)\"><title>\(marker)</title>",
            baseURL: URL(string: "https://\(host)/")
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
