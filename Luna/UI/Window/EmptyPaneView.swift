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
//  crops the empty sky on the right rather than the chair on the left. The
//  words are set the way an error page sets its own (`InternalPageHTML`'s
//  painted page): display type ranged left in the sky, sized to the pane, and
//  under it the one thing to do, with the New Tab shortcut as it is bound now.
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
    let headline = NSTextField(labelWithString: String(localized: "All quiet"))
    let hint = NSTextField(wrappingLabelWithString: "")
    private var shortcutObserver: (any NSObjectProtocol)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        painting.contentsGravity = .resize
        layer?.addSublayer(painting)
        headline.textColor = Tokens.Text.primary
        hint.textColor = Tokens.Text.secondary
        for label in [headline, hint] {
            label.isSelectable = false
            addSubview(label)
        }
        showPainting()
        showHint()
        shortcutObserver = NotificationCenter.default.addObserver(
            forName: KeyBindings.didChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.showHint() }
        }
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
        placeWords()
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

    // MARK: - The words

    /// The error pages' measures, as `InternalPageHTML` writes them for a
    /// painted page: the headline between 1.75 and 4.5 titles and 7.5 % of
    /// the pane's width, the line under it between one and 1.5 bodies and
    /// 1.6 %, set in from the left by 9 % and centred in the sky above the
    /// bottom 26 %.
    static let headlineScale: (min: CGFloat, width: CGFloat, max: CGFloat) = (1.75, 0.075, 4.5)
    static let hintScale: (min: CGFloat, width: CGFloat, max: CGFloat) = (1, 0.016, 1.5)
    static let leadingInset: CGFloat = 0.09
    static let groundShare: CGFloat = 0.26

    private static func clamp(_ scale: (min: CGFloat, width: CGFloat, max: CGFloat), base: CGFloat, width: CGFloat) -> CGFloat {
        min(max(base * scale.min, width * scale.width), base * scale.max)
    }

    /// "Press ⌘T to open a new tab.", with the keystroke in the headline's
    /// ink, or the menu to use when New Tab has no shortcut at all.
    private func showHint() {
        let size = hint.font?.pointSize ?? Tokens.TypeScale.pageBody.pointSize
        let plain: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size, weight: .regular),
            .foregroundColor: Tokens.Text.secondary
        ]
        guard let shortcut = KeyBindings.primary(for: .newTab)?.display else {
            hint.attributedStringValue = NSAttributedString(
                string: String(localized: "Choose File \u{203A} New Tab to open a page."),
                attributes: plain
            )
            return
        }
        let text = NSMutableAttributedString(string: String(localized: "Press "), attributes: plain)
        text.append(NSAttributedString(string: shortcut, attributes: [
            .font: NSFont.systemFont(ofSize: size, weight: .semibold),
            .foregroundColor: Tokens.Text.primary
        ]))
        text.append(NSAttributedString(string: String(localized: " to open a new tab."), attributes: plain))
        hint.attributedStringValue = text
    }

    private func placeWords() {
        let titleSize = Self.clamp(Self.headlineScale, base: Tokens.TypeScale.pageTitle.pointSize, width: bounds.width)
        let bodySize = Self.clamp(Self.hintScale, base: Tokens.TypeScale.pageBody.pointSize, width: bounds.width)
        if headline.font?.pointSize != titleSize {
            headline.font = .systemFont(ofSize: titleSize, weight: .heavy)
            // The page's `letter-spacing: -0.05ch`, a twentieth of a digit.
            headline.attributedStringValue = NSAttributedString(string: headline.stringValue, attributes: [
                .font: NSFont.systemFont(ofSize: titleSize, weight: .heavy),
                .foregroundColor: Tokens.Text.primary,
                .kern: -titleSize * 0.03
            ])
        }
        if hint.font?.pointSize != bodySize {
            hint.font = .systemFont(ofSize: bodySize, weight: .regular)
            showHint()
        }
        let left = (bounds.width * Self.leadingInset).rounded()
        let room = max(bounds.width - left * 2, 0)
        // The page's `max-width: 34ch` on the line under the headline.
        hint.preferredMaxLayoutWidth = min(room, bodySize * 0.6 * 34)
        // Measured by the cells that draw them, at the width there is: an
        // intrinsic size read in the pass that changed the font is the old
        // font's, and both lines came out cut short.
        let headlineSize = Self.fit(headline, width: room)
        let hintSize = Self.fit(hint, width: hint.preferredMaxLayoutWidth)
        let gap = Tokens.Metric.chromeGapWide * 1.5
        let block = headlineSize.height + gap + hintSize.height
        let sky = bounds.height * (1 - Self.groundShare)
        // Bottom-left origin: the sky is the top part of the pane.
        let top = bounds.height - (sky - block) / 2
        Tokens.Motion.immediately {
            headline.frame = CGRect(x: left, y: top - headlineSize.height,
                                    width: headlineSize.width, height: headlineSize.height)
            hint.frame = CGRect(x: left, y: top - block, width: hintSize.width, height: hintSize.height)
        }
    }

    private static func fit(_ label: NSTextField, width: CGFloat) -> CGSize {
        let size = label.cell?.cellSize(forBounds: CGRect(x: 0, y: 0, width: width, height: .greatestFiniteMagnitude))
            ?? label.intrinsicContentSize
        return CGSize(width: min(size.width.rounded(.up), width), height: size.height.rounded(.up))
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
