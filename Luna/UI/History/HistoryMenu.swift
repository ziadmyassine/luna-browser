//
//  HistoryMenu.swift
//  Luna
//
//  §11.3's verbs on §6.4's rows: the right-click menu, and the two questions
//  it can ask before it acts — which span Clear History… clears, and whether
//  to forget a site, which signs the Space out of it.
//
//  The menu is built per right-click and closes over the pages themselves,
//  never a row index: the table recycles its rows (see `TabMenu`).
//

import AppKit
import BrowserKit

@MainActor
enum HistoryMenu {

    /// Every glyph the menu draws, named once so a test can check that each one
    /// resolves — a misspelt symbol draws nothing and fails nowhere.
    enum Glyph {
        static let delete = "trash"
        static let forget = "eraser"
        static let clear = "clock.badge.xmark"
        static let all = [delete, forget, clear]
    }

    /// - Parameter pages: what the row acts on — every marked page when the
    ///   row clicked is marked, otherwise that row alone.
    static func build(for pages: [HistoryEntry], controller: HistoryPanelController) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let delete = pages.count == 1 ? String(localized: "Delete") : String(localized: "Delete \(pages.count) Pages")
        menu.addItem(SidebarMenu.glyphItem(delete, symbol: Glyph.delete) { [weak controller] in
            controller?.delete(pages)
        })
        // Offered while the pages are all one site's, which a single row always is.
        let sites = Set(pages.map { PublicSuffix.siteKey(forHost: $0.host) })
        if sites.count == 1, let site = sites.first ?? nil {
            let forget = String(localized: "Forget This Site")
            menu.addItem(SidebarMenu.glyphItem(forget, symbol: Glyph.forget) { [weak controller] in
                controller?.forgetSite(site)
            })
        }
        menu.addItem(.separator())
        let clear = String(localized: "Clear History…")
        menu.addItem(SidebarMenu.glyphItem(clear, symbol: Glyph.clear) { [weak controller] in
            controller?.clearHistory()
        })
        return menu
    }

    // MARK: - The two questions

    /// Safari's question, and its four answers. The narrowest span is the one
    /// offered first: the dialog is one Return away from running.
    static func askClearRange(spaceName: String) -> HistoryClearRange? {
        let picker = NSPopUpButton(frame: .zero, pullsDown: false)
        for range in HistoryClearRange.allCases { picker.addItem(withTitle: range.title) }
        picker.selectItem(at: 0)
        let label = NSTextField(labelWithString: String(localized: "Clear"))
        let row = NSStackView(views: [label, picker])
        row.orientation = .horizontal
        row.spacing = Tokens.Metric.panelInset
        row.frame.size = row.fittingSize

        let alert = NSAlert()
        alert.messageText = String(localized: "Clear History")
        alert.informativeText = String(localized: """
        Removes the pages visited in “\(spaceName)” from its history. Other Spaces keep theirs, \
        and nothing is signed out.
        """)
        alert.accessoryView = row
        alert.addButton(withTitle: String(localized: "Clear History"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.buttons.last?.keyEquivalent = "\u{1b}"
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let choice = picker.indexOfSelectedItem
        return HistoryClearRange.allCases.indices.contains(choice) ? HistoryClearRange.allCases[choice] : nil
    }

    /// Asked because the answer signs the Space out of the site, which a
    /// history delete otherwise never does.
    static func confirmForget(site: String, spaceName: String) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Forget \(site)?")
        alert.informativeText = String(localized: """
        Removes every visit to \(site) from the history of “\(spaceName)”, and its cookies, \
        storage and caches there. You will be signed out of \(site) in this Space.
        """)
        alert.addButton(withTitle: String(localized: "Forget"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.buttons.last?.keyEquivalent = "\u{1b}"
        return alert.runModal() == .alertFirstButtonReturn
    }
}
