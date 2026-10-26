//
//  ReportLinkTests.swift
//  LunaTests
//
//  Help ▸ Report a Bug… and Suggest an Idea… open GitHub's own issue forms,
//  filled in by URL. These are the addresses; nothing here opens one.
//

import XCTest
@testable import Luna

@MainActor
final class ReportLinkTests: XCTestCase {

    private func fields(_ link: URL) throws -> [String: String] {
        let items = try XCTUnwrap(URLComponents(url: link, resolvingAgainstBaseURL: false)?.queryItems)
        return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
    }

    private func bug(_ page: String?) -> URL {
        ReportLink.bug(luna: "0.2.1 (57), release, a1b2c3d", macos: "Version 26.1 (Build 25B78)",
                       url: page.flatMap(URL.init(string:)))
    }

    func testABugFillsInTheFormsFields() throws {
        let link = bug("https://example.com/a b?x=1&y=2+3#top")
        XCTAssertEqual(link.host(), "github.com")
        XCTAssertEqual(link.path(), "/ziadmyassine/luna-browser/issues/new")
        XCTAssertEqual(try fields(link), [
            "template": "bug_report.yml",
            "luna": "0.2.1 (57), release, a1b2c3d",
            "macos": "Version 26.1 (Build 25B78)",
            "steps": "1. Open https://example.com/a%20b?x=1&y=2+3#top\n2. "
        ])
    }

    /// GitHub reads a bare `+` in a query as a space.
    func testAPlusSurvivesTheTrip() {
        XCTAssertFalse(bug("https://example.com/?q=a+b").query(percentEncoded: true)?.contains("+") ?? true)
    }

    func testASecretInThePagesAddressIsHidden() throws {
        let steps = try XCTUnwrap(fields(bug("https://example.com/?token=abc"))["steps"])
        XCTAssertFalse(steps.contains("abc"), steps)
        XCTAssertTrue(steps.contains("token=[hidden]"), steps)
    }

    func testNoPageLeavesTheStepsOut() throws {
        XCTAssertNil(try fields(bug(nil))["steps"])
    }

    // MARK: - Context and length

    private func bug(_ page: String?, context: [String]) -> URL {
        ReportLink.bug(luna: "0.2.1 (57), release, a1b2c3d", macos: "Version 26.1 (Build 25B78)",
                       url: page.flatMap(URL.init(string:)), context: context)
    }

    func testTheContextFollowsTheSteps() throws {
        let link = bug("https://example.com/", context: ["Page: \"Moon\", zoom 100 %", "Before this: New Tab"])
        XCTAssertEqual(
            try fields(link)["steps"],
            "1. Open https://example.com/\n2. \n\nPage: \"Moon\", zoom 100 %\nBefore this: New Tab"
        )
    }

    func testContextWithoutAPageStillArrives() throws {
        XCTAssertEqual(try fields(bug(nil, context: ["Page: a", "Site: b"]))["steps"], "Page: a\nSite: b")
    }

    func testALongContextLosesItsLastLinesFirst() throws {
        let lines = (1...5).map { "\($0)" + String(repeating: "x", count: 1_499) }
        let link = bug("https://example.com/", context: lines)
        XCTAssertLessThanOrEqual(link.absoluteString.count, ReportLink.limit)
        let steps = try XCTUnwrap(fields(link)["steps"])
        XCTAssertTrue(steps.contains(lines[0]), "the first line went")
        XCTAssertFalse(steps.contains(lines[4]), "the last line stayed")
    }

    func testAHugeAddressIsClippedToFit() throws {
        let link = bug("https://example.com/" + String(repeating: "a", count: 10_000), context: ["Page: a"])
        XCTAssertLessThanOrEqual(link.absoluteString.count, ReportLink.limit)
        XCTAssertTrue(try XCTUnwrap(fields(link)["steps"]).hasPrefix("1. Open https://example.com/"))
    }

    /// GitHub leaves a dropdown unfilled from the URL (#238), so the layout
    /// travels in the context's first line instead.
    func testNoLinkSendsTheLayoutDropdown() {
        XCTAssertFalse(bug("https://example.com/").absoluteString.contains("layout="))
    }

    /// A parameter the reporter has no permission for turns the page into a 404.
    func testNoLinkAsksForLabelsOrProjects() {
        for link in [bug("https://example.com/"), ReportLink.idea] {
            XCTAssertFalse(link.absoluteString.contains("labels="), link.absoluteString)
            XCTAssertFalse(link.absoluteString.contains("projects="), link.absoluteString)
        }
    }

    func testAnIdeaOpensTheFeatureForm() {
        XCTAssertEqual(
            ReportLink.idea.absoluteString,
            "https://github.com/ziadmyassine/luna-browser/issues/new?template=feature_request.yml"
        )
    }

    /// Every source build reads `0.1.0 (1)`, so the build is stamped with
    /// the commit it came from (`project.yml`'s post-build script).
    func testTheBuildNamesItsCommit() throws {
        let commit = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "LunaCommit") as? String)
        XCTAssertNotNil(commit.wholeMatch(of: /[0-9a-f]{7,}(-dirty)?|unknown/), commit)
    }

    func testTheLunaLineNamesTheBuild() {
        XCTAssertEqual(
            ReportLink.lunaLine(version: "0.2.1", build: "57", release: true, commit: "a1b2c3d"),
            "0.2.1 (57), release, a1b2c3d"
        )
        XCTAssertEqual(
            ReportLink.lunaLine(version: "0.1.0", build: "1", release: false, commit: "a1b2c3d-dirty"),
            "0.1.0 (1), source, a1b2c3d-dirty"
        )
    }
}
