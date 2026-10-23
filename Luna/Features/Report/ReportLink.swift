//
//  ReportLink.swift
//  Luna
//
//  The addresses of the repo's issue forms (`.github/ISSUE_TEMPLATE`), filled
//  in by URL. GitHub's docs promise only the form's text fields, so `layout`,
//  a dropdown, may be ignored. Never `labels=` or `projects=`: a parameter the
//  reporter has no permission for turns the page into a 404, and the form's
//  own `labels:` applies them anyway.
//

import Foundation
import LunaControl

enum ReportLink {

    private static let newIssue = "https://github.com/ziadmyassine/luna-browser/issues/new"

    static let idea = URL(string: "\(newIssue)?template=feature_request.yml")!

    /// The field ids are `bug_report.yml`'s. The page's address goes through
    /// `ControlRedactor.scrub`, because the issue is public.
    static func bug(luna: String, macos: String, url: URL?, layout: String) -> URL {
        var fields = [("template", "bug_report.yml"), ("luna", luna), ("macos", macos)]
        if let url { fields.append(("steps", "1. Open \(ControlRedactor.scrub(url.absoluteString))\n2. ")) }
        fields.append(("layout", layout))
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
