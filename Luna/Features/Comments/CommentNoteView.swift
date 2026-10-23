//
//  CommentNoteView.swift
//  Luna
//
//  Comment mode's note field: a glass plate beside the picked element with
//  one text view in it. What the note is written to is `CommentMode`'s; this
//  is the plate and the keys typed into it. Built from the find field's parts
//  (`Glass.popover`, §4's capsule height, `TypeScale.urlPill`) because it is
//  the same kind of thing standing over the page.
//
//  No buttons: Return and Escape both commit and close, Shift-Return is a
//  new line, and nothing typed is ever thrown away.
//

import AppKit
import BrowserKit

@MainActor
final class CommentNoteView: NSView, NSTextViewDelegate {

    /// The text should be written to the comment: a pause in typing, or ⌘S.
    var onSave: (() -> Void)?
    /// Return or Escape: written, then the field goes.
    var onDone: (() -> Void)?

    private(set) var textView = NSTextView()
    private let placeholder = NSTextField(labelWithString: String(localized: "Add a note"))
    private let undo: UndoManager
    private var autosave: Task<Void, Never>?

    /// - Parameter undoManager: the comment set's, so ⌘Z here walks the
    ///   typing and the comments together and never the window's list.
    init(undoManager: UndoManager) {
        undo = undoManager
        super.init(frame: NSRect(x: 0, y: 0, width: Tokens.Metric.findBarWidth, height: Tokens.Metric.capsuleHeight))
        wantsLayer = true
        Glass.apply(.popover, to: self, cornerRadius: Tokens.Metric.capsuleHeight / 2)
        addSubview(placeholder)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(String(localized: "Note"))
        startNote()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    var text: String { textView.string }

    /// An empty field for the next comment, in a new text view. The old one's
    /// typing is still on the undo list, and undoing it into a view whose text
    /// was replaced underneath it crashed the app (measured).
    /// ponytail: those old steps stay on the list and change nothing on screen
    /// when ⌘Z reaches them; a typing list per note, chained to the set's, would drop them.
    func startNote() {
        autosave?.cancel()
        let hadFocus = hasFocus
        textView.removeFromSuperview()
        textView = NSTextView()
        textView.delegate = self
        textView.drawsBackground = false
        textView.isRichText = false
        textView.allowsUndo = true
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.setAccessibilityLabel(String(localized: "Note"))
        addSubview(textView)
        needsLayout = true
        applyTokens()
        textChanged()
        if hadFocus { focus() }
    }

    var hasFocus: Bool { window?.firstResponder === textView }

    func focus() {
        window?.makeFirstResponder(textView)
    }

    /// One line is §4's capsule; each line typed past it adds its own height.
    var fittingHeight: CGFloat {
        guard let layout = textView.layoutManager, let container = textView.textContainer else {
            return Tokens.Metric.capsuleHeight
        }
        container.containerSize = NSSize(width: textWidth, height: .greatestFiniteMagnitude)
        layout.ensureLayout(for: container)
        let lines = max(layout.usedRect(for: container).height, lineHeight)
        return Tokens.Metric.capsuleHeight - lineHeight + lines.rounded(.up)
    }

    /// The page's colour, which the plate takes its appearance from by the
    /// find field's rule (`FindBarView.setPageColour`).
    func setPageColour(_ colour: NSColor?) {
        let behind = colour ?? Tokens.Surface.base
        let dark = behind.wantsLightInk(in: (superview ?? self).effectiveAppearance)
        let wanted = NSAppearance(named: dark ? .darkAqua : .aqua)
        guard appearance?.name != wanted?.name else { return }
        appearance = wanted
    }

    // MARK: - Layout

    private var lineHeight: CGFloat {
        textView.layoutManager?.defaultLineHeight(for: Tokens.TypeScale.urlPill) ?? Tokens.TypeScale.urlPill.pointSize
    }

    /// The find field's ends: a third of the capsule before the text, and after it.
    private var sideInset: CGFloat { Tokens.Metric.capsuleHeight / 3 }
    private var textWidth: CGFloat { bounds.width - 2 * sideInset }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        let top = (Tokens.Metric.capsuleHeight - lineHeight) / 2
        let frame = NSRect(x: sideInset, y: top, width: textWidth, height: bounds.height - 2 * top)
        Tokens.Motion.immediately {
            textView.frame = frame
            placeholder.frame = NSRect(x: sideInset, y: top, width: textWidth, height: lineHeight)
        }
    }

    private func applyTokens() {
        let font = Tokens.TypeScale.urlPill
        textView.font = font
        textView.textColor = Tokens.Text.primary
        textView.insertionPointColor = Tokens.Text.primary
        placeholder.font = font
        placeholder.textColor = Tokens.Text.tertiary
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyTokens()
    }

    /// §30.1: the window moves by its background, and this is not background.
    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) {
        focus()
    }

    // MARK: - Keys

    func undoManager(for view: NSTextView) -> UndoManager? {
        undo
    }

    /// ⌘S writes the note whatever it is bound to elsewhere (the sidebar
    /// toggle by default): a view's key equivalent is asked before the menu's.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard hasFocus, event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
              event.charactersIgnoringModifiers == "s" else { return super.performKeyEquivalent(with: event) }
        autosave?.cancel()
        onSave?()
        return true
    }

    func textDidChange(_ notification: Notification) {
        textChanged()
        autosave?.cancel()
        autosave = Task { [weak self] in
            try? await Task.sleep(for: TabController.autosaveDelay)
            guard !Task.isCancelled else { return }
            self?.onSave?()
        }
    }

    func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        handle(selector, shift: NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false)
    }

    /// Split from the delegate call so a test can say whether Shift was down.
    func handle(_ selector: Selector, shift: Bool) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)) where shift:
            textView.insertNewlineIgnoringFieldEditor(nil)
        case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.cancelOperation(_:)):
            autosave?.cancel()
            onDone?()
        default:
            return false
        }
        return true
    }

    private func textChanged() {
        placeholder.isHidden = !textView.string.isEmpty
        let height = fittingHeight
        guard frame.height != height else { return }
        // Grows downward: the surface is flipped, so the top edge stays beside the element.
        Tokens.Motion.immediately { setFrameSize(NSSize(width: frame.width, height: height)) }
    }
}
