//
//  UpdateSwap.swift
//  Luna
//
//  The part of an update that touches the disk, off the main thread: fetch
//  the zip, check it, unpack it, check what came out, and put it where this
//  bundle is. Nothing changes until every check has passed, and the only
//  things ever removed are the scratch folder this makes and the `.old`
//  bundle it sets aside.
//
//  Only the bundle changes hands. The database, the defaults and the Keychain
//  are not read, moved or rewritten here.
//
//  What is checked, and what is not yet. Luna signs ad hoc until there is a
//  Developer ID certificate (TODO.md §24.4), so there is no team to hold a
//  new build to — the check a signed app makes on its successor. What stands
//  in for it: https to this repo's own download path, GitHub's SHA-256 of the
//  zip, and a bundle inside with Luna's identifier and a newer version. Once
//  Luna is signed, a code-signing requirement naming the team belongs in
//  `verify`.
//

import CryptoKit
import Foundation

enum UpdateSwap {

    enum Refused: Error, Equatable {
        case download, checksum, archive, wrongApp, notNewer, readOnly, move
    }

    /// Where this bundle lives, and so where the new one goes.
    static var target: URL { Bundle.main.bundleURL }

    /// The bundle set aside during a swap: a sibling, so both moves are
    /// renames on one volume.
    static var aside: URL {
        target.deletingLastPathComponent().appending(path: target.lastPathComponent + ".old")
    }

    static func install(_ release: UpdateRelease, over current: UpdateVersion) async throws {
        let files = FileManager.default
        // A folder that will not take a rename — /Applications owned by
        // another account, a disk image — cannot be updated from here.
        guard files.isWritableFile(atPath: target.deletingLastPathComponent().path) else { throw Refused.readOnly }

        // On the app's own volume, so the last move is a rename too.
        let scratch = (try? files.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: target,
            create: true
        )) ?? files.temporaryDirectory.appending(path: "luna-update-\(UUID().uuidString)")
        try files.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: scratch) }

        let zip = scratch.appending(path: UpdateRelease.archiveName)
        try await download(release.archive, to: zip)
        guard try digest(of: zip) == release.sha256 else { throw Refused.checksum }
        let unpacked = scratch.appending(path: "unpacked")
        try extract(zip, into: unpacked)
        guard let fresh = try files.contentsOfDirectory(at: unpacked, includingPropertiesForKeys: nil)
            .first(where: { $0.pathExtension == "app" })
        else { throw Refused.archive }
        try verify(fresh, newerThan: current)
        try swap(in: fresh)
    }

    private static func download(_ url: URL, to file: URL) async throws {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 120
        let (got, response) = try await URLSession.shared.download(for: request)
        guard (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? false else {
            throw Refused.download
        }
        // The session's copy is gone once this returns.
        try FileManager.default.moveItem(at: got, to: file)
    }

    static func digest(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var sha = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            sha.update(data: chunk)
        }
        return sha.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// `ditto`, as Archive Utility unpacks: permissions and the signature's
    /// extended attributes kept. No quarantine comes into it — Luna declares
    /// no `LSFileQuarantineEnabled`, so nothing it downloads carries the flag.
    private static func extract(_ zip: URL, into folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let ditto = Process()
        ditto.executableURL = URL(filePath: "/usr/bin/ditto")
        ditto.arguments = ["-x", "-k", zip.path, folder.path]
        ditto.standardOutput = FileHandle.nullDevice
        ditto.standardError = FileHandle.nullDevice
        try ditto.run()
        ditto.waitUntilExit()
        guard ditto.terminationStatus == 0 else { throw Refused.archive }
    }

    /// Luna, by identifier, and newer than the one running — by the version
    /// the bundle itself states, not the one the release's tag claimed.
    static func verify(_ bundle: URL, newerThan current: UpdateVersion) throws {
        guard let info = infoDictionary(of: bundle) else { throw Refused.archive }
        guard info["CFBundleIdentifier"] as? String == Bundle.main.bundleIdentifier else { throw Refused.wrongApp }
        guard let version = (info["CFBundleShortVersionString"] as? String).flatMap(UpdateVersion.init),
              version > current
        else { throw Refused.notNewer }
    }

    /// Two renames, and the first undone if the second fails. The running
    /// process keeps its files: the kernel follows the rename, so it goes on
    /// running from `.old` until it quits.
    private static func swap(in fresh: URL) throws {
        let files = FileManager.default
        sweep()
        guard !files.fileExists(atPath: aside.path) else { throw Refused.move }
        try files.moveItem(at: target, to: aside)
        do {
            try files.moveItem(at: fresh, to: target)
        } catch {
            try? files.moveItem(at: aside, to: target)
            throw Refused.move
        }
    }

    /// Removes the bundle a swap set aside once nothing runs from it: at quit,
    /// and at the next launch for a quit that was not clean. Only a `.old`
    /// that is Luna.
    static func sweep() {
        guard infoDictionary(of: aside)?["CFBundleIdentifier"] as? String == Bundle.main.bundleIdentifier else {
            return
        }
        try? FileManager.default.removeItem(at: aside)
    }

    private static func infoDictionary(of bundle: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: bundle.appending(path: "Contents/Info.plist")) else { return nil }
        return try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
    }
}
