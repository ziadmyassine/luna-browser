//
//  UpdateRelease.swift
//  Luna
//
//  What a GitHub release says about itself, read into what the updater needs,
//  and nothing that touches the network or the disk — so every rule about
//  which release counts can be asserted from a JSON string.
//
//  The feed is the repo's own "latest release": GitHub leaves drafts and
//  pre-releases out of it, so publishing a release is the whole of shipping
//  one. The release carries `Luna.zip` — the app, zipped with `ditto` — and
//  the workflow that builds it (`.github/workflows/release.yml`) is the only
//  thing that makes one.
//

import Foundation

/// A version as people write it — `0.2.0`, or a tag's `v0.2.0`. Compared part
/// by part as numbers, so 0.10.0 is newer than 0.9.0.
struct UpdateVersion: Comparable, CustomStringConvertible, Sendable {

    let parts: [Int]

    init?(_ text: String) {
        var trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.first == "v" || trimmed.first == "V" { trimmed.removeFirst() }
        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !parts.isEmpty, parts.allSatisfy({ $0 != nil }) else { return nil }
        self.parts = parts.compactMap(\.self)
    }

    var description: String { parts.map(String.init).joined(separator: ".") }

    /// Missing parts are zeros: 1.2 and 1.2.0 are the same version.
    static func < (lhs: Self, rhs: Self) -> Bool {
        for index in 0..<max(lhs.parts.count, rhs.parts.count) {
            let left = index < lhs.parts.count ? lhs.parts[index] : 0
            let right = index < rhs.parts.count ? rhs.parts[index] : 0
            if left != right { return left < right }
        }
        return false
    }

    static func == (lhs: Self, rhs: Self) -> Bool { !(lhs < rhs) && !(rhs < lhs) }
}

struct UpdateRelease: Equatable, Sendable {

    let version: UpdateVersion
    /// The zip the updater installs.
    let archive: URL
    /// Hex SHA-256 of the zip. A release without one is not offered: the
    /// download is checked against it before anything is unpacked.
    let sha256: String
    /// The release's page, for a build that cannot install on its own.
    let page: URL
    /// The release's own words, first paragraph, for the About row.
    let notes: String?

    /// The repo the feed is read from, and the only one an archive may come
    /// from.
    static let repository = "ziadmyassine/luna-browser"
    static let feed = URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!
    static let archiveName = "Luna.zip"

    /// Reads GitHub's release JSON. Nil for anything that is not a release
    /// Luna can install: no version in the tag, no `Luna.zip`, no checksum, or
    /// a zip that is not on this repo's own download path over https.
    ///
    /// The checksum is GitHub's own `digest` on the asset where there is one,
    /// and otherwise a `sha256:` line the workflow writes into the notes.
    static func parse(_ data: Data) -> UpdateRelease? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["draft"] as? Bool != true,
              json["prerelease"] as? Bool != true,
              let tag = json["tag_name"] as? String,
              let version = UpdateVersion(tag),
              let page = (json["html_url"] as? String).flatMap(URL.init(string:)),
              let assets = json["assets"] as? [[String: Any]],
              let asset = assets.first(where: { $0["name"] as? String == archiveName }),
              let archive = (asset["browser_download_url"] as? String).flatMap(URL.init(string:)),
              isOurs(archive)
        else { return nil }
        let body = json["body"] as? String
        guard let sha = digest(asset["digest"]) ?? digest(inNotes: body) else { return nil }
        return UpdateRelease(version: version, archive: archive, sha256: sha, page: page, notes: firstParagraph(of: body))
    }

    private static func isOurs(_ url: URL) -> Bool {
        url.scheme == "https"
            && url.host == "github.com"
            && url.path.hasPrefix("/\(repository)/releases/download/")
    }

    /// `sha256:` followed by 64 hex digits.
    private static func digest(_ value: Any?) -> String? {
        guard let text = (value as? String)?.lowercased(), text.hasPrefix("sha256:") else { return nil }
        let hex = String(text.dropFirst("sha256:".count)).trimmingCharacters(in: .whitespaces)
        return hex.count == 64 && hex.allSatisfy(\.isHexDigit) ? hex : nil
    }

    private static func digest(inNotes body: String?) -> String? {
        body?.split(whereSeparator: \.isNewline).lazy.compactMap { digest(String($0)) }.first
    }

    private static func firstParagraph(of body: String?) -> String? {
        let paragraph = body?
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty && !$0.lowercased().hasPrefix("sha256:") }
        return paragraph
    }
}
