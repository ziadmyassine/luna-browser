import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import WebKit

/// WebKit ships no favicon API at all (§26), so Luna finds icons itself: ask the page
/// for its `<link rel="icon">` set, fall back to `/favicon.ico`, and cache what decodes.
///
/// Everything handed out is **PNG bytes that have already been decoded once**. That is
/// the guarantee behind "no icon ever flashes a broken-image glyph" (§4.7): bytes that
/// ImageIO cannot read never reach the cache, so the sidebar's only two cases are a
/// real icon or nil (where the UI draws its monogram tile).
@MainActor
public final class FaviconService {

    public static let shared = FaviconService()

    /// Keys with no icon are remembered as empty `Data` so a miss costs one disk hit,
    /// not one per redraw.
    private var memory: [String: Data] = [:]
    private var recency: [String] = []
    private let memoryLimit: Int
    private let directory: URL

    /// Test seam: how many hosts the memory tier is holding.
    var memoryCount: Int { memory.count }

    init(directory: URL = FaviconService.defaultDirectory, memoryLimit: Int = 128) {
        self.directory = directory
        self.memoryLimit = memoryLimit
    }

    static var defaultDirectory: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL.temporaryDirectory
        return caches
            .appending(path: Bundle.main.bundleIdentifier ?? "dk.novapps.luna")
            .appending(path: "Favicons")
    }

    /// Cached PNG bytes, nil if unknown. Never touches the network.
    public func favicon(forHost host: String) -> Data? {
        let key = NavigationPolicy.faviconKey(forHost: host)
        if let cached = memory[key] {
            touch(key)
            return cached.isEmpty ? nil : cached
        }
        let onDisk = try? Data(contentsOf: fileURL(for: key))
        store(onDisk ?? Data(), for: key)
        return onDisk
    }

    /// Asks the live page for its icons, downloads the best one, caches it (§4.7).
    public func fetchFavicon(for webView: WKWebView, host: String) async -> Data? {
        let key = NavigationPolicy.faviconKey(forHost: host)
        if let cached = favicon(forHost: host) { return cached }

        var candidates = await declaredIconURLs(in: webView)
        // The convention every site still honours, and the only candidate for a page
        // that declares nothing.
        if let fallback = URL(string: "https://\(key)/favicon.ico") { candidates.append(fallback) }

        for candidate in candidates {
            guard let png = await Self.downloadPNG(from: candidate) else { continue }
            store(png, for: key)
            let file = fileURL(for: key)
            await Self.write(png, to: file)
            return png
        }
        store(Data(), for: key)
        return nil
    }

    // MARK: - Cache

    private func touch(_ key: String) {
        recency.removeAll { $0 == key }
        recency.append(key)
    }

    private func store(_ data: Data, for key: String) {
        memory[key] = data
        touch(key)
        while recency.count > memoryLimit {
            memory.removeValue(forKey: recency.removeFirst())
        }
    }

    /// Internal so tests can seed the disk tier.
    func fileURL(for key: String) -> URL {
        let name = key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? key
        return directory.appending(path: name + ".png")
    }

    // MARK: - Page + network (off the main actor)

    /// Best-first: biggest declared `sizes` wins, and an `apple-touch-icon` with no
    /// `sizes` is assumed to be the 180px one it almost always is.
    private func declaredIconURLs(in webView: WKWebView) async -> [URL] {
        let script = """
        (function () {
          var out = [];
          var links = document.querySelectorAll(
            'link[rel~="icon"], link[rel~="apple-touch-icon"], link[rel~="apple-touch-icon-precomposed"]'
          );
          for (var i = 0; i < links.length; i++) {
            var l = links[i];
            if (!l.href) { continue; }
            var size = parseInt((l.getAttribute('sizes') || '').split('x')[0], 10);
            if (isNaN(size)) { size = /apple/.test(l.getAttribute('rel') || '') ? 180 : 32; }
            out.push({ href: l.href, size: size });
          }
          out.sort(function (a, b) { return b.size - a.size; });
          return out.map(function (e) { return e.href; });
        })();
        """
        guard let hrefs = try? await webView.evaluateJavaScript(script) as? [String] else { return [] }
        return hrefs.compactMap(URL.init(string:)).filter {
            ["http", "https", "data"].contains($0.scheme?.lowercased() ?? "")
        }
    }

    private nonisolated static func downloadPNG(from url: URL) async -> Data? {
        guard let (data, response) = try? await URLSession.shared.data(from: url) else { return nil }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { return nil }
        // An icon is kilobytes. Anything past this is a mislabelled page or a trap.
        guard !data.isEmpty, data.count <= 2_000_000 else { return nil }
        return png(from: data)
    }

    private nonisolated static func write(_ data: Data, to file: URL) async {
        try? FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: file, options: .atomic)
    }

    /// Decodes, picks the largest sub-image (a `.ico` packs several and lists the
    /// smallest first) and re-encodes as a bounded PNG. Returns nil for anything
    /// ImageIO cannot read — including SVG icons, which fall through to the next
    /// candidate rather than becoming a broken image.
    nonisolated static func png(from data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { return nil }

        var bestIndex = 0
        var bestWidth = 0
        for index in 0..<count {
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
            let width = properties?[kCGImagePropertyPixelWidth] as? Int ?? 0
            if width > bestWidth {
                bestWidth = width
                bestIndex = index
            }
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 128
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, bestIndex, options as CFDictionary)
            ?? CGImageSourceCreateImageAtIndex(source, bestIndex, nil)
        else { return nil }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.png.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
