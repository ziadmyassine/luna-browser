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
//  At the end, the one piece of §5.0's list that is behaviour: a list a
//  download opened does not stand between the page and the next click, and
//  that click still closes it.
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

/// §5.0's list, opened by a download rather than by a press. The page stays
/// the user's while it is up: a click on the next file's link has to reach
/// that link instead of closing the list.
@MainActor
final class DownloadsAnnounceTests: XCTestCase {

    private func window() -> (NSWindow, NSView) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1070, height: 801),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )
        let anchor = NSView(frame: NSRect(x: 20, y: 20, width: 28, height: 28))
        window.contentView?.addSubview(anchor)
        return (window, anchor)
    }

    /// The middle of the window, well clear of the list standing on a button
    /// in the corner.
    private let onThePage = NSPoint(x: 700, y: 500)

    func testAListADownloadOpenedLetsThePageTakeTheClick() {
        let (window, anchor) = window()
        let controller = DownloadsPanelController(manager: DownloadManager())
        controller.announce(in: window, from: anchor, edge: .above)
        let sheet = try? XCTUnwrap(controller.presented)
        sheet?.layoutSubtreeIfNeeded()
        XCTAssertNil(sheet?.hitTest(onThePage), "the sheet is still eating the click on the page")
        XCTAssertNotNil(sheet?.hitTest(NSPoint(x: sheet?.body.frame.midX ?? 0, y: sheet?.body.frame.midY ?? 0)))
        controller.dismiss()
    }

    /// It still closes on a click beside it — anywhere but the list and the
    /// button, which toggles it by itself.
    func testAClickBesideTheListClosesItAndTheButtonIsSpared() throws {
        let (window, anchor) = window()
        let controller = DownloadsPanelController(manager: DownloadManager())
        controller.announce(in: window, from: anchor, edge: .above)
        let sheet = try XCTUnwrap(controller.presented)
        sheet.layoutSubtreeIfNeeded()
        func click(_ point: NSPoint, in view: NSView) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(
                with: .leftMouseDown,
                location: view.convert(point, to: nil),
                modifierFlags: [],
                timestamp: 0,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 1
            ))
        }
        let spared: [NSView?] = [sheet.body, anchor]
        let body = sheet.body.bounds
        XCTAssertTrue(PopoutController.lands(try click(onThePage, in: sheet), outside: spared))
        XCTAssertFalse(PopoutController.lands(try click(NSPoint(x: body.midX, y: body.midY), in: sheet.body), outside: spared))
        XCTAssertFalse(PopoutController.lands(try click(NSPoint(x: 14, y: 14), in: anchor), outside: spared))
        controller.dismiss()
    }

    /// A list the user opened keeps the ordinary rule: a click beside it
    /// closes it and goes no further.
    func testAListOpenedWithTheButtonStillCatchesTheClick() {
        let (window, anchor) = window()
        let controller = DownloadsPanelController(manager: DownloadManager())
        controller.toggle(in: window, from: anchor, edge: .above)
        controller.presented?.layoutSubtreeIfNeeded()
        XCTAssertTrue(controller.presented?.hitTest(onThePage) === controller.presented)
        controller.dismiss()
    }

    /// The icon is looked up once, not on every progress refresh.
    func testTheIconIsReadOnce() {
        let item = DownloadItem(request: nil, pageURL: nil, filename: "report.pdf", spaceID: nil)
        XCTAssertTrue(item.icon === item.icon)
    }
}
