#!/usr/bin/env swift
//
//  dmg-background.swift
//  Luna — §30.17
//
//  Draws the disk image's backdrop: the moon as a light source, an arrow
//  between the two icons, and one line of type.
//
//  The plane itself is artwork (`assets/dmg/dmg-background-*.jpg`) and the
//  two pieces of chrome are drawn here, rather than baked in, because type
//  that has been through a resampler is the one thing on this page a reader
//  looks at closely.
//
//  Light by default, although the app is usually seen dark: Finder draws the
//  two icon labels in the *system's* appearance, not the background's, so a
//  dark backdrop hands a light-mode Mac black text on near-black. A disk image
//  stores one background picture, in the volume's `.DS_Store`, so this is a
//  choice rather than a pair — `--dark` builds the other one for a release
//  that wants it.
//
//  Two representations in one TIFF, 1x and 2x: Finder picks by display, and a
//  single-scale PNG is either soft on Retina or twice the size everywhere.
//
//  usage: swift Tools/dmg-background.swift out.tiff [--dark]
//

import AppKit

// The window `make-dmg.sh` opens. The icons sit on its centre line.
let size = CGSize(width: 640, height: 400)
let appSlot = CGPoint(x: 165, y: 210)
let applicationsSlot = CGPoint(x: 475, y: 210)

let arguments = CommandLine.arguments
let isDark = arguments.contains("--dark")
let output = arguments.dropFirst().first { !$0.hasPrefix("--") } ?? "background.tiff"

/// The artwork, beside the tool rather than inside the app: it is a build
/// input for the installer, and the installer is the one surface a user sees
/// before Luna has ever run.
let plane: NSImage = {
    let name = isDark ? "dmg-background-dark" : "dmg-background-light"
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "assets/dmg/\(name).jpg")
    guard let image = NSImage(contentsOf: url) else { fatalError("no backdrop at \(url.path)") }
    return image
}()

// Ink for the arrow and the caption, against whichever plane is under them.
let ink = isDark ? NSColor(white: 1, alpha: 0.4) : NSColor(white: 0.1, alpha: 0.35)
let captionInk = isDark ? NSColor(white: 1, alpha: 0.6) : NSColor(white: 0.1, alpha: 0.55)

func draw(scale: CGFloat) -> NSBitmapImageRep {
    let pixels = (width: Int(size.width * scale), height: Int(size.height * scale))
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels.width,
        pixelsHigh: pixels.height,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { fatalError("no bitmap") }
    rep.size = size

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    plane.draw(in: NSRect(origin: .zero, size: size))
    drawArrow()
    drawCaption()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

/// A thin line with a head on it, between the two slots and clear of both.
func drawArrow() {
    ink.setStroke()
    let inset: CGFloat = 96
    let start = CGPoint(x: appSlot.x + inset, y: appSlot.y)
    let end = CGPoint(x: applicationsSlot.x - inset, y: applicationsSlot.y)
    let shaft = NSBezierPath()
    shaft.lineWidth = 2
    shaft.lineCapStyle = .round
    shaft.move(to: start)
    shaft.line(to: end)
    shaft.stroke()

    let head = NSBezierPath()
    head.lineWidth = 2
    head.lineCapStyle = .round
    head.lineJoinStyle = .round
    let wing: CGFloat = 9
    head.move(to: CGPoint(x: end.x - wing, y: end.y + wing))
    head.line(to: end)
    head.line(to: CGPoint(x: end.x - wing, y: end.y - wing))
    head.stroke()
}

func drawCaption() {
    let text = "Drag Luna into Applications"
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 13, weight: .regular),
        .foregroundColor: captionInk
    ]
    let measured = (text as NSString).size(withAttributes: attributes)
    (text as NSString).draw(
        at: CGPoint(x: (size.width - measured.width) / 2, y: 74),
        withAttributes: attributes
    )
}

let image = NSImage(size: size)
for scale in [CGFloat(1), CGFloat(2)] { image.addRepresentation(draw(scale: scale)) }
guard let data = image.tiffRepresentation else { fatalError("no tiff") }
try data.write(to: URL(fileURLWithPath: output))
print("wrote \(output)")
