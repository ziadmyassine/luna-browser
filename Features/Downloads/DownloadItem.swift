//
//  DownloadItem.swift
//  Luna
//
//  One download, plus the three decisions that are pure functions and therefore
//  testable without a network, a web view or a disk (TODO.md §15.1a, §15.4):
//  what the file is called, where it goes when that name is taken, and whether
//  it is the kind of file we stop and ask about.
//
//  A reference type on purpose: `DownloadManager` hands the same object to
//  every surface showing it, and each re-reads it as the download progresses.
//  `WKDownload` is `@MainActor` in the macOS 26.5 SDK (`WK_SWIFT_UI_ACTOR` on
//  the class), so everything here is too.
//

import AppKit
import Foundation
import UniformTypeIdentifiers
import WebKit

/// A download the user can see: live, finished, failed or cancelled.
@MainActor
final class DownloadItem {

    enum State: Equatable {
        case inProgress
        case finished
        /// `localizedDescription` of the underlying error. Resumable when
        /// `resumeData` is non-nil.
        case failed(String)
        case cancelled
    }

    let id = UUID()
    /// The request that started it — what a retry re-issues when there is no
    /// resume data.
    let request: URLRequest?
    /// The page the download came from. Goes into the quarantine record so the
    /// Gatekeeper dialog can say where the file is from (§15.3).
    let pageURL: URL?

    private(set) var filename: String
    private(set) var destination: URL?
    private(set) var state: State = .inProgress
    /// `WKDownload` conforms to `NSProgressReporting`; this is its `progress`.
    /// The modern `WKDownloadDelegate` has no byte-count callback at all, so
    /// this object is the only source of progress (§15.1a).
    private(set) var progress: Progress?
    private(set) var resumeData: Data?

    init(request: URLRequest?, pageURL: URL?, filename: String) {
        self.request = request
        self.pageURL = pageURL
        self.filename = filename
    }

    // MARK: Transitions — only `DownloadManager` drives these.

    func willWrite(to url: URL, progress: Progress?) {
        destination = url
        filename = url.lastPathComponent
        self.progress = progress
        state = .inProgress
        resumeData = nil
    }

    func finish() {
        state = .finished
        progress = nil
        openIfSafeAndAsked()
    }

    /// §3.5's "Open safe files after downloading", and the reason it is a
    /// setting rather than a policy: it defaults off, which is the opposite
    /// of what Safari ships, because it is the single behaviour named most
    /// often in macOS malware write-ups.
    ///
    /// "Safe" is `DownloadRisk`'s definition, not a second one: anything that
    /// would have stopped and asked on the way in never opens by itself on the
    /// way out. The open goes through `NSWorkspace`, so the quarantine flag
    /// `DownloadManager` wrote is still what Gatekeeper reads.
    private func openIfSafeAndAsked() {
        guard UserDefaults.standard.bool(forKey: DownloadDestination.autoOpenKey),
              !DownloadRisk.isRisky(filename: filename),
              let destination, isOnDisk
        else { return }
        NSWorkspace.shared.open(destination)
    }

    func fail(_ error: any Error, resumeData: Data?) {
        // A user-cancelled download is not a failure to show in red.
        let cancelled = (error as NSError).code == NSUserCancelledError
        state = cancelled ? .cancelled : .failed(error.localizedDescription)
        self.resumeData = resumeData
        progress = nil
    }

    /// Back to `.inProgress` for a retry. `resumeData` is kept: the retry is
    /// what consumes it, and it must survive until then.
    func restart() {
        state = .inProgress
    }

    /// True when the file is on disk and can be opened or revealed.
    var isOnDisk: Bool {
        guard state == .finished, let destination else { return false }
        return FileManager.default.fileExists(atPath: destination.path)
    }

    /// Retry is offered for anything that did not finish — resume data makes it
    /// cheap, `request` makes it possible at all.
    var canRetry: Bool {
        switch state {
        case .failed, .cancelled: resumeData != nil || request != nil
        case .inProgress, .finished: false
        }
    }

    /// The VoiceOver sentence for this row. A download that exists only as an
    /// animation is invisible to a screen reader (§21.1), so state is spelled
    /// out in words rather than implied by a glyph or a colour.
    var accessibilityLabel: String {
        switch state {
        case .finished: return String(localized: "\(filename), download complete")
        case .inProgress:
            let percent = progress.map { Int($0.fractionCompleted * 100) }
            return percent.map { String(localized: "\(filename), downloading, \($0) percent") }
                ?? String(localized: "\(filename), downloading")
        case let .failed(reason): return String(localized: "\(filename), download failed: \(reason)")
        case .cancelled: return String(localized: "\(filename), download cancelled")
        }
    }

    /// The file-type icon for §5's 34 pt slot. Uses the real file once it
    /// exists so a PDF looks like that PDF, and falls back to the type.
    var icon: NSImage {
        if let destination, isOnDisk {
            return NSWorkspace.shared.icon(forFile: destination.path)
        }
        let type = UTType(filenameExtension: (filename as NSString).pathExtension)
        return NSWorkspace.shared.icon(for: type ?? .data)
    }
}

// MARK: - Where the bytes land

/// The destination decision, as pure functions (§15.1a). `exists` is injected
/// so the uniquifier can be tested without writing to `~/Downloads`.
enum DownloadDestination {

    /// §3.5's "Save files to". Settings writes a path here; nothing else does.
    static let directoryKey = "downloads.directory"
    /// §3.5's "Open safe files after downloading". Read by `DownloadItem.finish()`.
    static let autoOpenKey = "downloads.autoOpen"

    /// Where the bytes land: the user's folder if they picked one and it is
    /// still writable, otherwise `~/Downloads`.
    ///
    /// The writability check is not belt-and-braces. The folder is chosen once
    /// and used for months; by the time it is an ejected volume or a deleted
    /// directory, WebKit's only answer is a download that fails with an error
    /// nobody connects to a setting. Falling back is the safe half — Settings
    /// owns the visible half, and refuses to store a folder that fails this.
    static var folder: URL {
        if let path = UserDefaults.standard.string(forKey: directoryKey), !path.isEmpty {
            let chosen = URL(filePath: path, directoryHint: .isDirectory)
            if isWritable(chosen) { return chosen }
        }
        return systemDownloads
    }

    /// `~/Downloads`, created if the user deleted it.
    static var systemDownloads: URL {
        let manager = FileManager.default
        if let url = try? manager.url(
            for: .downloadsDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) {
            return url
        }
        return manager.homeDirectoryForCurrentUser.appending(path: "Downloads", directoryHint: .isDirectory)
    }

    /// Whether Luna can actually write into `url` — tested by writing, not by
    /// asking.
    ///
    /// `FileManager.isWritableFile(atPath:)` reads the POSIX mode bits and
    /// nothing else, so it answers true for `~/Desktop` and `~/Documents`
    /// while TCC is still refusing the write. Luna is unsandboxed (D8), so
    /// there is no security-scoped bookmark to restore and no entitlement to
    /// check — creating and deleting a dot-file is the only check that agrees
    /// with what the download will do.
    static func isWritable(_ url: URL) -> Bool {
        let manager = FileManager.default
        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDirectory),
              isDirectory.boolValue
        else { return false }
        let probe = url.appending(path: ".luna-write-test-\(UUID().uuidString)", directoryHint: .notDirectory)
        guard manager.createFile(atPath: probe.path(percentEncoded: false), contents: nil) else { return false }
        try? manager.removeItem(at: probe)
        return true
    }

    /// Makes a server-supplied filename safe to write.
    ///
    /// Every clause here is an attack, not a tidy-up: a `/` escapes the
    /// downloads folder, a NUL truncates the path C-side, a leading `.` hides
    /// the file from the user who just downloaded it, and a name over the
    /// 255-byte limit fails the write outright.
    static func sanitize(_ suggested: String) -> String {
        var name = suggested
            .replacingOccurrences(of: "\0", with: "")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        name = (name as NSString).lastPathComponent
        while name.hasPrefix(".") { name.removeFirst() }
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { name = fallbackName }

        // 255 bytes, not characters: the limit is the filesystem's.
        let maxBytes = 255
        if name.utf8.count > maxBytes {
            let ext = (name as NSString).pathExtension
            let suffix = ext.isEmpty ? "" : "." + ext
            var base = (name as NSString).deletingPathExtension
            while base.utf8.count + suffix.utf8.count > maxBytes { base.removeLast() }
            name = base + suffix
        }
        return name
    }

    /// Finder's convention: `report.pdf`, `report 2.pdf`, `report 3.pdf`.
    /// Never overwrites — WebKit requires a destination that does not exist.
    static func unique(_ url: URL, exists: (URL) -> Bool) -> URL {
        guard exists(url) else { return url }
        let folder = url.deletingLastPathComponent()
        let ext = url.pathExtension
        let base = url.deletingPathExtension().lastPathComponent
        // Two is where Finder starts; the cap is a stop, not a policy — a
        // thousand collisions on one name means something else is wrong.
        for index in 2...1000 {
            let suffix = ext.isEmpty ? "" : "." + ext
            let candidate = folder.appending(path: "\(base) \(index)\(suffix)", directoryHint: .notDirectory)
            if !exists(candidate) { return candidate }
        }
        return folder.appending(path: "\(base)-\(UUID().uuidString)", directoryHint: .notDirectory)
    }

    static let fallbackName = "download"
}

// MARK: - §15.4 — the files worth stopping for

/// Whether a file should be confirmed before it is written.
///
/// Deliberately narrow. Warning about every `.zip` trains the user to click
/// through, which is worse than not warning at all — so this is the set macOS
/// itself treats as launchable code.
enum DownloadRisk {

    /// Types that run when you double-click them.
    private static var executableTypes: [UTType] {
        [.executable, .unixExecutable, .applicationBundle, .application, .shellScript, .diskImage]
    }

    /// Installer packages have no `UTType` constant on macOS, and both `.pkg`
    /// and `.mpkg` resolve to this one identifier (verified against the live
    /// type database, not assumed).
    private static let riskyIdentifiers: Set<String> = ["com.apple.installer-package-archive"]

    static func isRisky(filename: String) -> Bool {
        let ext = (filename as NSString).pathExtension
        guard !ext.isEmpty, let type = UTType(filenameExtension: ext) else { return false }
        if riskyIdentifiers.contains(type.identifier) { return true }
        if type.supertypes.contains(where: { riskyIdentifiers.contains($0.identifier) }) { return true }
        return executableTypes.contains { type.conforms(to: $0) }
    }
}
