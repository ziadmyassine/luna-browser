//
//  FindBarView.swift
//  Luna
//
//  §18.1's find field: a glass capsule in the page's top trailing corner with
//  the query, the count, previous and next, and close. What it searches and
//  when is `FindController`'s; this is the capsule and the keys typed into it.
//
//  Built from the toast's parts — `Glass.popover` at §4's capsule height on
//  `ControlSurfaceView` — because it is the same kind of thing: something of
//  Luna's standing over the page, not part of it.
//

import AppKit
import BrowserKit

@MainActor
final class FindBarView: NSView, NSTextFieldDelegate {

    var onQueryChange: ((String) -> Void)?
    var onNext: (() -> Void)?
    var onPrevious: (() -> Void)?
    var onClose: (() -> Void)?

    let field = NSTextField()
    let count = NSTextField(labelWithString: "")
    let previous = FindBarView.button("chevron.up", String(localized: "Previous Match"))
    let next = FindBarView.button("chevron.down", String(localized: "Next Match"))
    let close = FindBarView.button("xmark", String(localized: "Close Find"))
    private let icon = NSImageView()

    /// `.none`: the capsule is the material, and swells for them.
    private static func button(_ symbol: String, _ label: String) -> GlassButton {
        GlassButton(
            shape: Tokens.Metric.controlCircle,
            symbolName: symbol,
            pointSize: Tokens.Metric.glyphSize,
            label: label,
            glassMode: .none
        )
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        let height = Tokens.Metric.capsuleHeight
        Glass.apply(.popover, to: self, cornerRadius: height / 2).pinToEdges()
        buildField()
        wireButtons()

        // Touching, as `NavCluster`'s halves do: three marks on one material.
        let buttons = NSStackView(views: [previous, next, close])
        buttons.spacing = 0
        let row = NSStackView(views: [icon, field, count, buttons])
        row.orientation = .horizontal
        row.spacing = Tokens.Metric.chromeGap
        row.alignment = .centerY
        row.edgeInsets = NSEdgeInsets(
            top: 0, left: height / 3, bottom: 0, right: (height - Tokens.Metric.controlCircle.height) / 2
        )
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        let width = widthAnchor.constraint(equalToConstant: Tokens.Metric.findBarWidth)
        // Below required, so a pane narrower than the capsule squeezes the
        // field instead of pushing the capsule off the page.
        width.priority = .defaultHigh
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(equalToConstant: height),
            width
        ])

        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(String(localized: "Find on Page"))
        applyTokens()
        show(nil)
    }

    private func buildField() {
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.delegate = self
        field.setAccessibilityLabel(String(localized: "Find on Page"))
        // The field is the one thing in the capsule that gives way.
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        count.setContentHuggingPriority(.required, for: .horizontal)
        count.setContentCompressionResistancePriority(.required, for: .horizontal)
        count.isHidden = true
    }

    private func wireButtons() {
        previous.onActivate = { [weak self] in self?.pressed { $0.onPrevious?() } }
        next.onActivate = { [weak self] in self?.pressed { $0.onNext?() } }
        close.onActivate = { [weak self] in self?.onClose?() }
        for button in [previous, next, close] {
            button.onPressChange = { [weak self] down in
                guard let self else { return }
                Tokens.Motion.swell(self, to: down ? Tokens.Motion.pressSwell : 1)
            }
        }
        previous.toolTip = String(localized: "Previous Match (⇧⌘G)")
        next.toolTip = String(localized: "Next Match (⌘G)")
        close.toolTip = String(localized: "Close (Esc)")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    private func applyTokens() {
        let font = Tokens.TypeScale.urlPill
        field.font = font
        field.textColor = Tokens.Text.primary
        field.placeholderAttributedString = NSAttributedString(
            string: String(localized: "Find on Page"),
            attributes: [.font: font, .foregroundColor: Tokens.Text.tertiary]
        )
        count.font = Tokens.TypeScale.findCount
        count.textColor = Tokens.Text.secondary
        icon.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: font.pointSize, weight: .medium))
        icon.contentTintColor = Tokens.Text.secondary
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyTokens()
    }

    // MARK: - What it shows

    var query: String {
        get { field.stringValue }
        set { field.stringValue = newValue }
    }

    /// The count for `result`, or nothing: no query yet, a page that changed
    /// under it, or a match the count could not place.
    func show(_ result: FindResult?) {
        let text = Self.countText(for: result)
        count.stringValue = text ?? ""
        count.isHidden = text == nil
        // Nothing to step through when nothing was found.
        let canStep = result?.found ?? !field.stringValue.isEmpty
        previous.isEnabled = canStep
        next.isEnabled = canStep
    }

    static func countText(for result: FindResult?) -> String? {
        guard let result else { return nil }
        guard result.found else { return String(localized: "No matches") }
        guard let match = result.match, let total = result.total else { return nil }
        return result.isCapped ? String(localized: "\(match) of \(total)+") : String(localized: "\(match) of \(total)")
    }

    /// The page's colour, which the capsule takes its appearance from by the
    /// toast's rule (`ControlSurfaceView.setPageColour`): glass composites
    /// what is behind the window, so white ink on it vanishes over a white
    /// site. Set on the capsule rather than read from the layer, which is only
    /// told for the window Luna Control is watching.
    func setPageColour(_ colour: NSColor?) {
        let behind = colour ?? Tokens.Surface.base
        let dark = behind.wantsLightInk(in: (superview ?? self).effectiveAppearance)
        let wanted = NSAppearance(named: dark ? .darkAqua : .aqua)
        guard appearance?.name != wanted?.name else { return }
        appearance = wanted
    }

    // MARK: - Focus

    var hasFocus: Bool {
        guard let editor = field.currentEditor() else { return false }
        return window?.firstResponder === editor
    }

    /// `⌘F` on an open field selects what is in it, so typing replaces it.
    func focusField(selectingAll: Bool) {
        if !hasFocus { window?.makeFirstResponder(field) }
        let end = field.stringValue.utf16.count
        field.currentEditor()?.selectedRange = selectingAll ? NSRange(location: 0, length: end) : NSRange(location: end, length: 0)
    }

    /// A click takes first responder to the button it lands on, and the next
    /// letter typed should still go into the query.
    private func pressed(_ action: (FindBarView) -> Void) {
        let byPointer = NSApp.currentEvent.map { [.leftMouseUp, .leftMouseDown].contains($0.type) } ?? false
        action(self)
        if byPointer { focusField(selectingAll: false) }
    }

    /// A click on the glass between the controls puts the caret in the field.
    override func mouseDown(with event: NSEvent) {
        focusField(selectingAll: false)
    }

    /// §30.1: the window moves by its background, and this is not background.
    override var mouseDownCanMoveWindow: Bool { false }

    // MARK: - Keys

    func controlTextDidChange(_ notification: Notification) {
        onQueryChange?(field.stringValue)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        handle(selector, shift: NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false)
    }

    /// Return is next and Shift-Return previous, as in every Mac find field;
    /// Escape closes. Split from the delegate call so a test can say whether
    /// Shift was down.
    func handle(_ selector: Selector, shift: Bool) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            if shift { onPrevious?() } else { onNext?() }
        case #selector(NSResponder.cancelOperation(_:)):
            onClose?()
        default:
            return false
        }
        return true
    }
}
