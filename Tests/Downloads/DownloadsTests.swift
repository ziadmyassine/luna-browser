//
//  DownloadsTests.swift
//  LunaTests
//
//  The three pieces of the downloads feature that are decisions rather than
//  drawing: what a server-supplied filename becomes, where it goes when that
//  name is taken, and which types stop and ask (§15.4).
//
//  Every one of them is a rule about a hostile input that arrives once in a
//  thousand downloads and is unreviewable by eye when it does. §5.0's arc is
//  the same argument about geometry, and lives in `DownloadFlightTests`.
//

import XCTest
@testable import Luna

final class DownloadDestinationTests: XCTestCase {

    /// Separators are flattened, not dropped. Both rules are equally safe — nothing
    /// escapes `~/Downloads` either way — but flattening keeps the server's intent
    /// visible: a legitimate `invoices/2026/march.pdf` stays informative, and a
    /// hostile `../../etc/passwd` lands as something visibly odd rather than as a
    /// plausible-looking `passwd`. Taking the basename would do the opposite on both.
    func testSanitizeFlattensPathsRatherThanTakingTheBasename() {
        XCTAssertEqual(DownloadDestination.sanitize("../../etc/passwd"), "_.._etc_passwd")
        XCTAssertEqual(DownloadDestination.sanitize("a/b/c.pdf"), "a_b_c.pdf")
        // What actually matters: the result is a single path component.
        for hostile in ["../../etc/passwd", "a/b/c.pdf", "/etc/shadow", "..", "./../x"] {
            let name = DownloadDestination.sanitize(hostile)
            XCTAssertFalse(name.contains("/"), "\(hostile) -> \(name) still contains a separator")
            XCTAssertFalse(name.hasPrefix("."), "\(hostile) -> \(name) is hidden or relative")
        }
    }

    func testSanitizeStripsNullBytesAndLeadingDots() {
        XCTAssertEqual(DownloadDestination.sanitize("re\0port.pdf"), "report.pdf")
        XCTAssertEqual(DownloadDestination.sanitize("...hidden.pdf"), "hidden.pdf")
    }

    func testSanitizeNeverReturnsAnEmptyName() {
        XCTAssertEqual(DownloadDestination.sanitize(""), DownloadDestination.fallbackName)
        XCTAssertEqual(DownloadDestination.sanitize("   "), DownloadDestination.fallbackName)
        XCTAssertEqual(DownloadDestination.sanitize("..."), DownloadDestination.fallbackName)
    }

    func testSanitizeClampsToTheFilesystemByteLimit() {
        let name = String(repeating: "é", count: 400) + ".pdf"
        let result = DownloadDestination.sanitize(name)
        XCTAssertLessThanOrEqual(result.utf8.count, 255)
        XCTAssertTrue(result.hasSuffix(".pdf"), "the extension must survive the clamp")
    }

    func testUniqueFollowsFinderNumbering() {
        let folder = URL(fileURLWithPath: "/tmp")
        let taken: Set<String> = ["/tmp/report.pdf", "/tmp/report 2.pdf"]
        let result = DownloadDestination.unique(folder.appending(path: "report.pdf")) {
            taken.contains($0.path)
        }
        XCTAssertEqual(result.lastPathComponent, "report 3.pdf")
    }

    func testUniqueLeavesAFreeNameAlone() {
        let url = URL(fileURLWithPath: "/tmp/report.pdf")
        XCTAssertEqual(DownloadDestination.unique(url) { _ in false }, url)
    }

    func testUniqueHandlesNamesWithNoExtension() {
        let url = URL(fileURLWithPath: "/tmp/archive")
        let result = DownloadDestination.unique(url) { $0.path == "/tmp/archive" }
        XCTAssertEqual(result.lastPathComponent, "archive 2")
    }
}

final class DownloadRiskTests: XCTestCase {

    func testExecutableTypesWarn() {
        for name in ["Installer.dmg", "Setup.pkg", "Tool.app", "run.sh", "thing.command"] {
            XCTAssertTrue(DownloadRisk.isRisky(filename: name), "\(name) should warn (§15.4)")
        }
    }

    func testOrdinaryDownloadsDoNot() {
        // Warning about every archive trains the user to click through, which
        // is worse than not warning at all.
        for name in ["statement.pdf", "photo.png", "bundle.zip", "notes.txt", "data.csv", "noextension"] {
            XCTAssertFalse(DownloadRisk.isRisky(filename: name), "\(name) should not warn")
        }
    }
}
