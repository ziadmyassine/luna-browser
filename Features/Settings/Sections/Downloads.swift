//
//  Downloads.swift
//  Luna
//
//  docs/SETTINGS-SPEC.md §3.5.
//
//  Two of the four rows here are **disabled with a reason**, and the reason is
//  the same one: `DownloadManager` owns the destination decision and the item
//  list, and it is not this milestone's file to edit. What *is* wired is what
//  `Features/Downloads/DownloadItem.swift` can answer by itself — the folder
//  (`DownloadDestination.folder`) and auto-open (`DownloadItem.finish()`).
//  §30.4: a dimmed row that says why beats a switch that flips and does
//  nothing.
//

import AppKit

@MainActor
final class DownloadsSection: SettingsSection {

    static let id = "downloads"
    static let title = String(localized: "Downloads")
    static let symbolName = "arrow.down.circle"

    private let body = SettingsBody()
    private let path = NSPathControl()

    var view: NSView { body.view }
    var searchIndex: [String] { body.searchIndex }
    func filter(_ query: String) { body.filter(query) }

    init() {
        body.card(nil, [saveLocationRow(), askEachTimeRow(), autoOpenRow(), clearPolicyRow()])
    }

    // MARK: Where files go

    /// §3.5's "path popup + Choose…" is one native control, not two.
    ///
    /// Measured in `NSPathControl.h`: "If the control isEditable and has the
    /// pathStyle set to NSPathStylePopUp, an additional choice in the pop up
    /// menu will allow selecting another location. By default, an NSOpenPanel
    /// will be configured based on the allowedTypes." So `public.folder` plus
    /// editable *is* the Choose… item, with the system's own panel.
    private func saveLocationRow() -> (view: NSView, terms: [String]) {
        path.pathStyle = .popUp
        path.isEditable = true
        path.allowedTypes = ["public.folder"]
        path.url = DownloadDestination.folder
        path.target = self
        path.action = #selector(chooseFolder(_:))

        let title = String(localized: "Save files to")
        let row = SettingsRow.accessory(title, subtitle: nil, accessory: path)
        return (view: row, terms: [title, "folder", "location", "directory"])
    }

    /// Luna is unsandboxed (D8), so there is no security-scoped bookmark to
    /// mint and nothing to resolve at launch — a path string is the whole of
    /// the persistence. What replaces the bookmark is the write test: TCC still
    /// applies to `~/Desktop` and `~/Documents`, and it is the one thing a
    /// permissions check can see and `isWritableFile(atPath:)` cannot.
    @objc private func chooseFolder(_ sender: NSPathControl) {
        guard let chosen = sender.clickedPathItem?.url ?? sender.url else { return }
        guard DownloadDestination.isWritable(chosen) else {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = String(localized: "Luna cannot save files to “\(chosen.lastPathComponent)”.")
            alert.informativeText = String(localized: """
            Writing a test file there failed. Either the folder is read-only, or macOS has \
            not granted Luna access to it. Pick a different folder, or grant access in \
            System Settings › Privacy & Security › Files and Folders.
            """)
            alert.runModal()
            // The setting is unchanged, so the control must go back to showing
            // the folder downloads will actually land in.
            sender.url = DownloadDestination.folder
            return
        }
        UserDefaults.standard.set(chosen.path(percentEncoded: false), forKey: DownloadDestination.directoryKey)
        sender.url = DownloadDestination.folder
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

    /// Default **off**, and that is the point of the row rather than an
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
