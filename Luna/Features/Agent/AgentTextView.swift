//
//  AgentTextView.swift
//  Luna
//
//  The agent's words as the panel sets them: selectable text whose links
//  answer the pointer. A link is in Astro's ink, a weight up from the words
//  round it and with no rule under it; under the pointer a rounded lavender
//  wash fades in behind it and the
//  pointer becomes a hand; a click opens it in a tab of Luna's own rather
//  than handing it to whichever browser is the system's.
//
//  A text view rather than a label because a label cannot say where in its
//  words the pointer is. It sizes itself to its words at the width it is
//  given, so it stacks like a wrapping label.
//

import AppKit

@MainActor
final class AgentTextView: NSTextView {

    /// Where a clicked link goes. Without one it opens as any link would.
    var onOpenLink: ((URL) -> Void)?

    /// The words. Setting them clears a hover over words that are gone.
    var text = NSAttributedString() {
        didSet {
            guard text != oldValue else { return }
            textStorage?.setAttributedString(text)
            hover(nil)
            invalidateIntrinsicContentSize()
        }
    }

    /// One wash per line a hovered link runs across.
    private let washes = CALayer()
    private var hovered: NSRange?
    private var tracking: NSTrackingArea?

    init() {
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: 100, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        super.init(frame: .zero, textContainer: container)
        translatesAutoresizingMaskIntoConstraints = false
        isEditable = false
        isSelectable = true
        drawsBackground = false
        textContainerInset = .zero
        isVerticallyResizable = false
        isHorizontallyResizable = false
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        wantsLayer = true
        washes.zPosition = -1
        layer?.addSublayer(washes)
        linkTextAttributes = [
            .foregroundColor: Tokens.Astro.link,
            .cursor: NSCursor.pointingHand
        ]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    // MARK: - Size

    override var intrinsicContentSize: NSSize {
        guard let layout = layoutManager, let container = textContainer else { return super.intrinsicContentSize }
        layout.ensureLayout(for: container)
        return NSSize(width: NSView.noIntrinsicMetric, height: ceil(layout.usedRect(for: container).height))
    }

    override func setFrameSize(_ newSize: NSSize) {
        let rewraps = newSize.width != frame.width
        super.setFrameSize(newSize)
        if rewraps {
            invalidateIntrinsicContentSize()
            hover(nil)
        }
    }

    // MARK: - The pointer

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        hover(link(at: convert(event.locationInWindow, from: nil)))
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        hover(nil)
    }

    /// The whole link under `point`, if the point is on its words rather
    /// than in the space after a line.
    func link(at point: NSPoint) -> NSRange? {
        guard let layout = layoutManager, let container = textContainer, let storage = textStorage, storage.length > 0 else { return nil }
        let inText = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        var fraction: CGFloat = 0
        let glyph = layout.glyphIndex(for: inText, in: container, fractionOfDistanceThroughGlyph: &fraction)
        guard layout.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container).contains(inText) else { return nil }
        let index = layout.characterIndexForGlyph(at: glyph)
        guard index < storage.length else { return nil }
        var range = NSRange()
        return storage.attribute(.link, at: index, effectiveRange: &range) == nil ? nil : range
    }

    /// The wash behind `range`, faded in, or faded out with nil.
    private func hover(_ range: NSRange?) {
        guard range != hovered else { return }
        hovered = range
        var rects: [CGRect] = []
        if let range, let layout = layoutManager, let container = textContainer {
            let glyphs = layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            layout.enumerateEnclosingRects(forGlyphRange: glyphs, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
                                           in: container) { rect, _ in
                rects.append(rect.offsetBy(dx: self.textContainerOrigin.x, dy: self.textContainerOrigin.y).insetBy(dx: -3, dy: -1))
            }
        }
        if !rects.isEmpty {
            Tokens.Motion.immediately {
                washes.sublayers = rects.map { rect in
                    let wash = CALayer()
                    wash.frame = rect
                    wash.cornerRadius = 5
                    wash.cornerCurve = .continuous
                    wash.backgroundColor = Tokens.Astro.from.withAlphaComponent(0.18).cgColor
                    return wash
                }
                washes.opacity = 0
            }
        }
        CATransaction.begin()
        CATransaction.setAnimationDuration(Tokens.Motion.reduceMotion ? 0 : Tokens.Motion.controlHover.duration)
        washes.opacity = rects.isEmpty ? 0 : 1
        CATransaction.commit()
    }

    override func layout() {
        super.layout()
        Tokens.Motion.immediately { washes.frame = bounds }
    }

    // MARK: - Clicks

    override func clicked(onLink link: Any, at charIndex: Int) {
        let url = (link as? URL) ?? (link as? String).flatMap(URL.init(string:))
        guard let url, let onOpenLink else { return super.clicked(onLink: link, at: charIndex) }
        onOpenLink(url)
    }
}
