//
//  CommandBarInputField.swift
//  Luna
//
//  §9.1's single input and §9.4's inline autofill.
//
//  §9.4 asks for selected-suffix behaviour rather than ghost text: the
//  completion is really in the field and the part the user did not type is
//  really selected, so `→` accepts it, a keystroke replaces it and `⌫` removes
//  it — all of which AppKit already does for a selection. The cost is
//  re-entrancy (setting `stringValue` fires `controlTextDidChange` again) and
//  the backspace trap (completing again on the deletion that just rejected the
//  completion). Both are handled by the two flags below.
//

import AppKit

@MainActor
protocol CommandBarInputDelegate: AnyObject {
    /// The user changed what they typed. Runs on the keystroke, synchronously.
    func inputDidChange(_ typed: String)
    /// `↓` / `↑` / `⇥` / `⇧⇥`.
    func inputDidMoveSelection(by offset: Int)
    /// `↩`.
    func inputDidCommit()
    /// `esc`, with no completion left to cancel first.
    func inputDidCancel()
}

@MainActor
final class CommandBarInputField: NSTextField, NSTextFieldDelegate {

    weak var inputDelegate: (any CommandBarInputDelegate)?

    /// What the user actually typed, never the autofilled tail. Every query, and
    /// every §9.3 adaptive lesson, is keyed on this — teaching the ranker the
    /// string it completed for you would make it agree with itself forever.
    private(set) var typedText = ""

    /// True while this class is assigning `stringValue`. `controlTextDidChange`
    /// fires for programmatic changes exactly as it does for typed ones, and
    /// without this the autofill would re-enter itself on every completion.
    private var isProgrammaticUpdate = false

    /// Set by `⌫`/`⌦` and consumed by the next change. Deleting the completion is
    /// how the user says no; completing again on that keystroke makes the field
    /// impossible to clear.
    private var isDeleting = false

    init() {
        super.init(frame: .zero)
        isBordered = false
        isBezeled = false
        drawsBackground = false
        focusRingType = .none
        usesSingleLineMode = true
        cell?.wraps = false
        cell?.isScrollable = true
        delegate = self
        applyTokens()

        // §21.2 / contract rule 4: Increase Contrast is not an `NSAppearance` on
        // macOS 26.5, so the token colours resolved at assignment are the ones we
        // keep. Re-assign them when the setting flips or the field ignores it.
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(accessibilityDisplayOptionsChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    @objc private func accessibilityDisplayOptionsChanged() {
        applyTokens()
        needsDisplay = true
    }

    private func applyTokens() {
        font = Tokens.TypeScale.commandBarQuery
        textColor = Tokens.Text.primary
        placeholderAttributedString = NSAttributedString(
            string: placeholderText,
            attributes: [.font: Tokens.TypeScale.commandBarQuery, .foregroundColor: Tokens.Text.tertiary]
        )
    }

    private var placeholderText = "" {
        didSet { applyTokens() }
    }

    // MARK: - Opening (§9.1)

    /// `⌘T`: empty, new-tab mode. `⌘L`: prefilled with the current URL, selected.
    func begin(with text: String, placeholder: String, selectAll: Bool) {
        placeholderText = placeholder
        isDeleting = false
        setText(text)
        typedText = text
        guard let editor = currentEditor() else { return }
        editor.selectedRange = selectAll
            ? NSRange(location: 0, length: (text as NSString).length)
            : NSRange(location: (text as NSString).length, length: 0)
    }

    // MARK: - §9.4 inline autofill

    /// Puts `completion` in the field with everything past `typedText` selected.
    /// `nil` leaves the field exactly as the user typed it.
    func applyAutofill(_ completion: String?) {
        guard !isDeleting, let completion, completion != stringValue else { return }
        let typed = typedText as NSString
        guard (completion as NSString).length > typed.length else { return }
        setText(completion)
        currentEditor()?.selectedRange = NSRange(
            location: typed.length,
            length: (completion as NSString).length - typed.length
        )
    }

    /// Whether there is a completion to cancel — the first thing `esc` does (§9.4).
    var hasAutofill: Bool {
        stringValue != typedText
    }

    /// `esc` with a completion showing: drop back to what the user typed.
    func cancelAutofill() {
        setText(typedText)
        currentEditor()?.selectedRange = NSRange(location: (typedText as NSString).length, length: 0)
    }

    /// `→` with a completion showing: keep it and put the caret at the end.
    private func acceptAutofill() {
        typedText = stringValue
        currentEditor()?.selectedRange = NSRange(location: (stringValue as NSString).length, length: 0)
    }

    private func setText(_ text: String) {
        isProgrammaticUpdate = true
        stringValue = text
        isProgrammaticUpdate = false
    }

    // MARK: - NSTextFieldDelegate

    func controlTextDidChange(_ notification: Notification) {
        guard !isProgrammaticUpdate else { return }
        typedText = stringValue
        // The delegate re-ranks and calls straight back into `applyAutofill`, so
        // `isDeleting` has to still be set while it runs — that suppression for
        // one keystroke is the whole reason ⌫ can clear a completion.
        inputDelegate?.inputDidChange(typedText)
        isDeleting = false
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.moveDown(_:)), #selector(NSResponder.insertTab(_:)):
            inputDelegate?.inputDidMoveSelection(by: 1)
        case #selector(NSResponder.moveUp(_:)), #selector(NSResponder.insertBacktab(_:)):
            inputDelegate?.inputDidMoveSelection(by: -1)
        case #selector(NSResponder.insertNewline(_:)):
            inputDelegate?.inputDidCommit()
        case #selector(NSResponder.cancelOperation(_:)):
            // §9.4: `Esc` cancels the completion. Only once there is none left does
            // it mean §9.1's "dismiss".
            if hasAutofill { cancelAutofill() } else { inputDelegate?.inputDidCancel() }
        case #selector(NSResponder.moveRight(_:)):
            // Only when a completion is showing; otherwise `→` is an ordinary
            // caret move and belongs to the field.
            guard hasAutofill, textView.selectedRange.length > 0 else { return false }
            acceptAutofill()
        case #selector(NSResponder.deleteBackward(_:)), #selector(NSResponder.deleteForward(_:)):
            isDeleting = true
            return false
        default:
            return false
        }
        return true
    }

    // MARK: - Accessibility (§21.1)

    /// The editable half of the panel's combo box. The results list is its sibling;
    /// `CommandBarPanelView` owns the `comboBox` role that groups the two.
    override func accessibilityRole() -> NSAccessibility.Role? { .textField }
}
