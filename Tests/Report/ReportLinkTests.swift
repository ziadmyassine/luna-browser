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
                       url: page.flatMap(URL.init(string:)), layout: "Top bar")
    }

    func testABugFillsInTheFormsFields() throws {
        let link = bug("https://example.com/a b?x=1&y=2+3#top")
        XCTAssertEqual(link.host(), "github.com")
        XCTAssertEqual(link.path(), "/ziadmyassine/luna-browser/issues/new")
        XCTAssertEqual(try fields(link), [
            "template": "bug_report.yml",
            "luna": "0.2.1 (57), release, a1b2c3d",
            "macos": "Version 26.1 (Build 25B78)",
            "steps": "1. Open https://example.com/a%20b?x=1&y=2+3#top\n2. ",
            "layout": "Top bar"
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
