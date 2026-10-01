//
//  BrowserCommands+Find.swift
//  Luna
//
//  §18.1's four Edit ▸ Find commands, for the window in front
//  (`FindController`). Same rules as `BrowserCommands.swift`: a first-responder
//  action per command, nothing that is not also a menu item.
//
//  ⌘F is the Settings window's search as well. AppKit stops at the first menu
//  item carrying a key equivalent, enabled or not, and Edit comes before
//  Window ▸ Settings, so Find… owns the key; the Settings window answers
//  `findInPage(_:)` itself while it is key, ahead of this delegate in the
//  responder chain, the way it answers `closeTab(_:)` for ⌘W.
//

import AppKit
import BrowserKit

extension AppDelegate {

    /// The window's find, unless the key window is one find does not belong
    /// to — Settings, which handles ⌘F itself and has no page for ⌘G.
    private var find: FindController? {
        if NSApp.keyWindow?.windowController is SettingsWindowController { return nil }
        return front?.find
    }

    @objc func findInPage(_ sender: Any?) {
        find?.open()
    }

    @objc func findNextInPage(_ sender: Any?) {
        find?.findNext()
    }

    @objc func findPreviousInPage(_ sender: Any?) {
        find?.findPrevious()
    }

    /// ⌘E. Text selected in a field — the address bar, a form on the page has
    /// its own — is what the user is pointing at; otherwise the page's.
    @objc func useSelectionForFind(_ sender: Any?) {
        guard let find else { return }
        if let editor = NSApp.keyWindow?.firstResponder as? NSTextView, editor !== find.bar?.field.currentEditor() {
            let range = editor.selectedRange()
            if range.length > 0 {
                return find.useSelection((editor.string as NSString).substring(with: range))
            }
        }
        find.useSelectionFromPage()
    }

    /// Returns nil for anything it does not own, so `validateMenuItem`'s chain
    /// carries on past it.
    func validateFindCommand(_ item: NSMenuItem) -> Bool? {
        switch item.action {
        case #selector(findInPage(_:)), #selector(useSelectionForFind(_:)):
            return find?.canFind ?? false
        case #selector(findNextInPage(_:)), #selector(findPreviousInPage(_:)):
            guard let find else { return false }
            return find.canFind && find.hasQuery
        default:
            return nil
        }
    }
}
