//
//  SpacePreviewView.swift
//  Luna
//
//  The Space on the other side of the swipe, drawn so it can be seen arriving.
//
//  A page turn has to show the page. §30.9 used to lean the column 40 pt and
//  dim it, which says "something is happening" and nothing else: the Space you
//  were reaching for stayed invisible until the gesture had committed, so the
//  choice was made blind. This is the other half of the motion — the incoming
//  Space translating in from the edge the fingers are heading toward.
//
//  It is a still, not the list. §3.4's list is one `NSTableView` bound to the
//  active Space, and pointing it at a Space the window is not in would mean
//  tearing down and rebuilding the thing the user is about to be handed. A page
//  turn needs a picture: nothing here hovers, scrolls, closes a tab or takes a
//  click, and it is thrown away the moment the gesture ends, cross-faded by
//  §6's `spaceSwitchCrossfade`.
//
//  The picture is of the whole column, pinned tabs included. It used to be a
//  flat run of rows built from every tab, which put the §3.3 tiles in as
//  ordinary rows — so a Space with pinned tabs arrived looking like a Space
//  without any and rearranged itself the moment the real column took over, and
//  that correction is the one frame the cross-fade exists to hide. The grid is
//  drawn as a grid, with `EssentialsGridView`'s own slot arithmetic.
//
//  Only what fits is drawn. A Space with sixty tabs is a Space whose first
//  dozen rows are what identifies it at a glance, and drawing the other
//  forty-eight into a view that lives for 300 ms is work nobody sees.
//

import AppKit
import BrowserKit

/// A still of one Space's column: its §8.2a wash, its §3.3 tiles and as many
/// §3.4 rows as the frame has room for.
@MainActor
final class SpacePreviewView: NSView {

    private let wash = SpaceWashView()
    private var tiles: [SpacePreviewTile] = []
    private var rows: [NSView] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        isHidden = true
        addSubview(wash)
        // Decorative, and short-lived: the Space it shows is announced by the
        // list that replaces it, which is the one VoiceOver should be reading.
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    /// Whether the still is drawing a Space at all.
    ///
    /// False for the plane the `+` stands on, which is what a swipe past the
    /// last Space shows — and false is a picture, not an absence: see
    /// ``showBlank()``.
    var isShowingASpace: Bool { !tiles.isEmpty || !rows.isEmpty }

    /// Never takes a click: the gesture owns the pointer while this is up.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// - Parameters:
    ///   - column: the Space's list, built exactly as the real one is.
    ///   - icon: the favicon for a tab, from whichever cache the caller has —
    ///     the live session first, §4.7's on-disk store after it. Nil draws the
    ///     same placeholder a cold row draws.
    ///
    /// The still is drawn from `SidebarList.rows` rather than from a flat run of
    /// tabs with a head bolted on. The head was written when §3.4 began with New
    /// Tab and a rule under it; §3.4b put the rule *above* New Tab and takes it
    /// away entirely for a Space with nothing saved, so a hard-coded head drew a
    /// rule that was both in the wrong place and always there — one that
    /// appeared for the length of a swipe and vanished when the real column
    /// arrived. Asking the list means the still cannot disagree with it again,
    /// and group headers come along for free.
    func show(column: SidebarList, gradient: GradientPair, icon: (Tab) -> NSImage?) {
        wash.show(gradient)
        clear()
        tiles = column.essentials.map { tab in
            let tile = SpacePreviewTile(icon: icon(tab))
            addSubview(tile)
            return tile
        }
        rows = column.rows.indices.map { view(forRow: $0, in: column, icon: icon) }
        for row in rows { addSubview(row) }
        needsLayout = true
    }

    /// The Space past the last one: a plane with nothing on it.
    ///
    /// Not an empty Space's column. An empty Space is a Space and still draws
    /// §30.6's `New Tab` row; the one being made has no column yet, and the
    /// only thing standing on this plane is the `+` the fingers are closing the
    /// ring on. The neutral gradient paints nothing, so what shows through is
    /// the window's own chrome.
    func showBlank() {
        wash.show(Tokens.Gradient.neutral)
        clear()
    }

    private func clear() {
        for tile in tiles { tile.removeFromSuperview() }
        for row in rows { row.removeFromSuperview() }
        tiles = []
        rows = []
        needsLayout = true
    }

    private func view(forRow row: Int, in column: SidebarList, icon: (Tab) -> NSImage?) -> NSView {
        switch column.rows[row] {
        case .separator:
            return SpacePreviewRule()
        case .addTab:
            return SpacePreviewRow(title: String(localized: "New Tab"), icon: Self.plus, isDimmed: true)
        case .group:
            guard let group = column.group(at: row) else { return SpacePreviewRule() }
            return SpacePreviewRow(
                title: group.name,
                icon: NSImage(systemSymbolName: group.symbolName, accessibilityDescription: nil),
                isDimmed: true
            )
        case .tab:
            guard let tab = column.tab(at: row) else { return SpacePreviewRule() }
            return SpacePreviewRow(
                title: tab.title.isEmpty ? (tab.url.host() ?? "") : tab.title,
                icon: icon(tab),
                isDimmed: false,
                indent: column.group(ofTab: tab.id) == nil ? 0 : Tokens.Metric.groupIndent
            )
        }
    }

    private static let plus = NSImage(systemSymbolName: "plus", accessibilityDescription: nil)?
        .withSymbolConfiguration(.init(pointSize: Tokens.Metric.faviconSize, weight: .regular))

    override func layout() {
        super.layout()
        // Bounds-derived frames never animate — see `Motion.immediately`.
        Tokens.Motion.immediately { placeContents() }
    }

    private func placeContents() {
        wash.frame = bounds
        // The grid hangs from the top of the page, exactly as §3.3 hangs from
        // under the URL pill, and the list starts where it ends.
        let gridHeight = EssentialsGridView.height(forTiles: tiles.count)
        let grid = NSRect(x: 0, y: bounds.maxY - gridHeight, width: bounds.width, height: gridHeight)
        for (index, tile) in tiles.enumerated() {
            tile.frame = EssentialsGridView.slotRect(at: index, of: tiles.count, in: grid)
        }
        var top = grid.minY
        for row in rows {
            let height = row is SpacePreviewRule ? Tokens.Metric.separatorRowHeight : Tokens.Metric.rowHeight
            top -= height
            row.frame = NSRect(x: 0, y: top, width: bounds.width, height: height).integral
            // Off the bottom is off the picture. See the file header.
            row.isHidden = top < bounds.minY
        }
    }
}

/// One §3.3 tile of the still: the plate and the favicon, and nothing that
/// makes a tile a control — no glow, no hover, no menu.
///
/// The plate, and deliberately not the glass. A real tile is a `.dormant`
/// `GlassButton`: at rest it wears `Surface.well` and a hairline, and the
/// material only comes up under the pointer or on the tab you are on. Drawing
/// the material here lit every tile in the Space you were swiping toward, so
/// every pinned tab arrived looking selected — which is what "all the pinned
/// tabs are highlighted" was. A still of a column nobody is pointing at has
/// nothing lit in it.
@MainActor
final class SpacePreviewTile: NSView {

    private let icon = NSImageView()

    init(icon image: NSImage?) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.cornerRadius = Tokens.Metric.essentialsTile.cornerRadius
        icon.image = image ?? SpacePreviewRow.placeholder
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.contentTintColor = image == nil ? Tokens.Text.secondary : nil
        addSubview(icon)
        applyTokens()
        setAccessibilityElement(false)
    }

    private func applyTokens() {
        layer?.backgroundColor = Tokens.Surface.well.cgColor
        layer?.borderWidth = Tokens.Metric.hairline
        layer?.borderColor = Tokens.Line.border.cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyTokens()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    override func layout() {
        super.layout()
        Tokens.Motion.immediately {
            let side = Tokens.Metric.essentialsIcon
            icon.frame = NSRect(
                x: (bounds.width - side) / 2,
                y: (bounds.height - side) / 2,
                width: side,
                height: side
            ).pixelAligned
        }
    }
}

/// §3.4's rule between the command row and the tabs, as the still draws it.
@MainActor
final class SpacePreviewRule: NSView {

    override func draw(_ dirtyRect: NSRect) {
        Tokens.Line.hairline.setFill()
        NSRect(
            x: 0,
            y: (bounds.height - Tokens.Metric.hairline) / 2,
            width: bounds.width,
            height: Tokens.Metric.hairline
        ).fill()
    }
}

/// One row of the still: §3.4's favicon square and its title, at §3.4's insets,
/// and nothing else. No pill, no hover, no close chip — a row in a picture is
/// not a row you can use, and drawing the affordances would be a lie about
/// what this view does.
@MainActor
final class SpacePreviewRow: NSView {

    private let icon = NSImageView()
    private let title = NSTextField(labelWithString: "")

    private let indent: CGFloat

    init(title text: String, icon image: NSImage?, isDimmed: Bool, indent: CGFloat = 0) {
        self.indent = indent
        super.init(frame: .zero)
        icon.image = image ?? Self.placeholder
        icon.imageScaling = .scaleProportionallyUpOrDown
        title.stringValue = text
        title.lineBreakMode = .byTruncatingTail
        addSubview(icon)
        addSubview(title)
        applyTokens(isTinted: image == nil || isDimmed)
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    static let placeholder = NSImage(systemSymbolName: "globe", accessibilityDescription: nil)?
        .withSymbolConfiguration(.init(pointSize: Tokens.Metric.faviconSize, weight: .regular))

    private func applyTokens(isTinted: Bool) {
        title.font = Tokens.TypeScale.sidebarRow
        // The still is of a Space you are not in yet, so every row in it is an
        // inactive row: §3.4's secondary ink, never the selected pill's.
        title.textColor = Tokens.Text.secondary
        icon.contentTintColor = isTinted ? Tokens.Text.secondary : nil
    }

    override func layout() {
        super.layout()
        Tokens.Motion.immediately {
            let side = Tokens.Metric.faviconSize
            icon.frame = NSRect(
                x: Tokens.Metric.rowFaviconInset + indent,
                y: (bounds.height - side) / 2,
                width: side,
                height: side
            ).pixelAligned
            // The same column and the same box a real row gives its title.
            // A label draws its one line at the top of whatever frame it is
            // given, so handing it the full row height put "New Tab" a third of
            // a row above the favicon beside it — visible for the length of a
            // swipe and corrected the moment the real list arrived. The box is
            // the type's own height, centred, exactly as `SidebarRowView` does
            // it.
            let column = SidebarRowView.titleColumn(
                inRowOfWidth: bounds.width,
                hasUnread: false,
                slotOccupied: false,
                indent: indent
            )
            let height = title.intrinsicContentSize.height
            title.frame = NSRect(
                x: column.x,
                y: (bounds.height - height) / 2,
                width: column.width,
                height: height
            ).integral
        }
    }
}
