//
//  TabSwitcherView.swift
//  Luna
//
//  The `⌃⇥` switcher on screen: up to two rows of five tab cards on §5's
//  popover glass, in a panel of its own centred on the browser window.
//
//  A child panel rather than a view in the window, unlike the Command Bar and
//  the quit sheet, because its size is fixed and the window's is not. Five
//  cards across are wider than a small window, and the switcher does not
//  shrink or scroll to fit one: it stands over the window and past its edges.
//  A view inside the window would be cut off at them.
//
//  The keyboard never comes here. `⌃` is held down the whole time the
//  switcher is up, and a local event monitor reads it before the page can
//  (`AppDelegate+TabSwitcher.swift`), so the panel never becomes key.
//

import AppKit

/// The switcher's geometry. `Design/` has no switcher entry, so every value
/// that can be is derived from an existing `Tokens.Metric`, as
/// `CommandBarMetrics` and `QuitSheetMetrics` are.
enum TabSwitcherMetrics {
    /// The width §6.8's stored snapshots were made for: `TabLifecycle` sizes
    /// them for a preview about 200 pt wide, so a picture from disk is sharp
    /// here and a picture taken live costs no more than one from disk.
    static let pictureWidth: CGFloat = 200
    /// 16:10, the shape of the pages the pictures are of on a laptop display.
    /// A page of another shape is cropped to it rather than squashed.
    static var pictureSize: CGSize { CGSize(width: pictureWidth, height: (pictureWidth * 10 / 16).rounded()) }
    static var cardInset: CGFloat { Tokens.Metric.panelInset }
    static var cardSize: CGSize {
        CGSize(
            width: pictureWidth + 2 * cardInset,
            height: pictureSize.height + Tokens.Metric.faviconSize + 3 * cardInset
        )
    }
    static var cardGap: CGFloat { Tokens.Metric.panelInset }
    /// Between the glass and the cards.
    static var padding: CGFloat { Tokens.Metric.panelInset }
    static var panelRadius: CGFloat { Tokens.Metric.contentCardRadius }
    /// Concentric with the panel, and the picture with the card: each corner
    /// is the one outside it minus the inset between them, so the three curves
    /// run parallel instead of pinching at the corners.
    static var cardRadius: CGFloat { panelRadius - padding }
    static var pictureRadius: CGFloat { cardRadius - cardInset }
    /// How long `⌃⇥` waits before the panel appears. A quick tap is a flick
    /// back to the last tab and a panel flashing up for it is noise, so the
    /// switch happens with no panel at all if `⌃` comes up first. Held
    /// longer, the panel is there. The Command Bar's own deadline, for its
    /// reason: longer than this and a held key reads as nothing happening.
    static var revealDelay: TimeInterval { CommandBarMetrics.openDeadline }

    /// The panel for `count` cards, laid out as `TabSwitcherGrid` lays them.
    static func panelSize(for count: Int) -> CGSize {
        let grid = TabSwitcherGrid(count: count)
        let columns = CGFloat(grid.columns), rows = CGFloat(grid.rows)
        return CGSize(
            width: columns * cardSize.width + max(columns - 1, 0) * cardGap + 2 * padding,
            height: rows * cardSize.height + max(rows - 1, 0) * cardGap + 2 * padding
        )
    }
}

/// The glass and the cards on it: the whole of the panel's content.
@MainActor
final class TabSwitcherView: NSView {

    /// A card was clicked.
    var onPick: ((Int) -> Void)?

    private(set) var cards: [TabSwitcherCard] = []
    /// How the cards are laid out, for ↑ and ↓.
    let grid: TabSwitcherGrid

    init(items: [TabSwitcherItem]) {
        grid = TabSwitcherGrid(count: items.count)
        super.init(frame: NSRect(origin: .zero, size: TabSwitcherMetrics.panelSize(for: items.count)))
        wantsLayer = true
        Glass.apply(.popover, to: self, cornerRadius: TabSwitcherMetrics.panelRadius)

        for (index, item) in items.enumerated() {
            let card = TabSwitcherCard(item: item)
            card.onActivate = { [weak self] in self?.onPick?(index) }
            addSubview(card)
            cards.append(card)
        }

        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(String(localized: "Tab Switcher"))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    // MARK: - Content

    /// Lights the card at `index` and no other.
    func select(_ index: Int) {
        for (position, card) in cards.enumerated() { card.isSelected = position == index }
    }

    func setPicture(_ image: NSImage, at index: Int) {
        guard cards.indices.contains(index) else { return }
        cards[index].setPicture(image)
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        Tokens.Motion.immediately(place)
    }

    private func place() {
        let metrics = TabSwitcherMetrics.self
        let card = metrics.cardSize
        let gap = metrics.cardGap
        for (index, view) in cards.enumerated() {
            let (row, column) = grid.place(index)
            view.frame = NSRect(
                x: metrics.padding + CGFloat(column) * (card.width + gap),
                // The first row on top: the view is not flipped.
                y: metrics.padding + CGFloat(grid.rows - 1 - row) * (card.height + gap),
                width: card.width,
                height: card.height
            )
        }
    }

    override var mouseDownCanMoveWindow: Bool { false }

    // MARK: - The panel

    /// A borderless panel holding `view`, centred on `host` and kept on its
    /// screen.
    ///
    /// Non-activating and never key, like §14.3's credential picker: the
    /// browser window keeps the keyboard, which is where the `⌃` release that
    /// ends the switch has to arrive. A child window, so it travels with the
    /// browser window, joins it in fullscreen and closes with it.
    static func panel(holding view: TabSwitcherView, over host: NSWindow) -> NSPanel {
        let size = view.frame.size
        let panel = NSPanel(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // The window's own shadow, which follows the glass's rounded shape. A
        // layer shadow on the view would be cut off at the panel's edge.
        panel.hasShadow = true
        panel.level = .floating
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = true
        panel.collectionBehavior = [.transient, .ignoresCycle]
        panel.animationBehavior = .none
        panel.contentView = view
        panel.setFrame(frame(size: size, centredOn: host.frame, within: host.screen?.visibleFrame), display: false)
        return panel
    }

    /// Centred on the window, then pulled back onto the screen if a window
    /// near an edge would push it off.
    static func frame(size: CGSize, centredOn window: CGRect, within screen: CGRect?) -> CGRect {
        var origin = CGPoint(
            x: (window.midX - size.width / 2).rounded(),
            y: (window.midY - size.height / 2).rounded()
        )
        if let screen {
            origin.x = min(max(origin.x, screen.minX), max(screen.maxX - size.width, screen.minX))
            origin.y = min(max(origin.y, screen.minY), max(screen.maxY - size.height, screen.minY))
        }
        return CGRect(origin: origin, size: size)
    }
}
