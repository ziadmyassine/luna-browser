//
//  FileStorageCarryOver.swift
//  Luna
//
//  Where `FileStorageSeed` gets what file pages saved before Luna: the
//  `localStorage` of the `file://` origin in the Chromium browsers on this
//  Mac. Dia's deck boards and checklists were the case — opened in Luna, every
//  tick made in Dia was gone.
//
//  Read once, the first time a file page loads (18 ms for Dia's 16 MB store,
//  measured), and only for that one origin.
//

import Foundation

enum FileStorageCarryOver {

    /// The browsers asked, most likely first. The first one to have a key
    /// gives its value.
    static let sources: [ImportSource] = [.dia, .arc, .chrome, .brave, .edge, .chromium, .vivaldi, .opera, .atlas, .helium]

    static func entries() -> [String: String] {
        var result: [String: String] = [:]
        for directory in storageDirectories() {
            for (key, value) in ChromiumLocalStorage.entries(origin: "file://", in: directory) where result[key] == nil {
                result[key] = value
            }
        }
        return result
    }

    /// Each profile's `Local Storage/leveldb`, the default profile first.
    static func storageDirectories() -> [URL] {
        sources.flatMap { source -> [URL] in
            guard let root = ChromiumProfileLocator.userDataRoot(
                in: source.supportDirectoryURL,
                candidates: source.chromiumUserDataCandidates
            ) else { return [] }
            let profiles = ChromiumProfileLocator.profileDirectoryNames(in: root)
                .sorted { ($0 == "Default" ? 0 : 1, $0) < ($1 == "Default" ? 0 : 1, $1) }
            return profiles.map { profile in
                (profile.isEmpty ? root : root.appending(path: profile, directoryHint: .isDirectory))
                    .appending(path: "Local Storage/leveldb", directoryHint: .isDirectory)
            }
        }
    }
}
