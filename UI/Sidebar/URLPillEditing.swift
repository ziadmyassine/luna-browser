//
//  URLPillEditing.swift
//  Luna
//
//  §3.2's pill, open: what `⌘L` and a click put in the field, what the arrow
//  keys and Return do while it is open, and what it goes back to afterwards.
//
//  Split out of `URLPillView.swift` for the reason `URLPillLayout.swift` was:
//  that file crosses SwiftLint's 400-line limit otherwise. Nothing changed on
//  the way across — `isEditing` stays a stored property of the view, because an
//  extension cannot hold one.
//

import AppKit

extension URLPillView {

    // MARK: - Editing (§3.2, ⌘L)

    /// Expands to the full URL, selected. Idempotent, so ⌘L on an already-open
    /// pill just re-selects.
    ///
    /// **Unless the pill hands off.** A pill with an `onHandOff` never opens:
    /// the click and the `⌘L` both go to §9.1, which is where the field, the
    /// history and the list already live. See `URLPillView.onHandOff`.
    func beginEditing() {
        guard onHandOff == nil else { return onHandOff?() ?? () }
        let wasEditing = isEditing
        isEditing = true
        updateGlass()
        // A new tab opens empty, not with `luna://newtab` selected in it: the
        // address of a blank page is not something anyone means to edit, and
        // selecting it only means the first keystroke has to clear it.
        let blank = Self.label(of: displayedURL).isEmpty
        field.stringValue = blank ? "" : (displayedURL?.absoluteString ?? "")
        field.isEditable = true
        field.isSelectable = true
        needsLayout = true
        window?.makeFirstResponder(field)
        field.currentEditor()?.selectAll(nil)
        needsDisplay = true
        // Only on the way in. This is idempotent — ⌘L on an open pill just
        // re-selects — and a bar that re-opened on every ⌘L would fight the
        // scroll rule for a state it is already in.
        if !wasEditing { onBeginEditing?() }
    }

    private func endEditing(commit: Bool) {
        // Asked before the field is torn down: the list is dismissed on the way
        // out, and a phrase read after that is a phrase read from nothing.
        let chosen = commit ? chosenCompletion?() : nil
        let typed = chosen ?? field.stringValue
        isEditing = false
        updateGlass()
        field.isEditable = false
        field.isSelectable = false
        field.stringValue = Self.label(of: displayedURL)
        needsLayout = true
        if window?.firstResponder !== self { window?.makeFirstResponder(self) }
        needsDisplay = true
        onEndEditing?(commit)
        if commit, !typed.isEmpty { onSubmit?(typed) }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.cancelOperation(_:)):
            endEditing(commit: false) // §3.2: Esc reverts.
        case #selector(NSResponder.insertNewline(_:)):
            endEditing(commit: true)
        case #selector(NSResponder.moveDown(_:)):
            return onMoveSelection?(1) ?? false
        case #selector(NSResponder.moveUp(_:)):
            return onMoveSelection?(-1) ?? false
        default:
            return false
        }
        return true
    }

    func controlTextDidChange(_ obj: Notification) {
        guard isEditing else { return }
        // §3.2b centres the text in the capsule, so it has to be re-placed on
        // every keystroke rather than only when the address changes.
        needsLayout = true
        onTyping?(field.stringValue)
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard isEditing else { return }
        endEditing(commit: false)
    }

    /// §30.1: the sidebar's plane moves the window; a control on it does not.
    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) {
        beginEditing()
    }
}
