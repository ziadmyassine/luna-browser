//
//  ControlCapture.swift
//  Luna
//
//  Luna Control's pictures of a page: `screenshot` at a scale and of a
//  region, the frames of a `gif` recording with a marker where a call
//  pointed, and the GIF written from them. Every picture is taken with the
//  page's secret fields drawn as dots, whatever its scale or region.
//
//  AppKit, WebKit and ImageIO only, and no Luna types, so
//  `BrowserKit/Tests/ControlStageTests` can compile this very file.
//

import AppKit
import ImageIO
import LunaControl
import UniformTypeIdentifiers
import WebKit

/// A tab's recording: the newest `ControlTools.frameLimit` frames.
struct ControlRecording {
    var frames: [CGImage] = []
    var isOn = true

    mutating func add(_ frame: CGImage) {
        frames.append(frame)
        if frames.count > ControlTools.frameLimit { frames.removeFirst(frames.count - ControlTools.frameLimit) }
    }
}

@MainActor
enum ControlCapture {

    /// Luna Control's own content world: the page cannot see the library's
    /// globals or the ref table, and cannot replace the functions it calls.
    static let world = WKContentWorld.world(name: "luna-control")

    /// A frame's width at most, in pixels: a page's text still reads, and
    /// sixty frames stay a few megabytes.
    private static let frameWidth = 800.0
    private static let frameDelay = 0.8

    /// `scale` pixels per CSS pixel of `region`, or of the viewport. A region
    /// reaching past the viewport is cut to it.
    static func image(of webView: WKWebView, scale: Double = 1, region: ControlCommand.Region? = nil) async throws
        -> CGImage {
        let zoom = webView.pageZoom * webView.magnification
        let viewport = CGRect(x: 0, y: 0, width: webView.bounds.width / zoom, height: webView.bounds.height / zoom)
        let css = region.map { CGRect(x: $0.x, y: $0.y, width: $0.width, height: $0.height).intersection(viewport) } ?? viewport
        guard !css.isNull, css.width >= 1, css.height >= 1 else {
            throw ControlError(region == nil ? "The tab has no size to take a picture of." : """
            That region is outside the viewport, which is \(Int(viewport.width))×\(Int(viewport.height)) CSS pixels.
            """)
        }
        let width = max(Int((css.width * scale).rounded()), 1)
        let height = max(Int((css.height * scale).rounded()), 1)
        let configuration = WKSnapshotConfiguration()
        configuration.afterScreenUpdates = true
        configuration.rect = CGRect(x: css.minX * zoom, y: css.minY * zoom, width: css.width * zoom, height: css.height * zoom)
        configuration.snapshotWidth = NSNumber(value: width)
        // A page this cannot run in — a PDF, an image — has no fields to hide.
        _ = try? await webView.callAsyncJavaScript(ControlScripts.maskSecrets, arguments: ["args": [:]], in: nil, contentWorld: world)
        let snapshot: NSImage
        do {
            snapshot = try await webView.takeSnapshot(configuration: configuration)
        } catch {
            await unmask(webView)
            throw error
        }
        await unmask(webView)
        guard let source = snapshot.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let context = context(width: width, height: height) else {
            throw ControlError("The screenshot could not be drawn.")
        }
        context.interpolationQuality = .high
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage() else { throw ControlError("The screenshot could not be drawn.") }
        return image
    }

    /// One frame of a recording, with a ring at each of `marks` (CSS pixels).
    static func frame(of webView: WKWebView, marks: [CGPoint]) async throws -> CGImage {
        let cssWidth = webView.bounds.width / (webView.pageZoom * webView.magnification)
        let scale = min(1, frameWidth / max(cssWidth, 1))
        let image = try await image(of: webView, scale: scale)
        guard !marks.isEmpty, let context = context(width: image.width, height: image.height) else { return image }
        let height = CGFloat(image.height)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        // Drawn into the agent's picture, not Luna's interface: a red that
        // stands out on most pages rather than a design token.
        context.setStrokeColor(CGColor(srgbRed: 1, green: 0.2, blue: 0.2, alpha: 1))
        context.setFillColor(CGColor(srgbRed: 1, green: 0.2, blue: 0.2, alpha: 0.3))
        context.setLineWidth(3)
        for mark in marks {
            let ring = CGRect(x: mark.x * scale - 12, y: height - mark.y * scale - 12, width: 24, height: 24)
            context.fillEllipse(in: ring)
            context.strokeEllipse(in: ring)
        }
        return context.makeImage() ?? image
    }

    static func png(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    /// Loops forever, one frame every `frameDelay` seconds.
    static func writeGIF(_ frames: [CGImage], to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.gif.identifier as CFString, frames.count, nil
        ) else { throw ControlError("The recording could not be written.") }
        let gif = kCGImagePropertyGIFDictionary as String
        CGImageDestinationSetProperties(destination, [gif: [kCGImagePropertyGIFLoopCount as String: 0]] as CFDictionary)
        let each = [gif: [kCGImagePropertyGIFDelayTime as String: frameDelay]] as CFDictionary
        for frame in frames { CGImageDestinationAddImage(destination, frame, each) }
        guard CGImageDestinationFinalize(destination) else { throw ControlError("The recording could not be written.") }
    }

    private static func unmask(_ webView: WKWebView) async {
        _ = try? await webView.callAsyncJavaScript(ControlScripts.unmaskSecrets, arguments: ["args": [:]], in: nil, contentWorld: world)
    }

    private static func context(width: Int, height: Int) -> CGContext? {
        CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }
}
