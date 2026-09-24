//
//  SettingsLayoutPicker.swift
//  Luna
//
//  §3.2's Layout row: a small picture of each layout, chosen by clicking it,
//  the way System Settings chooses a theme. Two words in a segment told the
//  user where the tabs go; the picture shows them, before they have to try it.
//
//  The pictures are drawn, not screenshots: they follow the theme and the
//  Increase Contrast inks like the rest of the pane, and a screenshot of
//  somebody else's tabs would be a lie about what the user's window will
//  look like.
//

import AppKit

@MainActor
final class SettingsLayoutPicker: NSView {

    var onChoose: ((ChromeLayoutPreference) -> Void)?

    private(set) var options: [SettingsLayoutOption] = []

    var selected: ChromeLayoutPreference {
        didSet { for option in options { option.isChosen = option.layout == selected } }
    }

    init(selected: ChromeLayoutPreference) {
        self.selected = selected
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = Tokens.Metric.chromeGapWide
        stack.alignment = .top
        stack.translatesAutoresizingMaskIntoConstraints = false
        for layout in ChromeLayoutPreference.allCases {
            let option = SettingsLayoutOption(layout: layout)
            option.isChosen = layout == selected
            option.onChoose = { [weak self] in
                guard let self, self.selected != layout else { return }
                self.selected = layout
                onChoose?(layout)
            }
            options.append(option)
            stack.addArrangedSubview(option)
        }
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.radioGroup)
        setAccessibilityLabel(String(localized: "Layout"))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }
}

/// One layout: its picture and its name. Answers the pointer with its ring,
/// as `SpaceSwatchChip` does — a wash over the picture would be a picture of
/// a different window — and the press with the swell every button has.
@MainActor
final class SettingsLayoutOption: NSView {

    let layout: ChromeLayoutPreference
    var onChoose: (() -> Void)?

    var isChosen = false {
        didSet {
            guard isChosen != oldValue else { return }
            refresh(animated: true)
        }
    }

    /// Internal so a test can see the swell land on it.
    let picture: SettingsLayoutPicture
    private let label = NSTextField(labelWithString: "")
    private var isHovering = false {
        didSet { if isHovering != oldValue { refresh(animated: true) } }
    }
    private var isPressed = false {
        didSet {
            guard isPressed != oldValue else { return }
            Tokens.Motion.swell(picture, to: isPressed ? Tokens.Motion.pressSwell : 1)
        }
    }

    init(layout: ChromeLayoutPreference) {
        self.layout = layout
        picture = SettingsLayoutPicture(layout: layout)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        label.stringValue = layout.title
        label.font = Tokens.TypeScale.settingsCaption
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        picture.translatesAutoresizingMaskIntoConstraints = false
        for view in [picture, label] { addSubview(view) }
        let size = Tokens.Metric.settingsLayoutPreview
        NSLayoutConstraint.activate([
            picture.widthAnchor.constraint(equalToConstant: size.width),
            picture.heightAnchor.constraint(equalToConstant: size.height),
            picture.topAnchor.constraint(equalTo: topAnchor),
            picture.leadingAnchor.constraint(equalTo: leadingAnchor),
            picture.trailingAnchor.constraint(equalTo: trailingAnchor),
            label.topAnchor.constraint(equalTo: picture.bottomAnchor, constant: Tokens.Metric.chromeGap),
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.radioButton)
        setAccessibilityLabel(layout.title)
        refresh(animated: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    private func refresh(animated: Bool) {
        setAccessibilityValue(isChosen)
        label.textColor = isChosen ? Tokens.Text.primary : Tokens.Text.secondary
        let ring: NSColor? = if isChosen {
            Tokens.Text.primary
        } else if isHovering {
            Tokens.Text.secondary
        } else {
            nil
        }
        picture.setRing(ring, animated: animated)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refresh(animated: false)
    }

    // MARK: - Pointer

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where area.owner === self { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) { isHovering = true }
    override func mouseExited(with event: NSEvent) { isHovering = false }

    override func mouseDown(with event: NSEvent) { isPressed = true }

    override func mouseUp(with event: NSEvent) {
        isPressed = false
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onChoose?()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }

    override func accessibilityPerformPress() -> Bool {
        onChoose?()
        return true
    }
}

/// A window in miniature: the lights, the chrome the layout puts its tabs
/// in, and the page. The selected tab is the one bright pill, as it is in
/// the real window.
@MainActor
final class SettingsLayoutPicture: NSView {

    private let kind: ChromeLayoutPreference

    init(layout: ChromeLayoutPreference) {
        kind = layout
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerCurve = .continuous
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    /// The ring is drawn outside the picture, as the swatch's is, so choosing
    /// a layout does not cover the edge of the thing chosen.
    func setRing(_ colour: NSColor?, animated: Bool) {
        let apply = {
            self.layer?.borderWidth = colour == nil ? 0 : Tokens.Metric.settingsLayoutRing
            self.layer?.borderColor = colour?.cgColor
        }
        guard animated else { return Tokens.Motion.immediately(apply) }
        Tokens.Motion.animate(Tokens.Motion.controlHover) { context in
            context.allowsImplicitAnimation = true
            apply()
        }
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = Tokens.Metric.settingsControlCorner + Tokens.Metric.settingsLayoutRing
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    // MARK: - Drawing

    /// Proportions of the picture, so it scales with its token.
    private enum Part {
        static let inset: CGFloat = 1 / 24
        static let sidebar: CGFloat = 0.3
        /// A tab pill's height, of the picture's.
        static let tab: CGFloat = 0.12
        /// A light's diameter, of the picture's width, and the gap between two
        /// of them, of a light — macOS's 12 pt lights stand 8 pt apart.
        static let light: CGFloat = 1 / 30
        static let lightGap: CGFloat = 0.65
    }

    override func draw(_ dirtyRect: NSRect) {
        let ring = Tokens.Metric.settingsLayoutRing
        let window = bounds.insetBy(dx: 2 * ring, dy: 2 * ring)
        let corner = Tokens.Metric.settingsControlCorner - ring
        fill(window, corner: corner, with: Tokens.Surface.hover)
        Tokens.Line.border.setStroke()
        let edge = NSBezierPath(roundedRect: window.insetBy(dx: 0.5, dy: 0.5), xRadius: corner, yRadius: corner)
        edge.lineWidth = Tokens.Metric.hairline
        edge.stroke()

        let pad = window.width * Part.inset
        switch kind {
        case .sidebar: drawSidebar(in: window, pad: pad, corner: corner)
        case .topBar: drawTopBar(in: window, pad: pad, corner: corner)
        }
    }

    /// The lights on the first line: the column's head in one picture, the
    /// bar in the other — the line the tabs stand on, as in the real window.
    private func drawSidebar(in window: NSRect, pad: CGFloat, corner: CGFloat) {
        let column = window.width * Part.sidebar
        let tab = window.height * Part.tab
        let head = window.maxY - pad - tab / 2
        drawLights(from: window.minX + 1.5 * pad, centredOn: head)
        for index in 0..<4 {
            let pill = NSRect(
                x: window.minX + pad,
                y: head - tab / 2 - CGFloat(index + 1) * (tab + pad / 2),
                width: column - 2 * pad,
                height: tab
            )
            fill(pill, corner: tab / 3, with: index == 0 ? Tokens.Surface.selected : Tokens.Surface.hover)
        }
        let page = NSRect(
            x: window.minX + column,
            y: window.minY + pad,
            width: window.width - column - pad,
            height: window.height - 2 * pad
        )
        fill(page, corner: corner - pad, with: Tokens.Surface.selected)
    }

    private func drawTopBar(in window: NSRect, pad: CGFloat, corner: CGFloat) {
        let tab = window.height * Part.tab
        let line = window.maxY - pad - tab / 2
        let lightsEnd = drawLights(from: window.minX + 1.5 * pad, centredOn: line)
        let width = window.width / 6
        for index in 0..<3 {
            let pill = NSRect(
                x: lightsEnd + 1.5 * pad + CGFloat(index) * (width + pad / 2),
                y: line - tab / 2,
                width: width,
                height: tab
            )
            fill(pill, corner: tab / 3, with: index == 0 ? Tokens.Surface.selected : Tokens.Surface.hover)
        }
        let top = line - tab / 2 - pad
        let page = NSRect(
            x: window.minX + pad,
            y: window.minY + pad,
            width: window.width - 2 * pad,
            height: top - window.minY - pad
        )
        fill(page, corner: corner - pad, with: Tokens.Surface.selected)
    }

    /// The three lights, in the ink the rest of the picture is drawn in: a
    /// row of red, yellow and green at this size is the loudest thing in the
    /// pane and says nothing about the layout. Returns where the row ends.
    @discardableResult
    private func drawLights(from x: CGFloat, centredOn y: CGFloat) -> CGFloat {
        let size = bounds.width * Part.light
        let step = size * (1 + Part.lightGap)
        Tokens.Text.tertiary.setFill()
        for index in 0..<3 {
            let dot = NSRect(x: x + CGFloat(index) * step, y: y - size / 2, width: size, height: size)
            NSBezierPath(ovalIn: dot).fill()
        }
        return x + 2 * step + size
    }

    private func fill(_ rect: NSRect, corner: CGFloat, with colour: NSColor) {
        colour.setFill()
        NSBezierPath(roundedRect: rect, xRadius: max(corner, 0), yRadius: max(corner, 0)).fill()
    }
}
