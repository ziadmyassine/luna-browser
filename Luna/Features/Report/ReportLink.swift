//
//  ReportLink.swift
//  Luna
//
//  The addresses of the repo's issue forms (`.github/ISSUE_TEMPLATE`), filled
//  in by URL. Text fields only: GitHub leaves the `layout` dropdown unfilled
//  (#238), so the layout travels in the context. Never `labels=` or
//  `projects=`: a parameter the reporter has no permission for turns the
//  page into a 404, and the form's own `labels:` applies them anyway.
//

import Foundation
import LunaControl

enum ReportLink {

    private static let newIssue = "https://github.com/ziadmyassine/luna-browser/issues/new"

    static let idea = URL(string: "\(newIssue)?template=feature_request.yml")!

    /// This repo's issues, the list, one issue or the new-issue form.
    static func isIssuePage(_ url: URL?) -> Bool {
        let issues = "/ziadmyassine/luna-browser/issues"
        guard let url, url.host() == "github.com" else { return false }
        return url.path() == issues || url.path().hasPrefix(issues + "/")
    }

    /// The longest link Luna builds. Measured signed out on 2026-10-23: a
    /// 7,011-character link opened the form and 7,015 did not, and a 2 KB
    /// cookie header brought that down to about 5,000. GitHub's limit is
    /// the URL and the request headers together, so this leaves room.
    static let limit = 4_000

    /// The field ids are `bug_report.yml`'s. The page's address goes through
    /// `ControlRedactor.scrub`, because the issue is public, and is cut to
    /// 1,000 characters. `context` follows the reporter's numbered lines,
    /// most important first: over `limit`, the last lines go first.
    static func bug(luna: String, macos: String, url: URL?, context: [String] = []) -> URL {
        let open = url.map { "1. Open \(ControlRedactor.scrub($0.absoluteString).prefix(1_000))\n2. " }
        var context = context
        while true {
            let steps = [open, context.isEmpty ? nil : context.joined(separator: "\n")]
                .compactMap { $0 }.joined(separator: "\n\n")
            let link = link([
                ("template", "bug_report.yml"), ("luna", luna), ("macos", macos), ("steps", steps)
            ].filter { !$0.1.isEmpty })
            if link.absoluteString.count <= limit || context.isEmpty { return link }
            context.removeLast()
        }
    }

    private static func link(_ fields: [(String, String)]) -> URL {
        var components = URLComponents(string: newIssue)!
        // `urlQueryAllowed` keeps `&`, `=` and `+`, and GitHub reads a bare `+` as a space.
        let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+"))
        components.percentEncodedQueryItems = fields.map {
            URLQueryItem(name: $0.0, value: $0.1.addingPercentEncoding(withAllowedCharacters: allowed))
        }
        return components.url!
    }

    /// `0.2.1 (57), release, a1b2c3d`: the build, whether it came from a
    /// release, and the commit it was built from.
    static func lunaLine(version: String, build: String, release: Bool, commit: String) -> String {
        "\(version) (\(build)), \(release ? "release" : "source"), \(commit)"
    }
}
