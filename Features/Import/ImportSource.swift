//
//  ImportSource.swift
//  Luna — §23.2, §30.18
//
//  Which browsers Luna can import from, where their data is, and which are on
//  this Mac. Detection is on-disk only, because a directory alone is not
//  evidence: `~/Library/Application Support/Arc`, `Chromium`, `Microsoft Edge`,
//  `Vivaldi` and `com.operasoftware.Opera` all exist on the development machine
//  as empty leftovers with none of those browsers installed. A source counts as
//  importable only when a profile directory with a real `History` or
//  `Preferences` is there to read.
//

import Foundation

/// A browser Luna can read.
enum ImportSource: String, CaseIterable, Sendable, Identifiable {
    case dia
    case arc
    case chrome
    case chromium
    case brave
    case edge
    case vivaldi
    case opera
    case atlas
    case helium
    case safari

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .dia: "Dia"
        case .arc: "Arc"
        case .chrome: "Google Chrome"
        case .chromium: "Chromium"
        case .brave: "Brave"
        case .edge: "Microsoft Edge"
        case .vivaldi: "Vivaldi"
        case .opera: "Opera"
        case .atlas: "Atlas"
        case .helium: "Helium"
        case .safari: "Safari"
        }
    }

    /// Verified from the installed app on this Mac for Dia (`company.thebrowser.dia`,
    /// 1.48.0) and Safari; the rest are the published identifiers. Detection
    /// does not use these — a screen does, to fetch the app icon.
    var bundleIdentifier: String {
        switch self {
        case .dia: "company.thebrowser.dia"
        case .arc: "company.thebrowser.Browser"
        case .chrome: "com.google.Chrome"
        case .chromium: "org.chromium.Chromium"
        case .brave: "com.brave.Browser"
        case .edge: "com.microsoft.edgemac"
        case .vivaldi: "com.vivaldi.Vivaldi"
        case .opera: "com.operasoftware.Opera"
        case .atlas: "com.openai.atlas"
        case .helium: "net.imput.helium"
        case .safari: "com.apple.Safari"
        }
    }

    /// Support directory, relative to the user's real home.
    ///
    /// Dia's is verified on this Mac: `~/Library/Application Support/Dia/`
    /// holds `User Data/` (a stock Chromium profile root), plus Dia's own
    /// `StorableAutoArchive.json`, `BlockList.json` and `Favicons/`. Only the
    /// Chromium half is readable — everything Dia added is encrypted.
    var homeRelativeSupportPath: String {
        switch self {
        case .dia: "Library/Application Support/Dia"
        case .arc: "Library/Application Support/Arc"
        case .chrome: "Library/Application Support/Google/Chrome"
        case .chromium: "Library/Application Support/Chromium"
        case .brave: "Library/Application Support/BraveSoftware"
        case .edge: "Library/Application Support/Microsoft Edge"
        case .vivaldi: "Library/Application Support/Vivaldi"
        case .opera: "Library/Application Support/com.operasoftware.Opera"
        // Unverified: neither browser is installed on this Mac, so these are
        // the published layouts and nothing more. A wrong path degrades to
        // "not installed", never to a crash or a half-read profile.
        case .atlas: "Library/Application Support/Atlas"
        case .helium: "Library/Application Support/net.imput.helium"
        case .safari: "Library/Safari"
        }
    }

    /// Where the Chromium `User Data` root sits inside the support directory,
    /// in the order to try. `""` means the support directory is the root.
    /// Empty means this source is not a Chromium profile store.
    ///
    /// Verified: Dia and Arc nest under `User Data/`; Brave's support directory
    /// is the vendor folder with the browser one level down.
    var chromiumUserDataCandidates: [String] {
        switch self {
        case .dia, .arc: ["User Data"]
        case .chrome, .chromium, .edge, .vivaldi, .opera, .atlas, .helium: [""]
        case .brave: ["Brave-Browser", "Brave-Browser-Beta", "Brave-Browser-Nightly"]
        case .safari: []
        }
    }

    var isChromiumFamily: Bool { !chromiumUserDataCandidates.isEmpty }

    var supportDirectoryURL: URL {
        Self.realHomeDirectory.appending(path: homeRelativeSupportPath, directoryHint: .isDirectory)
    }

    /// The user's real home directory.
    ///
    /// Luna is unsandboxed on purpose (§22.1, D8 — the sandbox blocks default
    /// browser registration), so `NSHomeDirectory()` is already correct today.
    /// `getpwuid` is used anyway because it stays correct if that ever changes:
    /// in a sandboxed process the Foundation answers resolve to the container,
    /// and an importer that silently looks in the wrong home reports every
    /// browser as "not installed". That exact bug shipped once already.
    static var realHomeDirectory: URL {
        if let entry = getpwuid(getuid()), let directory = entry.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: directory), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }
}

/// One profile inside a Chromium `User Data` root.
///
/// `Default` is frequently not the user's real profile: on this Mac Dia's
/// `Default` is named "Work" and `Profile 1` is the one in daily use
/// (`profile.last_used`). Always show `displayName`, never the directory name.
struct ChromiumProfile: Sendable, Hashable, Identifiable {
    /// Directory name inside `User Data`, or `""` when the root is itself the
    /// profile (Opera's single-profile layout).
    var directoryName: String
    var displayName: String?
    var isLastUsed: Bool = false

    var id: String { directoryName }

    /// What a picker should show.
    func label(for source: ImportSource) -> String {
        if let displayName, !displayName.isEmpty { return displayName }
        // "Default" is a directory name, not a profile name.
        return directoryName.isEmpty || directoryName == "Default" ? source.displayName : directoryName
    }
}

/// What the user can do about a source Luna cannot read, where there is
/// something to do. Most unavailable sources have no answer — a browser that
/// is not installed is not a problem to solve — so this is nil far more often
/// than not.
enum ImportRemedy: Sendable, Hashable, CaseIterable {
    case fullDiskAccess

    var title: String { String(localized: "Grant Luna Full Disk Access") }

    /// The Full Disk Access list itself, not the top of Privacy & Security.
    /// `Privacy_AllFiles` is the anchor macOS uses for that pane; without it
    /// the button lands the user on a page of nineteen rows and the sentence
    /// it replaced was more use than the button.
    var settingsURL: URL? {
        URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles")
    }
}

/// A source that is actually on this Mac, with the profiles it offers.
struct DetectedSource: Sendable, Hashable, Identifiable {
    var source: ImportSource
    var profiles: [ChromiumProfile]
    /// `false` means "list it greyed out" (§30.18) rather than "hide it".
    var isAvailable: Bool
    /// Why it is unavailable, if it is. Safari's is always Full Disk Access.
    var unavailableReason: String?
    /// Set when the reason is one the user can act on, so a screen can offer
    /// the door rather than describe where it is.
    var remedy: ImportRemedy?

    var id: String { source.id }
}

/// Finds `User Data` roots and enumerates the profiles inside them.
///
/// Every decoding step is `static` and takes `Data`, so it is testable without
/// a browser installed; only the two disk functions touch the filesystem.
enum ChromiumProfileLocator {

    /// The first candidate that holds a `Local State` or a profile directory.
    static func userDataRoot(in supportDirectory: URL, candidates: [String]) -> URL? {
        for candidate in candidates {
            let root = candidate.isEmpty
                ? supportDirectory
                : supportDirectory.appending(path: candidate, directoryHint: .isDirectory)
            if FileManager.default.fileExists(atPath: root.appending(path: "Local State").path) {
                return root
            }
            if !profileDirectoryNames(in: root).isEmpty { return root }
        }
        return nil
    }

    /// Profile directories found on disk. A directory counts when it holds a
    /// `Preferences` or a `History`; `[""]` means the root is itself the
    /// profile, which is Opera's layout.
    static func profileDirectoryNames(in userDataRoot: URL) -> [String] {
        func isProfile(_ directory: URL) -> Bool {
            FileManager.default.fileExists(atPath: directory.appending(path: "Preferences").path)
                || FileManager.default.fileExists(atPath: directory.appending(path: "History").path)
        }

        let entries = (try? FileManager.default.contentsOfDirectory(atPath: userDataRoot.path)) ?? []
        let named = entries
            .filter { isProfile(userDataRoot.appending(path: $0, directoryHint: .isDirectory)) }
            .sorted(by: profileOrder)
        if !named.isEmpty { return named }
        return isProfile(userDataRoot) ? [""] : []
    }

    /// Parses `Local State` → `profile.info_cache.<dir>.name` and `profile.last_used`.
    ///
    /// `JSONSerialization` rather than `Decodable`: the file carries keys that
    /// change between Chromium releases, and a lenient walk survives that where
    /// a strict decode throws the whole import away.
    static func decodeProfiles(localState data: Data, existingDirectories known: [String]) -> [ChromiumProfile] {
        let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let profile = root?["profile"] as? [String: Any]
        let infoCache = profile?["info_cache"] as? [String: Any] ?? [:]
        let lastUsed = profile?["last_used"] as? String

        let directories = known.isEmpty ? infoCache.keys.sorted(by: profileOrder) : known
        return directories.map { directory in
            let info = infoCache[directory] as? [String: Any]
            let name = (info?["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return ChromiumProfile(
                directoryName: directory,
                displayName: name,
                isLastUsed: directory == lastUsed
            )
        }
    }

    static func profiles(inUserDataRoot userDataRoot: URL) -> [ChromiumProfile] {
        let directories = profileDirectoryNames(in: userDataRoot)
        if let data = try? Data(contentsOf: userDataRoot.appending(path: "Local State")) {
            let profiles = decodeProfiles(localState: data, existingDirectories: directories)
            if !profiles.isEmpty { return profiles }
        }
        return directories.map { ChromiumProfile(directoryName: $0) }
    }

    /// `Default` first, then `Profile 1`, `Profile 2`, … numerically.
    private static func profileOrder(_ lhs: String, _ rhs: String) -> Bool {
        if lhs == "Default" { return rhs != "Default" }
        if rhs == "Default" { return false }
        let left = Int(lhs.dropFirst("Profile ".count))
        let right = Int(rhs.dropFirst("Profile ".count))
        if let left, let right { return left < right }
        return lhs < rhs
    }
}

/// Which browsers are on this Mac. The list a screen renders (§30.17–30.18):
/// available first, the rest greyed with a reason.
enum ImportSourceDetector {

    static func detect() -> [DetectedSource] {
        ImportSource.allCases.map(detect(_:)).sorted { lhs, rhs in
            if lhs.isAvailable != rhs.isAvailable { return lhs.isAvailable }
            return lhs.source.displayName < rhs.source.displayName
        }
    }

    static func detect(_ source: ImportSource) -> DetectedSource {
        guard source.isChromiumFamily else {
            // Safari: the app is always installed, the data never readable
            // without Full Disk Access. Verified on this Mac — an unsandboxed
            // `ls ~/Library/Safari` is "Operation not permitted". §23.2's
            // exported-HTML path is the one that works.
            let readable = (try? FileManager.default.contentsOfDirectory(atPath: source.supportDirectoryURL.path)) != nil
            return DetectedSource(
                source: source,
                profiles: readable ? [ChromiumProfile(directoryName: "")] : [],
                isAvailable: readable,
                unavailableReason: readable
                    ? nil
                    : ImportError.needsFullDiskAccess(source.displayName).errorDescription,
                remedy: readable ? nil : .fullDiskAccess
            )
        }

        guard
            let root = ChromiumProfileLocator.userDataRoot(
                in: source.supportDirectoryURL,
                candidates: source.chromiumUserDataCandidates
            )
        else {
            return DetectedSource(
                source: source,
                profiles: [],
                isAvailable: false,
                unavailableReason: ImportError.notInstalled(source.displayName).errorDescription
            )
        }

        let profiles = ChromiumProfileLocator.profiles(inUserDataRoot: root)
        return DetectedSource(
            source: source,
            profiles: profiles,
            isAvailable: !profiles.isEmpty,
            unavailableReason: profiles.isEmpty
                ? ImportError.noProfiles(source.displayName).errorDescription
                : nil
        )
    }
}
