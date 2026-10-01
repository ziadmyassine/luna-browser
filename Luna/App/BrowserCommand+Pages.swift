//
//  BrowserCommand+Pages.swift
//  Luna
//
//  The table's entries for a page's paper and sound: §15.5's Print and
//  Download PDF, §18.4a's Mute All. Part of `BrowserCommand.all` like any
//  other; a file of their own only to keep the type's body under the
//  linter's length.
//

import AppKit

extension BrowserCommand {

    /// §15.5. Offered only while the tab shows a PDF from the web.
    static let downloadPDF = BrowserCommand(
        "downloadPDF", "Download PDF", #selector(AppDelegate.downloadPDF(_:)),
        symbol: "arrow.down.doc", keywords: ["save pdf", "pdf"]
    )
    /// Every Mac's ⌘P. A PDF in the viewer prints as its own pages.
    static let printPage = BrowserCommand(
        "printPage", "Print…", #selector(AppDelegate.printPage(_:)), [KeyBinding("p")], symbol: "printer"
    )

    static let muteAllTabs = BrowserCommand(
        "muteAllTabs", "Mute All Tabs", #selector(AppDelegate.muteAllTabs(_:)),
        symbol: "speaker.slash", keywords: ["silence", "sound", "audio", "quiet"]
    )
    static let unmuteAllTabs = BrowserCommand(
        "unmuteAllTabs", "Unmute All Tabs", #selector(AppDelegate.unmuteAllTabs(_:)),
        symbol: "speaker.wave.2", keywords: ["sound", "audio"]
    )
}
