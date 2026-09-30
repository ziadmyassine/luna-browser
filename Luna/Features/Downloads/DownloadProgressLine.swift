//
//  DownloadProgressLine.swift
//  Luna
//
//  §5.0's read-out: how far a download has got, on the row in §15.3's list.
//
//  §3.2c's line — same `loadLineHeight`, `Accent.tint` fill and
//  `loadLineAdvance` travel, because two surfaces that answer "how far" should
//  not be two designs — plus a track. The load line needs none because its
//  pill is the track; a row has no such edge, and a line ending in the middle
//  of nothing says nothing about how far the bytes have to go.
//
//  The fill only travels between two honest numbers. WebKit's `Progress`
//  (§15.1a) can arrive in jumps or not at all, and a bar on a clock of its own
//  lies, so this animates from where it is to where it has been told.
//

import AppKit

/// Decorative: the percentage is on the row in words, for §21.1's sake, and
/// this is the glanceable version of the same fact.
@MainActor
final class DownloadProgressLine: NSView {

    private let fill = NSView()
    private(set) var fraction: Double = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        fill.wantsLayer = true
        addSubview(fill)
        refreshInk()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    /// Moves the fill to `next`, animated, unless nothing has changed.
    ///
    /// Forward-only, for §3.2c's rule 2: a download that reports a smaller
    /// fraction after a redirect or a resume is not a file getting further
    /// away, and a bar that retreats reads as a fault rather than as a fact.
    func advance(to next: Double) {
        let clamped = min(max(next, 0), 1)
        guard clamped > fraction else { return }
        fraction = clamped
        Tokens.Motion.animate(Tokens.Motion.loadLineAdvance) { context in
            context.allowsImplicitAnimation = true
            fill.animator().frame = fillFrame
        }
    }

    /// Back to empty with no travel — a retry starting over, or a row being
    /// re-used. There is nothing to watch about a bar being reset.
    func reset() {
        fraction = 0
        Tokens.Motion.immediately { fill.frame = fillFrame }
    }

    override func layout() {
        super.layout()
        // Bounds-derived frames never animate — see `Motion.immediately`.
        Tokens.Motion.immediately {
            layer?.cornerRadius = bounds.height / 2
            fill.layer?.cornerRadius = bounds.height / 2
            fill.frame = fillFrame
        }
    }

    /// Leading-anchored, so it grows the way the language reads.
    private var fillFrame: NSRect {
        NSRect(x: 0, y: 0, width: (bounds.width * fraction).rounded(), height: bounds.height)
    }

    private func refreshInk() {
        // §1's colour rule allows the accent as fill, which is all this is.
        // The track is §3.4's hover wash — the faintest surface in the system,
        // which is the right weight for "the part that has not happened yet".
        layer?.backgroundColor = Tokens.Surface.hover.cgColor
        fill.layer?.backgroundColor = Tokens.Accent.tint.cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshInk()
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
