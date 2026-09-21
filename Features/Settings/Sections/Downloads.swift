//
//  Downloads.swift
//  Luna
//
//  docs/SETTINGS-SPEC.md §3.5.
//
//  Two of the four rows here are disabled with a reason, and the reason is
//  the same one: `DownloadManager` owns the destination decision and the item
//  list, and it is not this milestone's file to edit. What is wired is what
//  `Features/Downloads/DownloadItem.swift` can answer by itself — the folder
//  (`DownloadDestination.folder`) and auto-open (`DownloadItem.finish()`).
//  §30.4: a dimmed row that says why beats a switch that flips and does
//  nothing.
//
//  The folder is a pop-up, not an `NSPathControl`. The path control was one
//  native control doing the work of two, which is why it was chosen — but it
//  draws the folder's name hard against its leading edge and its chevron
//  against the trailing one, and it is as wide as the row lets it be. So the
//  word "Downloads" sat inches away from the control it belonged to, with the
//  row's own label on the far side of the gap. A pop-up puts the name and the
//  chevron together, and makes this row look like the two below it instead of
//  like a control borrowed from another window.
//

import AppKit

@MainActor
final class DownloadsSection: SettingsSection {

    static let id = "downloads"
    static let title = String(localized: "Downloads")
    static let symbolName = "arrow.down.circle"

    private let body = SettingsBody()
    private let folder = NSPopUpButton(frame: .zero, pullsDown: true)

    var view: NSView { body.view }
    var searchIndex: [String] { body.searchIndex }
    func filter(_ query: String) { body.filter(query) }

    init() {
        body.card(nil, [saveLocationRow(), askEachTimeRow(), autoOpenRow(), clearPolicyRow()])
    }

    // MARK: Where files go

    /// A pull-down: item 0 is the title, so the button reads as the folder in
    /// force and the menu offers the only thing there is to do about it.
    private func saveLocationRow() -> (view: NSView, terms: [String]) {
        folder.isBordered = false
        folder.font = Tokens.TypeScale.settingsRow
        folder.contentTintColor = Tokens.Text.secondary
        folder.target = self
        folder.action = #selector(folderMenuChose(_:))
        refreshFolder()

        let title = String(localized: "Save files to")
        let row = SettingsRow.accessory(title, subtitle: nil, accessory: folder)
        return (view: row, terms: [title, "folder", "location", "directory"])
    }

    /// The title carries the folder's own icon, at the row's text size — a
    /// download destination is a place on disk, and the icon is what says so in
    /// less room than the path would take.
    private func refreshFolder() {
        let url = DownloadDestination.folder
        folder.removeAllItems()
        folder.addItem(withTitle: url.lastPathComponent)
        let icon = NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false))
        icon.size = NSSize(width: Tokens.Metric.glyphSize, height: Tokens.Metric.glyphSize)
        folder.item(at: 0)?.image = icon
        folder.menu?.addItem(.separator())
        folder.addItem(withTitle: String(localized: "Other…"))
    }

    @objc private func folderMenuChose(_ sender: NSPopUpButton) {
        // Index 0 is the pull-down's own title and 1 is the separator; the only
        // item that does anything is the last one.
        guard sender.indexOfSelectedItem == sender.numberOfItems - 1 else { return }
        chooseFolder()
    }

    /// Luna is unsandboxed (D8), so there is no security-scoped bookmark to
    /// mint and nothing to resolve at launch — a path string is the whole of
    /// the persistence. What replaces the bookmark is the write test: TCC still
    /// applies to `~/Desktop` and `~/Documents`, and it is the one thing a
    /// permissions check can see and `isWritableFile(atPath:)` cannot.
    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = DownloadDestination.folder
        panel.prompt = String(localized: "Choose")
        guard panel.runModal() == .OK, let chosen = panel.url else { return }
        guard DownloadDestination.isWritable(chosen) else {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = String(localized: "Luna cannot save files to \u{201C}\(chosen.lastPathComponent)\u{201D}.")
            alert.informativeText = String(localized: """
            Writing a test file there failed. Either the folder is read-only, or macOS has \
            not granted Luna access to it. Pick a different folder, or grant access in \
            System Settings \u{203A} Privacy & Security \u{203A} Files and Folders.
            """)
            alert.runModal()
            // The setting is unchanged, so the control must go back to showing
            // the folder downloads will actually land in.
            refreshFolder()
            return
        }
        UserDefaults.standard.set(chosen.path(percentEncoded: false), forKey: DownloadDestination.directoryKey)
        refreshFolder()
    }

    // MARK: The three policy rows

    private func askEachTimeRow() -> (view: NSView, terms: [String]) {
        let title = String(localized: "Ask where to save each file")
        let row = SettingsRow.toggle(
            title,
            subtitle: nil,
            value: UserDefaults.standard.bool(forKey: "downloads.askEachTime"),
            isEnabled: false,
            disabledReason: String(localized: "DownloadManager picks the destination itself and does not read this yet."),
            onChange: { _ in }
        )
        return (view: row, terms: [title, "ask", "save panel"])
    }

    /// Default off, and that is the point of the row rather than an
    /// oversight: Safari ships this on, and it is the setting named most often
    /// in macOS malware write-ups. "Safe" is `DownloadRisk`'s definition — an
    /// executable, a disk image or an installer package never opens by itself,
    /// whatever this is set to.
    private func autoOpenRow() -> (view: NSView, terms: [String]) {
        let title = String(localized: "Open “safe” files after downloading")
        let subtitle = String(localized: "Never opens apps, disk images or installer packages")
        let row = SettingsRow.toggle(
            title,
            subtitle: subtitle,
            value: UserDefaults.standard.bool(forKey: DownloadDestination.autoOpenKey)
        ) { open in
            UserDefaults.standard.set(open, forKey: DownloadDestination.autoOpenKey)
        }
        return (view: row, terms: [title, subtitle, "open", "auto-open", "safe"])
    }

    /// Measured while building this: `DownloadManager.items` is in memory only
    /// — nothing writes it to disk and nothing reads it back — so the list is
    /// already, and always, cleared on quit. Two of the three options in §3.5's
    /// popup cannot be honoured, so the popup shows the truth and is dimmed.
    private func clearPolicyRow() -> (view: NSView, terms: [String]) {
        let title = String(localized: "Clear download list")
        let options = [
            String(localized: "Manually"), String(localized: "On quit"), String(localized: "After a day")
        ]
        let row = SettingsRow.popup(
            title,
            subtitle: nil,
            options: options,
            selected: 1,
            isEnabled: false,
            disabledReason: String(localized: "The download list is not saved between launches, so it always clears on quit."),
            onChange: { _ in }
        )
        return (view: row, terms: [title, "history", "clear list"])
    }
}
