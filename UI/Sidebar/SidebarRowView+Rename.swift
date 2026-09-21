//
//  SidebarRowView+Rename.swift
//  Luna
//
//  §3.4a and §3.4b's rename, typed on the row itself rather than asked for in a
//  sheet. One field for both nouns: a folder's name and a tab's are the same
//  line of text in the same place, and the row is what knows which it is.
//
//  A folder arrives with no name worth keeping — it is made by a right-click
//  and it has to be called something — so the first thing every new one needs
//  is a name. A dialog for that puts a window in front of the list the folder
//  has just appeared in, and the answer goes to a row the user can no longer
//  see. Typing on the row is the same act with nothing in front of it, and it
//  is what renaming a folder looks like everywhere else on the system.
//
//  §3.3's tiles and §4's strip keep the dialog, because neither draws the tab's
//  name as a line of text there is room to type on.
//
//  The field is hidden except while it is being typed into. It is not a second
//  title: the row draws its name the way every other row draws one, and this
//  comes out on top for the length of the edit.
//

import AppKit

extension SidebarRowView: NSTextFieldDelegate {

    /// Set up once, in the initialiser. Borderless and unpainted, because the
    /// row is already wearing §3.4's selected pill and a bezel inside it would
    /// be a box inside a box.
    func prepareEditor() {
        editor.isHidden = true
        editor.isBezeled = false
        editor.isBordered = false
        editor.drawsBackground = false
        // `drawsBackground` answers for the cell; the colour answers for
        // everything that reads the cell without asking it, and the field
        // editor is one of those. Left at `textBackgroundColor` it paints the
        // near-black plate that made the row look like a text box cut into it.
        editor.backgroundColor = .clear
        editor.focusRingType = .none
        editor.font = Tokens.TypeScale.sidebarRow
        editor.textColor = Tokens.Text.primary
        editor.lineBreakMode = .byClipping
        editor.cell?.usesSingleLineMode = true
        editor.delegate = self
        editor.target = self
        editor.action = #selector(editorCommitted)
    }

    /// The field's box: one line tall, from the title's own left edge out to the
    /// pill's inner one.
    ///
    /// Not the title's box, which is what it draws over. A title is laid out at
    /// the width it needs and faded where it runs out; a name being typed is
    /// longer than the name that fitted, and a field cut to the old one would
    /// scroll its own text under the caret for no reason.
    /// - Parameter icon: the row's icon slot, which is where the field stands
    ///   while it is asking for an emoji. What is being replaced then is the
    ///   picture, and a field over the name would read as a rename.
    /// - Parameter reserve: what the trailing end of the row is already using —
    ///   §3.4b's chevron on a folder's header, nothing on a tab.
    func placeEditor(title box: NSRect, icon: NSRect, reserving reserve: CGFloat) {
        let height = editor.intrinsicContentSize.height
        let x = isPickingEmoji ? icon.minX : box.minX
        let right = isPickingEmoji ? icon.maxX : bounds.width - 2 * Tokens.Metric.rowInset - reserve
        editor.frame = NSRect(
            x: x,
            y: (bounds.height - height) / 2,
            width: max(right - x, 0),
            height: height
        ).integral
    }

    /// Opens the field on this row's own name, with the whole of it selected so
    /// the first keystroke replaces it.
    func beginEditing(_ name: String) {
        guard let window else { return }
        editor.stringValue = name
        editor.isHidden = false
        setTitleHidden(true)
        needsLayout = true
        // Laid out before the field takes focus: the field editor copies the
        // frame it finds, so a field still at its old size shows the caret in
        // the wrong place for the length of the edit.
        layoutSubtreeIfNeeded()
        window.makeFirstResponder(editor)
        styleFieldEditor()
        editor.currentEditor()?.selectAll(nil)
    }

    /// §3.4b's *Emoji…*: the icon slot becomes a one-character field and macOS's
    /// own palette opens over it.
    ///
    /// The palette rather than a grid of Luna's own, because there are three
    /// thousand emoji and the user already knows where theirs are — it has a
    /// search field, a frequently-used row and their own skin tones, and none
    /// of that is worth rebuilding badly. It inserts into whatever field has
    /// focus, which is the whole reason there is a field here at all: the row
    /// does not want the text, it wants the one character the palette sends.
    ///
    /// The name stays visible. It is the picture being changed, and a row that
    /// blanked its title to ask about its icon would be asking the wrong
    /// question.
    func beginPickingEmoji() {
        guard let window else { return }
        isPickingEmoji = true
        editor.stringValue = ""
        editor.isHidden = false
        needsLayout = true
        layoutSubtreeIfNeeded()
        window.makeFirstResponder(editor)
        styleFieldEditor()
        NSApp.orderFrontCharacterPalette(nil)
    }

    /// The field editor is one shared `NSTextView` the window lends out, and it
    /// arrives wearing whatever the last field left on it. Set every time
    /// rather than once: the row does not own it and cannot keep it.
    private func styleFieldEditor() {
        guard let live = editor.currentEditor() as? NSTextView else { return }
        live.drawsBackground = false
        live.backgroundColor = .clear
        live.insertionPointColor = Tokens.Text.primary
        live.selectedTextAttributes = [
            .backgroundColor: Tokens.Surface.selected,
            .foregroundColor: Tokens.Text.primary
        ]
    }

    /// Takes the field away. `commit` false is Escape and every path that is not
    /// the user saying yes — the row keeps the name it already had.
    func endEditing(commit: Bool) {
        guard !editor.isHidden else { return }
        let typed = editor.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let wasPickingEmoji = isPickingEmoji
        isPickingEmoji = false
        editor.isHidden = true
        setTitleHidden(false)
        // The list gets the focus back, or the whole window has none: the field
        // is about to stop existing as far as the responder chain is concerned,
        // and a window with no first responder swallows the next arrow key.
        if editor.currentEditor() != nil { window?.makeFirstResponder(superview) }
        // Blank goes through rather than being dropped here. A folder refuses
        // it and a tab reads it as "give the name back to the page", and only
        // the row knows which of the two it is.
        guard commit, !wasPickingEmoji else { return }
        onRename?(typed)
    }

    @objc
    private func editorCommitted() {
        endEditing(commit: true)
    }

    /// Escape abandons the edit. Return is `action`'s, and Tab is left to
    /// AppKit — a row is not a form, so there is nothing to move on to.
    public func control(
        _ control: NSControl,
        textView: NSTextView,
        doCommandBy selector: Selector
    ) -> Bool {
        guard selector == #selector(NSResponder.cancelOperation(_:)) else { return false }
        endEditing(commit: false)
        return true
    }

    /// Clicking away commits, which is what a name typed and then left alone
    /// means. Guarded on the field still being up: `endEditing` resigns first
    /// responder itself, and that comes back through here.
    public func controlTextDidEndEditing(_ notification: Notification) {
        endEditing(commit: true)
    }

    /// The emoji arrives as a change rather than as a return: the palette
    /// inserts a character and then sits there, so waiting for the user to
    /// confirm would be waiting for a keystroke they have no reason to make.
    /// The first character closes the field.
    ///
    /// Anything that is not an emoji is discarded rather than stored — the
    /// field is open to the keyboard as well as the palette, and a folder
    /// wearing the letter `k` is not an icon.
    public func controlTextDidChange(_ notification: Notification) {
        guard isPickingEmoji, let first = editor.stringValue.first else { return }
        let chosen = String(first)
        endEditing(commit: false)
        guard RowEmoji.isEmoji(chosen) else { return }
        onPickEmoji?(chosen)
    }
}
