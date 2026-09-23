//
//  TopBarTabRow.swift
//  Luna
//
//  An open tab, or a folder's header, on §4's bar: §3.4's own row, laid on its
//  side.
//
//  Not a look-alike. The view inside is `SidebarRowView` — the same favicon at
//  the same inset, the same title faded rather than cut, the same unread dot,
//  loading shimmer, speaker, close glyph and folder chevron — configured from
//  the same `SidebarRowContent`. The bar and the column draw one tab, so they
//  draw it with one class. Like the column's rows it draws no fill of its own:
//  the selected pill and the hover pill are two `RowPillView`s the strip moves
//  between rows, and that is what makes the selection slide rather than blink.
//
//  The host exists for one reason. A column row is the table's full width and
//  paints its pill `rowInset` inside itself, so on a bar, where rows stand side
//  by side, two neighbours' insets would overlap and the left one's margin
//  would take the right one's clicks. The host is exactly the pill's box and
//  carries the row a little outside it, so the hit area is what is drawn.
//

import AppKit

@MainActor
final class TopBarTabRow: NSView {

    let row = SidebarRowView()
    /// The press, handed to the strip whole: it decides whether a press on a
    /// row is a click or the start of §6.6's lift.
    var onPress: ((NSEvent) -> Void)?
    var onHover: ((Bool) -> Void)?
    var menuBuilder: (() -> NSMenu?)?

    private var tracking: NSTrackingArea?
    private(set) var content = SidebarRowContent()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(row)
        setAccessibilityElement(true)
        setAccessibilityRole(.radioButton)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code")
    }

    func configure(_ next: SidebarRowContent) {
        content = next
        row.configure(next)
        setAccessibilityLabel(next.title)
        toolTip = next.title
    }

    // MARK: - Size

    /// The pill a row needs for `content`: its favicon, its whole title, and
    /// the chevron after a folder's name — the column's own insets, measured
    /// rather than guessed, so the title's fade only starts when a title is
    /// longer than the bar will give it.
    static func pillWidth(for content: SidebarRowContent) -> CGFloat {
        measure.stringValue = content.title
        let chevron = content.disclosure == nil
            ? 0
            : Tokens.Metric.groupChevronSlot.width + Tokens.Metric.groupChevronGap
        let unread = content.hasUnread ? Tokens.Metric.spaceDot + Tokens.Metric.rowInset : 0
        let width = Tokens.Metric.rowTitleInset + ceil(measure.intrinsicContentSize.width) + chevron + unread
        return min(max(width, TopBarMetrics.rowFloor), TopBarMetrics.rowCeiling)
    }

    /// The same face the row draws its title in, so the measurement is of the
    /// thing that will be drawn.
    private static let measure: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.font = Tokens.TypeScale.sidebarRow
        return label
    }()

    // MARK: - Geometry

    override func layout() {
        super.layout()
        // The row is a column row: `rowInset` either side of its pill and
        // `rowPillInset` above and below it.
        Tokens.Motion.immediately {
            row.frame = bounds.insetBy(dx: -Tokens.Metric.rowInset, dy: -Tokens.Metric.rowPillInset)
        }
    }

    /// The row's trailing glyph is a control of its own and takes its own
    /// click; everything else on the pill is the row's.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let superview else { return nil }
        let local = convert(point, from: superview)
        guard bounds.contains(local) else { return nil }
        if let inner = row.hitTest(local), inner !== row { return inner }
        return self
    }

    // MARK: - Pointer

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }

    override func mouseDown(with event: NSEvent) { onPress?(event) }

    override func menu(for event: NSEvent) -> NSMenu? {
        menuBuilder?() ?? super.menu(for: event)
    }

    /// §4: a row is not bar, so it does not move the window.
    override var mouseDownCanMoveWindow: Bool { false }
}
