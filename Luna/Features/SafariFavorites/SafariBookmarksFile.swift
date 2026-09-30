//
//  SafariBookmarksFile.swift
//  Luna
//
//  Reading and replacing `~/Library/Safari/Bookmarks.plist` the way Safari and
//  its sync agent do.
//
//  The agent writes the file while Safari is closed too, whenever another
//  device changes a bookmark, so a write here takes Safari's lock and only
//  replaces the file if it still holds what was read. Losing that race is not
//  an error: the caller reads again a few seconds later.
//
//  The folder is behind macOS's privacy protection. Reading it needs Full Disk
//  Access, which only the user can grant; without it every call here throws
//  `noAccess` and nothing is touched.
//

import Foundation
import IOKit

enum SafariBookmarksFile {

    enum Failure: Error, Equatable {
        /// Full Disk Access is off for Luna.
        case noAccess
        /// Safari or its agent holds the lock, or wrote the file since it was read.
        case busy
    }

    static var folder: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Safari", directoryHint: .isDirectory)
    }

    static func read(from folder: URL = folder) throws -> Data {
        do {
            return try Data(contentsOf: folder.appending(path: "Bookmarks.plist"))
        } catch let error as CocoaError where error.code == .fileReadNoPermission {
            throw Failure.noAccess
        } catch let error as NSError where error.domain == NSPOSIXErrorDomain && error.code == Int(EPERM) {
            throw Failure.noAccess
        }
    }

    /// Replaces the file with `data` if it still holds `expected`, under Safari's lock.
    static func replace(_ expected: Data, with data: Data, in folder: URL = folder) throws {
        guard let lock = SafariBookmarksLock.take(in: folder) else { throw Failure.busy }
        defer { lock.release() }
        guard try read(from: folder) == expected else { throw Failure.busy }
        try data.write(to: folder.appending(path: "Bookmarks.plist"), options: .atomic)
    }

    /// Tells a running Safari that the file changed under it: the distributed
    /// notifications Safari's bookmarks framework posts itself. They do not
    /// start an upload — measured, the sync agent ignores every notification,
    /// and only an edit Safari itself makes does (`SafariSyncNudge`).
    static func announceChange() {
        let center = DistributedNotificationCenter.default()
        for name in [
            "WebBookmarksDidReloadDistributedNotification",
            "WebBookmarksDataclassDidChangeNotification",
            "WebBookmarksDidReloadNotification"
        ] {
            center.postNotificationName(Notification.Name(name), object: nil, userInfo: nil, deliverImmediately: true)
        }
    }
}

/// The lock Safari and its sync agent hold while they write the file: a `lock`
/// folder beside it, with a `details.plist` naming the holder. Making a folder
/// is atomic, so exactly one process gets it; one left by a process that is no
/// longer running on this Mac is taken over.
struct SafariBookmarksLock {

    let folder: URL

    static func take(in safari: URL, now: Date = Date()) -> SafariBookmarksLock? {
        let folder = safari.appending(path: "lock", directoryHint: .isDirectory)
        if mkdir(folder.path, 0o755) != 0 {
            guard isStale(folder) else { return nil }
            try? FileManager.default.removeItem(at: folder)
            guard mkdir(folder.path, 0o755) == 0 else { return nil }
        }
        let details: [String: Any] = [
            "LockFileDate": now,
            "LockFileHostname": platformUUID ?? ProcessInfo.processInfo.hostName,
            "LockFileProcessID": Int(getpid()),
            "LockFileProcessName": ProcessInfo.processInfo.processName,
            "LockFileUsername": NSUserName()
        ]
        guard let data = try? PropertyListSerialization.data(fromPropertyList: details, format: .xml, options: 0),
              (try? data.write(to: folder.appending(path: "details.plist"))) != nil
        else {
            try? FileManager.default.removeItem(at: folder)
            return nil
        }
        return SafariBookmarksLock(folder: folder)
    }

    func release() {
        try? FileManager.default.removeItem(at: folder)
    }

    /// Held by a process that has gone, on this Mac. A lock from another Mac —
    /// a home folder on a network volume — is never judged stale from here.
    static func isStale(_ folder: URL) -> Bool {
        guard let data = try? Data(contentsOf: folder.appending(path: "details.plist")),
              let details = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let pid = details["LockFileProcessID"] as? Int,
              details["LockFileHostname"] as? String == platformUUID
        else { return false }
        return kill(pid_t(pid), 0) != 0 && errno == ESRCH
    }

    /// The Mac's hardware UUID, which is what Safari writes as the lock's host.
    static let platformUUID: String? = {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        return IORegistryEntryCreateCFProperty(service, "IOPlatformUUID" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? String
    }()
}
