//
//  SpacePreviewView.swift
//  Luna
//
//  The Space on the other side of the swipe, drawn so it can be seen arriving.
//
//  **A page turn has to show the page.** §30.9 used to lean the column 40 pt
//  and dim it, which says "something is happening" and nothing else: the Space
//  you were reaching for stayed invisible until the gesture had already
//  committed, so the choice was made blind. This is the other half of the
//  motion — the incoming Space, translating in from the edge the fingers are
//  heading toward while the live one translates out.
//
//  **It is a still, and it is not the list.** §3.4's list is an `NSTableView`
//  bound to the active Space: there is exactly one, it recycles its rows, and
//  pointing it at a Space the window is not in would mean tearing down and
//  rebuilding the thing the user is about to be handed. What a page turn needs
//  is a picture, not a working list — nothing here hovers, scrolls, closes a
//  tab or takes a click. It is thrown away the moment the gesture ends, and
//  what replaces it is the real list, cross-faded by §6's
//  `spaceSwitchCrossfade` so the seam is not a frame anyone can catch.
//
//  Only what fits is drawn. A Space with sixty tabs is a Space whose first
//  dozen rows are what identifies it at a glance, and drawing the other
//  forty-eight into a view that lives for 300 ms is work nobody sees.
//

import AppKit
import BrowserKit

/// A still of one Space's column: its §8.2a wash, its §3.3 tiles' worth of
/// height, and as many §3.4 rows as the frame has room for.
@MainActor
final class SpacePreviewView: NSView {

    private let wash = SpaceWashView()
    private var rows: [SpacePreviewRow] = []

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

    /// Never takes a click: the gesture owns the pointer while this is up.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// - Parameter icon: the favicon for a tab, from whichever cache the caller
    ///   has — the live session first, §4.7's on-disk store after it. Nil draws
    ///   the same placeholder a cold row draws.
    func show(tabs: [Tab], gradient: GradientPair, icon: (Tab) -> NSImage?) {
        wash.show(gradient)
        for row in rows { row.removeFromSuperview() }
        rows = tabs.map { tab in
            let row = SpacePreviewRow(title: tab.title.isEmpty ? (tab.url.host() ?? "") : tab.title, icon: icon(tab))
            addSubview(row)
            return row
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        // Bounds-derived frames never animate — see `Motion.immediately`.
        Tokens.Motion.immediately { placeContents() }
    }

    private func placeContents() {
        wash.frame = bounds
        let pitch = Tokens.Metric.rowHeight
        var top = bounds.maxY
        for row in rows {
            top -= pitch
            row.frame = NSRect(x: 0, y: top, width: bounds.width, height: pitch).integral
            // Off the bottom is off the picture. See the file header.
            row.isHidden = top < bounds.minY
        }
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

    init(title text: String, icon image: NSImage?) {
        super.init(frame: .zero)
        icon.image = image ?? NSImage(systemSymbolName: "globe", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: Tokens.Metric.faviconSize, weight: .regular))
        icon.imageScaling = .scaleProportionallyUpOrDown
        title.stringValue = text
        title.lineBreakMode = .byTruncatingTail
        addSubview(icon)
        addSubview(title)
        applyTokens(hasFavicon: image != nil)
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    private func applyTokens(hasFavicon: Bool) {
        title.font = Tokens.TypeScale.sidebarRow
        // The still is of a Space you are not in yet, so every row in it is an
        // inactive row: §3.4's secondary ink, never the selected pill's.
        title.textColor = Tokens.Text.secondary
        icon.contentTintColor = hasFavicon ? nil : Tokens.Text.secondary
    }

    override func layout() {
        super.layout()
        Tokens.Motion.immediately {
            let side = Tokens.Metric.faviconSize
            icon.frame = NSRect(
                x: Tokens.Metric.rowFaviconInset,
                y: (bounds.height - side) / 2,
                width: side,
                height: side
            ).pixelAligned
            let leading = Tokens.Metric.rowTitleInset
            title.frame = NSRect(
                x: leading,
                y: 0,
                width: max(bounds.width - leading - Tokens.Metric.rowInset, 0),
                height: bounds.height
            ).integral
        }
    }
}
