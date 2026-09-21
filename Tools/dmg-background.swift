#!/usr/bin/env swift
//
//  dmg-background.swift
//  Luna — §30.17
//
//  Draws the disk image's backdrop: Luna's own Space gradient over a light
//  plane, an arrow between the two icons, and one line of type.
//
//  Light, although the app is usually seen dark: Finder draws the two icon
//  labels in the *system's* appearance, not the background's, so a dark
//  backdrop hands a light-mode Mac black text on near-black. Light loses less
//  — dark mode's white labels keep their shadow — and it is the page the
//  reference sets an installer on anyway.
//
//  A script rather than a checked-in asset so the artwork moves when the colour
//  does, and standalone rather than part of the app because the installer is
//  the one surface a user sees before Luna has ever run.
//
//  Two representations in one TIFF, 1× and 2×: Finder picks by display, and a
//  single-scale PNG is either soft on Retina or twice the size everywhere.
//
//  usage: swift Tools/dmg-background.swift out.tiff
//

import AppKit

// The window `make-dmg.sh` opens. The icons sit on its centre line.
let size = CGSize(width: 640, height: 400)
let appSlot = CGPoint(x: 165, y: 210)
let applicationsSlot = CGPoint(x: 475, y: 210)

// `GradientPair.defaultSpace`, which is what a first Space is seeded with.
let gradientStart = NSColor(srgbRed: 0.45, green: 0.38, blue: 0.92, alpha: 1)
let gradientEnd = NSColor(srgbRed: 0.24, green: 0.65, blue: 0.94, alpha: 1)
// `Tokens.Surface.base` in light mode, a shade off white so the window's own
// edge is visible against it.
let plane = NSColor(srgbRed: 0.97, green: 0.97, blue: 0.98, alpha: 1)

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

    plane.setFill()
    NSRect(origin: .zero, size: size).fill()

    // The gradient reads as light falling across the plane rather than as a
    // panel: held at a tenth, corner to corner, the way §8.2a's wash is.
    let wash = NSGradient(
        colors: [gradientStart.withAlphaComponent(0.26), gradientEnd.withAlphaComponent(0.14)]
    )
    wash?.draw(in: NSRect(origin: .zero, size: size), angle: -35)

    drawArrow()
    drawCaption()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

/// A thin line with a head on it, between the two slots and clear of both.
func drawArrow() {
    let ink = NSColor(white: 0.1, alpha: 0.35)
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
        .foregroundColor: NSColor(white: 0.1, alpha: 0.55)
    ]
    let measured = (text as NSString).size(withAttributes: attributes)
    (text as NSString).draw(
        at: CGPoint(x: (size.width - measured.width) / 2, y: 74),
        withAttributes: attributes
    )
}

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "background.tiff"
let image = NSImage(size: size)
for scale in [CGFloat(1), CGFloat(2)] { image.addRepresentation(draw(scale: scale)) }
guard let data = image.tiffRepresentation else { fatalError("no tiff") }
try data.write(to: URL(fileURLWithPath: output))
print("wrote \(output)")
