//
//  SettingsAccountRow.swift
//  Luna
//
//  The account row at the head of Settings' column, between the search field
//  and the section list: the user's picture, their name and "iCloud", as
//  macOS's own settings head their column. It opens the iCloud page.
//
//  A list row, not a button (CLAUDE.md): it answers the pointer the way the
//  section rows under it do — no plate of its own, `RowPillView`'s glass on
//  hover and while its page is showing, and no swell. It had a bordered plate
//  that swelled, and it read as a card dropped on the column rather than the
//  first entry in it.
//
//  The subtitle is "iCloud", not the sync status: every status line but two
//  was cut off at the column's width. The status is the page's first row,
//  and the row's tooltip.
//

import AppKit
import BrowserKit
import OpenDirectory

@MainActor
final class SettingsAccountRow: NSView {

    var onActivate: (() -> Void)?

    /// The iCloud page is showing.
    var isOn = false { didSet { if isOn != oldValue { refresh() } } }

    var status: SyncStatus { didSet { describe() } }

    /// The section list's two fills, on the same terms: the selected pill
    /// while the page is showing, the hover lift otherwise.
    private let selectionPill = RowPillView(role: .selected)
    private let hoverPill = RowPillView(role: .hover)
    private let name: String
    private let avatar = NSView()
    private let nameLabel: NSTextField
    private let subtitle = NSTextField(labelWithString: String(localized: "iCloud"))
    private var isHovering = false { didSet { if isHovering != oldValue { refresh() } } }

    init(name: String = NSFullUserName(), picture: NSImage? = SettingsAccountRow.loginPicture(), status: SyncStatus) {
        self.name = name
        self.status = status
        nameLabel = NSTextField(labelWithString: name)
        super.init(frame: .zero)
        for pill in [selectionPill, hoverPill] {
            pill.alphaValue = 0
            addSubview(pill)
        }

        avatar.wantsLayer = true
        avatar.layer?.cornerRadius = SettingsMetrics.accountAvatar / 2
        avatar.layer?.masksToBounds = true
        let face: NSView
        if let picture {
            let image = NSImageView(image: picture)
            image.imageScaling = .scaleProportionallyUpOrDown
            face = image
        } else {
            let initials = NSTextField(labelWithString: Self.initials(of: name))
            initials.font = Tokens.TypeScale.settingsHeading
            initials.alignment = .center
            face = initials
        }
        avatar.addSubview(face)

        nameLabel.font = Tokens.TypeScale.settingsAccountName
        subtitle.font = Tokens.TypeScale.settingsCaption
        for label in [nameLabel, subtitle] {
            label.lineBreakMode = .byTruncatingTail
            label.cell?.usesSingleLineMode = true
        }
        for view in [avatar, nameLabel, subtitle] { addSubview(view) }

        setAccessibilityElement(true)
        setAccessibilityRole(.radioButton)
        setAccessibilityValue(false)
        describe()
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    /// The first letters of the first and last words: "Jane Q Appleseed" is JA.
    static func initials(of name: String) -> String {
        let words = name.split(separator: " ")
        return [words.first, words.count > 1 ? words.last : nil]
            .compactMap { $0?.first.map { String($0).uppercased() } }
            .joined()
    }

    /// The macOS login picture, from the local directory record. Not Contacts:
    /// "Me" in Contacts asks for permission, and this does not.
    static func loginPicture() -> NSImage? {
        guard let node = try? ODNode(session: ODSession.default(), type: ODNodeType(kODNodeTypeLocalNodes)),
              let record = try? node.record(
                  withRecordType: kODRecordTypeUsers,
                  name: NSUserName(),
                  attributes: [kODAttributeTypeJPEGPhoto]
              ),
              let data = (try? record.values(forAttribute: kODAttributeTypeJPEGPhoto))?.first as? Data
        else { return nil }
        return NSImage(data: data)
    }

    private func describe() {
        toolTip = status.line()
        setAccessibilityLabel(String(localized: "iCloud, \(name), \(status.line())"))
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        Tokens.Motion.immediately {
            for pill in [selectionPill, hoverPill] where pill.alphaValue > 0 { pill.move(to: bounds, spec: nil) }
            let side = SettingsMetrics.accountAvatar
            let margin = ((bounds.height - side) / 2).rounded()
            avatar.frame = NSRect(x: margin, y: margin, width: side, height: side)
            for face in avatar.subviews {
                let height = face is NSTextField ? ceil(face.fittingSize.height) : side
                face.frame = NSRect(x: 0, y: ((side - height) / 2).rounded(), width: side, height: height)
            }
            let left = avatar.frame.maxX + Tokens.Metric.chromeGap
            let width = max(bounds.width - left - margin, 0)
            let nameHeight = ceil(nameLabel.fittingSize.height)
            let subtitleHeight = ceil(subtitle.fittingSize.height)
            let top = ((bounds.height + nameHeight + subtitleHeight) / 2).rounded()
            nameLabel.frame = NSRect(x: left, y: top - nameHeight, width: width, height: nameHeight)
            subtitle.frame = NSRect(x: left, y: top - nameHeight - subtitleHeight, width: width, height: subtitleHeight)
        }
    }

    // MARK: - Ink

    /// The section rows' hierarchy: full-strength ink for the selected row
    /// only, and the subtitle a step under whatever the name is set in.
    private func refresh() {
        setAccessibilityValue(isOn)
        nameLabel.textColor = isOn ? Tokens.Text.primary : Tokens.Text.secondary
        subtitle.textColor = Tokens.Text.tertiary
        (avatar.subviews.first as? NSTextField)?.textColor = Tokens.Accent.onTint
        effectiveAppearance.performAsCurrentDrawingAppearance {
            self.avatar.layer?.backgroundColor = Tokens.Accent.tint.cgColor
        }
        show(selectionPill, isOn, spec: Tokens.Motion.selectedRowMove)
        // Never both: a hover lift under the selected pill is a second wash on
        // a row that already has one.
        show(hoverPill, isHovering && !isOn, spec: Tokens.Motion.rowHover)
    }

    private func show(_ pill: RowPillView, _ shown: Bool, spec: MotionSpec) {
        if shown {
            pill.move(to: bounds, spec: spec)
        } else {
            pill.fade(to: 0)
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refresh()
    }

    // MARK: - Pointer

    /// The whole plate is the target; the labels inside it are decoration.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let superview, bounds.contains(convert(point, from: superview)) else { return nil }
        return self
    }

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

    /// On the way down, as a section row picks its page.
    override func mouseDown(with event: NSEvent) { onActivate?() }

    override func accessibilityPerformPress() -> Bool {
        onActivate?()
        return true
    }

    override var mouseDownCanMoveWindow: Bool { false }
}
