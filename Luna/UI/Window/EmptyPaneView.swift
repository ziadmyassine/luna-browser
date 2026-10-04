//
//  EmptyPaneView.swift
//  Luna
//
//  What the content pane shows with no page in it: a moonscape from the same
//  hand as the error pages (`assets/error-pages/`), by day in light and by
//  night in dark. The pane's plain plane was there before, and a window with
//  every tab closed read as one that had failed to draw.
//
//  The painting is placed the way an error page's is: covering the pane,
//  standing on its bottom edge, and anchored left of centre so a narrow pane
//  crops the empty sky on the right rather than the chair on the left.
//

import AppKit
import BrowserKit
import ImageIO

@MainActor
final class EmptyPaneView: NSView {

    /// The fraction of the overflow cut from the left when the pane is
    /// narrower than the painting: the error pages' `25%`.
    static let horizontalAnchor: CGFloat = 0.25

    let painting = CALayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        painting.contentsGravity = .resize
        layer?.addSublayer(painting)
        showPainting()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its views in code")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        showPainting()
    }

    override func layout() {
        super.layout()
        guard let size = Self.image(dark: isDark).map({ CGSize(width: $0.width, height: $0.height) }),
              size.width > 0, size.height > 0
        else { return }
        let scale = max(bounds.width / size.width, bounds.height / size.height)
        let drawn = CGSize(width: size.width * scale, height: size.height * scale)
        Tokens.Motion.immediately {
            painting.frame = CGRect(
                x: (bounds.width - drawn.width) * Self.horizontalAnchor,
                y: 0,
                width: drawn.width,
                height: drawn.height
            )
        }
    }

    private var isDark: Bool {
        effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    private func showPainting() {
        let image = Self.image(dark: isDark)
        Tokens.Motion.immediately { painting.contents = image }
        needsLayout = true
    }

    // MARK: - The two paintings

    private static var images: [Bool: CGImage] = [:]
    private static var skies: [Bool: RGBA] = [:]

    private static func data(dark: Bool) -> Data? {
        Bundle.main.url(forResource: dark ? "empty-dark" : "empty-light", withExtension: "jpg")
            .flatMap { try? Data(contentsOf: $0) }
    }

    /// Decoded once per appearance and kept: the pane shows it every time the
    /// last tab closes, and a 2752-wide JPEG is not worth decoding each time.
    private static func image(dark: Bool) -> CGImage? {
        if let image = images[dark] { return image }
        let image = data(dark: dark)
            .flatMap { CGImageSourceCreateWithData($0 as CFData, nil) }
            .flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
        images[dark] = image
        return image
    }

    /// The painting's sky, for the page bar over an empty pane.
    static func sky(dark: Bool) -> RGBA? {
        if let sky = skies[dark] { return sky }
        let sky = data(dark: dark).flatMap(InternalPages.skyColour(ofPainting:))
        skies[dark] = sky
        return sky
    }

    /// The sky for the appearance the app is in now.
    static var sky: RGBA? {
        sky(dark: NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
    }
}
