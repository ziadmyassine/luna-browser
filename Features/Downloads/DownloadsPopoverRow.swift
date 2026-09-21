//
//  DownloadsPopoverRow.swift
//  Luna
//
//  The one row inside §5's popover:
//  `[file-type icon 34] [filename, middle-truncated, 14 pt] [confirm 30]`,
//  plus the §5.1 particle sweep laid over the filename.
//
//  Middle truncation is required, not stylistic (§5). A statement called
//  `97103328759-2026-01-01-2026-08-31.pdf` has to keep both ends: head
//  truncation destroys the account number, tail truncation destroys the
//  extension, and either leaves the user unable to tell which file landed.
//
//  It is spelled with a paragraph style rather than
//  `NSTextField.lineBreakMode` because the cell resets the mode when the
//  string is set — see `applyTokens`.
//

import AppKit

/// §5: `[file-type icon 34] [filename, middle-truncated, 14 pt] [confirm 30]`.
@MainActor
final class DownloadsPopoverRowView: NSView {

    private let item: DownloadItem
    private let iconView = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let confirm = NSButton()
    private let confirmBacking: NSView
    private let sweep = ParticleSweepView(frame: .zero)
    private let onConfirm: () -> Void

    /// §5 gives the icon, the font and the button but no padding. The icon is
    /// 34 in a 58 pt row, so the row's own symmetry fixes it at 12 — used for
    /// the outer inset and the gap alike.
    private var inset: CGFloat {
        (Tokens.Metric.downloadsPopover.height - Tokens.Metric.downloadsFileIcon) / 2
    }

    init(item: DownloadItem, onConfirm: @escaping () -> Void) {
        self.item = item
        self.onConfirm = onConfirm
        self.confirmBacking = Glass.backing(
            .control,
            cornerRadius: Tokens.Metric.downloadsConfirm.cornerRadius
        )
        super.init(frame: .zero)

        iconView.image = item.icon
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.setAccessibilityElement(false)
        addSubview(iconView)

        label.maximumNumberOfLines = 1
        label.cell?.truncatesLastVisibleLine = true
        label.setAccessibilityLabel(item.accessibilityLabel)
        addSubview(label)

        addSubview(sweep)

        // Sized before it is in the tree: a glass backing that first lays out
        // at zero has nothing for autoresizing to scale from.
        confirmBacking.setFrameSize(Tokens.Metric.downloadsConfirm.size)
        addSubview(confirmBacking)

        confirm.isBordered = false
        confirm.bezelStyle = .regularSquare
        confirm.imagePosition = .imageOnly
        confirm.image = NSImage(
            systemSymbolName: "checkmark",
            accessibilityDescription: String(localized: "Dismiss")
        )
        confirm.target = self
        confirm.action = #selector(confirmTapped)
        confirm.setAccessibilityLabel(String(localized: "Dismiss"))
        // Return also confirms, for anyone who does focus the panel.
        confirm.keyEquivalent = "\r"
        confirmBacking.addSubview(confirm)

        applyTokens()
        // Increase Contrast is not an `NSAppearance` on macOS 26.5, so nothing
        // invalidates these colours for us (contract rule 4).
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(applyTokens),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    @objc private func confirmTapped() { onConfirm() }

    /// Middle truncation, through the paragraph style rather than
    /// `NSTextField.lineBreakMode` — the cell resets the mode when the string
    /// is set, and the attributed string is the only spelling that survives it.
    @objc private func applyTokens() {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingMiddle
        let font = Tokens.TypeScale.downloadFilename
        label.textColor = Tokens.Text.primary
        label.font = font
        label.attributedStringValue = NSAttributedString(
            string: item.filename,
            attributes: [
                .font: font,
                .foregroundColor: Tokens.Text.primary,
                .paragraphStyle: paragraph
            ]
        )
        confirm.contentTintColor = Tokens.Text.primary
        confirm.symbolConfiguration = NSImage.SymbolConfiguration(
            pointSize: font.pointSize,
            weight: .semibold
        )
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        let icon = Tokens.Metric.downloadsFileIcon
        let button = Tokens.Metric.downloadsConfirm
        iconView.frame = CGRect(x: inset, y: (bounds.height - icon) / 2, width: icon, height: icon)
        confirmBacking.frame = CGRect(
            x: bounds.width - inset - button.width,
            y: (bounds.height - button.height) / 2,
            width: button.width,
            height: button.height
        )
        confirm.frame = confirmBacking.bounds
        let textLeft = iconView.frame.maxX + inset
        let height = ceil(Tokens.TypeScale.downloadFilename.boundingRectForFont.height)
        label.frame = CGRect(
            x: textLeft,
            y: (bounds.height - height) / 2,
            width: max(confirmBacking.frame.minX - inset - textLeft, 0),
            height: height
        )
    }

    /// §5.1. Under Reduce Motion this is a no-op and the filename simply
    /// appears — which is the whole of the required behaviour.
    func runSweep() { sweep.run(sampling: label) }
}
