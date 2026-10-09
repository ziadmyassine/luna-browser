//
//  SymbolInk.swift
//  Luna
//
//  Where an SF Symbol's ink sits in the box an image view draws it in, so a
//  row can stand each symbol level with its title rather than every symbol by
//  one measurement. A favicon's ink fills its box; a symbol's need not:
//  `plus` and `folder` sit low in theirs, `globe` and `doc.text` are centred.
//  One lift for all of them, set by `plus`, stood the globe half a point high.
//

import AppKit

@MainActor
enum SymbolInk {

    private static var drops: [String: CGFloat] = [:]

    /// How far below its box's middle the symbol's ink is centred, in
    /// points, drawn at `pointSize` in a square of that side. Measured from
    /// the pixels once per symbol and size.
    static func drop(_ name: String, pointSize: CGFloat) -> CGFloat {
        let key = "\(name)@\(pointSize)"
        if let known = drops[key] { return known }
        let measured = measure(name, pointSize: pointSize)
        drops[key] = measured
        return measured
    }

    private static func measure(_ name: String, pointSize: CGFloat) -> CGFloat {
        let view = NSImageView(frame: NSRect(x: 0, y: 0, width: pointSize, height: pointSize))
        view.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        view.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        view.contentTintColor = .black
        guard view.image != nil, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return 0 }
        view.cacheDisplay(in: view.bounds, to: rep)
        var top: Int?
        var bottom = 0
        for row in 0 ..< rep.pixelsHigh {
            let inked = (0 ..< rep.pixelsWide).contains { (rep.colorAt(x: $0, y: row)?.alphaComponent ?? 0) > 0.3 }
            guard inked else { continue }
            top = top ?? row
            bottom = row
        }
        guard let top else { return 0 }
        let scale = CGFloat(rep.pixelsHigh) / pointSize
        // Rows count down from the top.
        return (CGFloat(top + bottom + 1) / 2) / scale - pointSize / 2
    }
}
