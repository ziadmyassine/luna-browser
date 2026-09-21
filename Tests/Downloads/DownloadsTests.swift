//
//  DownloadsTests.swift
//  LunaTests
//
//  The four pieces of the downloads feature that are decisions rather than
//  drawing: what a server-supplied filename becomes, where it goes when that
//  name is taken, which types stop and ask (§15.4), and whether §5.1's
//  timeline actually adds up to 0.40 s.
//
//  The last one is the reason this file exists. The particle sweep can only be
//  seen to be wrong, and by the time anyone sees it the numbers have been
//  wrong for a month.
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

final class ParticleSweepTimelineTests: XCTestCase {

    private let total = Tokens.Motion.downloadsParticleSweep.duration
    private let dissolve = Tokens.Motion.particleDissolve.duration
    private let stagger = Tokens.Motion.particleStagger

    /// §5.1: 0.22 s dissolve + 0.18 s settle = the 0.40 s total §6 exempts from
    /// the 0.35 s budget. If someone nudges one of the three, this fails.
    func testPublishedDurationsAddUp() {
        XCTAssertEqual(dissolve + Tokens.Motion.particleSettle.duration, total, accuracy: 0.0001)
    }

    func testStartsAtHomeFullyOpaque() {
        for sweep in [0.0, 0.5, 1.0] as [CGFloat] {
            let frame = ParticleSweep.phase(sweep: sweep, at: 0)
            XCTAssertEqual(frame.displacement, 0, accuracy: 0.0001)
            XCTAssertEqual(frame.alpha, 1, accuracy: 0.0001)
        }
    }

    func testDissolvesToNothingAndComesBack() {
        // Fully gone at the end of its own dissolve slice…
        XCTAssertEqual(ParticleSweep.phase(sweep: 0, at: dissolve - stagger).alpha, 0, accuracy: 0.0001)
        // …and fully home again by the end of the whole sweep.
        let settled = ParticleSweep.phase(sweep: 1, at: total)
        XCTAssertEqual(settled.alpha, 1, accuracy: 0.0001)
        XCTAssertEqual(settled.displacement, 0, accuracy: 0.0001)
    }

    /// The left→right sweep is the whole point of §5.1's step 2: at any instant
    /// during the dissolve a particle on the left must be further gone than one
    /// on the right.
    func testTheDissolveIsDirectional() {
        let mid = dissolve / 2
        let left = ParticleSweep.phase(sweep: 0, at: mid)
        let right = ParticleSweep.phase(sweep: 1, at: mid)
        XCTAssertLessThan(left.alpha, right.alpha)
        XCTAssertGreaterThan(left.displacement, right.displacement)
    }

    /// Nothing may still be moving after 0.40 s — §6's budget is the contract.
    func testNothingRunsPastTheTotal() {
        for sweep in stride(from: 0.0, through: 1.0, by: 0.1) {
            let frame = ParticleSweep.phase(sweep: CGFloat(sweep), at: total)
            XCTAssertEqual(frame.alpha, 1, accuracy: 0.0001, "sweep \(sweep) still fading at 0.40 s")
            XCTAssertEqual(frame.displacement, 0, accuracy: 0.0001, "sweep \(sweep) still moving at 0.40 s")
        }
    }
}
