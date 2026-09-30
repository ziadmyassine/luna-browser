//
//  SafariSyncNudge.swift
//  Luna
//
//  Makes Safari's sync agent upload what Luna wrote, without showing Safari
//  (docs/SAFARI-FAVORITES.md).
//
//  The agent uploads only when Safari itself edits its bookmarks, when iCloud
//  pushes a change from another device, or on a daily timer. Measured: it
//  ignores every notification Luna can post, and its XPC service refuses any
//  process without a private Safari entitlement. So Luna has Safari make one
//  edit — a Reading List item — with Safari started hidden if it is not open
//  already. The agent then uploads everything waiting, Luna's entries with it.
//  Afterwards Safari is quit again if Luna started it, and the item is taken
//  out of the file; that removal goes up with the next upload.
//

import AppKit

@MainActor
enum SafariSyncNudge {

    nonisolated static let safari = "com.apple.Safari"
    /// The Reading List item Safari is asked to add. `.invalid` never
    /// resolves, so Safari's preview fetch ends at once.
    nonisolated static let marker = "https://luna.invalid/safari-sync"
    nonisolated static let markerTitle = "Luna"

    /// Measured: the upload finished about two seconds after Safari's edit.
    nonisolated static let uploadTimeout: Duration = .seconds(20)
    /// Long enough for the one-time "Luna wants to control Safari" prompt.
    nonisolated static let promptTimeout: TimeInterval = 60

    /// - Returns: whether the upload was seen to happen.
    @discardableResult
    static func run() async -> Bool {
        var launched: NSRunningApplication?
        if NSRunningApplication.runningApplications(withBundleIdentifier: safari).isEmpty {
            launched = await launchHidden()
            guard launched != nil else { return false }
        }
        let uploaded = await addMarker() ? await waitForUpload() : false
        if let launched { await quit(launched) }
        await removeMarker()
        return uploaded
    }

    private static func launchHidden() async -> NSRunningApplication? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: safari) else { return nil }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.hides = true
        configuration.addsToRecentItems = false
        guard let app = try? await NSWorkspace.shared.openApplication(at: url, configuration: configuration) else { return nil }
        for _ in 0..<100 where !app.isFinishedLaunching {
            try? await Task.sleep(for: .milliseconds(100))
        }
        return app.isFinishedLaunching ? app : nil
    }

    /// Through `osascript` rather than `NSAppleScript`, which runs on the main
    /// thread and would hold Luna there while the permission prompt is up.
    private nonisolated static func addMarker() async -> Bool {
        await Task.detached {
            let script = "tell application id \"\(safari)\" to add reading list item \"\(marker)\" with title \"\(markerTitle)\""
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return false }
            let deadline = Date().addingTimeInterval(promptTimeout)
            while process.isRunning, Date() < deadline { usleep(100_000) }
            if process.isRunning { process.terminate() }
            return process.terminationReason == .exit && process.terminationStatus == 0
        }.value
    }

    /// Until the item Safari added has its CloudKit system fields: the agent
    /// uploads the whole list at once, so Luna's entries went up with it.
    private nonisolated static func waitForUpload() async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + uploadTimeout
        while clock.now < deadline {
            try? await Task.sleep(for: .seconds(1))
            if let data = try? SafariBookmarksFile.read(),
               let document = try? SafariBookmarksDocument(data: data),
               document.hasUploadedReadingListItem(at: marker) {
                return true
            }
        }
        return false
    }

    private static func quit(_ app: NSRunningApplication) async {
        app.terminate()
        for _ in 0..<50 where !app.isTerminated {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    /// Only with Safari closed: a running Safari holds its own copy and may
    /// write the item back. Left in, the next write takes it out
    /// (`SafariFavorites.write`).
    private static func removeMarker() async {
        guard NSRunningApplication.runningApplications(withBundleIdentifier: safari).isEmpty else { return }
        await Task.detached {
            for _ in 0..<5 {
                guard let data = try? SafariBookmarksFile.read(),
                      var document = try? SafariBookmarksDocument(data: data),
                      document.removeReadingListItems(at: marker),
                      let edited = try? document.data()
                else { return }
                do {
                    try SafariBookmarksFile.replace(data, with: edited)
                    return
                } catch {
                    try? await Task.sleep(for: .seconds(2))
                }
            }
        }.value
    }
}
