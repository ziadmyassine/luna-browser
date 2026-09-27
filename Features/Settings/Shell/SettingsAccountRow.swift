//
//  SettingsAccountRow.swift
//  Luna
//
//  The account row at the head of Settings' column, between the search field
//  and the section list: the user's picture, their name, and what iCloud sync
//  is doing (docs/SYNC-PLAN.md §5). It opens the iCloud page.
//
//  A button, not a list row (CLAUDE.md): it stands on a plate of its own
//  outside `SettingsSectionList`, so it answers with the wash and the swell
//  rather than the list's sliding pill. While its page is showing it holds
//  the press's wash, as a chosen `ExtensionCardButton` does.
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

    private let name: String
    private let avatar = NSView()
    private let nameLabel: NSTextField
    private let subtitle = NSTextField(labelWithString: "")
    private var isHovering = false { didSet { if isHovering != oldValue { refresh() } } }
    private var isPressed = false {
        didSet {
            guard isPressed != oldValue else { return }
            refresh()
            Tokens.Motion.swell(self, to: isPressed ? Tokens.Motion.pressSwell : 1)
        }
    }

    init(name: String = NSFullUserName(), picture: NSImage? = SettingsAccountRow.loginPicture(), status: SyncStatus) {
        self.name = name
        self.status = status
        nameLabel = NSTextField(labelWithString: name)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.cornerRadius = SettingsMetrics.rowCornerRadius
        layer?.borderWidth = Tokens.Metric.hairline

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
        setAccessibilityRole(.button)
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
        subtitle.stringValue = status.line()
        setAccessibilityLabel(String(localized: "iCloud, \(name), \(status.line())"))
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        Tokens.Motion.immediately {
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

    private func refresh() {
        nameLabel.textColor = Tokens.Text.primary
        subtitle.textColor = Tokens.Text.secondary
        (avatar.subviews.first as? NSTextField)?.textColor = Tokens.Accent.onTint
        let fill: NSColor? = isOn || isPressed ? Tokens.Surface.selected : (isHovering ? Tokens.Surface.hover : nil)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            self.layer?.borderColor = Tokens.Line.border.cgColor
            self.avatar.layer?.backgroundColor = Tokens.Accent.tint.cgColor
            Tokens.Motion.wash(self.layer, to: fill)
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

    override func mouseDown(with event: NSEvent) { isPressed = true }

    override func mouseDragged(with event: NSEvent) {
        isPressed = bounds.contains(convert(event.locationInWindow, from: nil))
    }

    override func mouseUp(with event: NSEvent) {
        let inside = isPressed
        isPressed = false
        if inside { onActivate?() }
    }

    override func accessibilityPerformPress() -> Bool {
        onActivate?()
        return true
    }

    override var mouseDownCanMoveWindow: Bool { false }
}
