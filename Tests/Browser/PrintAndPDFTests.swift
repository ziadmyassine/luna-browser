//
//  PrintAndPDFTests.swift
//  LunaTests
//
//  §15.5: File ▸ Print… on the page in front, Download PDF, and the toast a
//  slow PDF brings down. Nothing here prints: `PagePrinting.run` is replaced
//  for every test that reaches it.
//

import AppKit
import BrowserKit
import XCTest
@testable import Luna

@MainActor
final class PrintAndPDFTests: XCTestCase {

    private let directory = URL.temporaryDirectory.appending(path: "luna-tests-\(UUID().uuidString)")
    private var runner: ((NSPrintOperation, NSWindow) -> Void)?
    private var window: NSWindow?

    override func setUp() async throws {
        runner = PagePrinting.run
    }

    override func tearDown() async throws {
        if let runner { PagePrinting.run = runner }
        window?.close()
        window = nil
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - The command

    /// Every Mac's ⌘P, last in File, and not already somebody else's — the
    /// table-wide sweep in `ShortcutBindingsTests` is what proves the last.
    func testPrintShipsCommandPAtTheFootOfFile() throws {
        XCTAssertEqual(BrowserCommand.printPage.defaults, [KeyBinding("p")])
        XCTAssertNil(KeyBindings.conflict(for: KeyBinding("p"), ignoring: .printPage))
        let file = try XCTUnwrap(NSApp.mainMenu?.items.first { $0.submenu?.title == "File" }?.submenu)
        XCTAssertEqual(file.items.suffix(2).map(\.title), ["Download PDF", "Print…"])
    }

    func testNothingPrintsWithoutALivePage() async throws {
        var ran = 0
        PagePrinting.run = { _, _ in ran += 1 }
        let session = try await makeSession()
        try tab(in: session)

        XCTAssertFalse(session.canPrint)
        session.printActivePage()
        XCTAssertEqual(ran, 0)
    }

    /// WebKit's own operation, titled for the page and sheeted on its window.
    func testPrintHandsWebKitsOperationToTheWindow() async throws {
        var printed: (NSPrintOperation, NSWindow)?
        PagePrinting.run = { printed = ($0, $1) }
        let session = try await makeSession()
        let id = try tab(in: session)
        session.activateTab(id)
        let webView = try XCTUnwrap(session.controller(for: id)?.webView)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled],
                              backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.contentView?.addSubview(webView)
        self.window = window

        XCTAssertTrue(session.canPrint)
        session.printActivePage()

        let (operation, host) = try XCTUnwrap(printed)
        XCTAssertTrue(host === window)
        XCTAssertEqual(operation.jobTitle, session.activeTitle)
        XCTAssertTrue(operation.showsPrintPanel)
    }

    /// Download PDF dims on anything that is not a PDF in the viewer.
    func testDownloadPDFIsOnlyForAPDF() async throws {
        let session = try await makeSession()
        let id = try tab(in: session)
        session.activateTab(id)
        XCTAssertFalse(session.canDownloadActivePDF)
    }

    // MARK: - The toast

    func testASlowPDFSaysItsSizeAndOffersDownloads() {
        var pressed = 0
        let pdf = PDFArrival(url: URL(string: "https://books.example/atlas.pdf")!, expectedLength: 48_000_000)
        let toast = PageToast.openingPDF(pdf) { pressed += 1 }

        XCTAssertEqual(toast.text, "Opening a 48 MB PDF")
        XCTAssertEqual(toast.detail, "atlas.pdf")
        XCTAssertEqual(toast.actions.map(\.title), ["Download"])
        XCTAssertEqual(toast.dwell, Tokens.Motion.toastActionDwell, "an offer gets the time to reach it")
        toast.actions.first?.run()
        XCTAssertEqual(pressed, 1)
    }

    /// No length from the server, and an address with no file name in it.
    func testAPDFOfUnknownSizeSaysItIsStillLoading() {
        let pdf = PDFArrival(url: URL(string: "https://books.example/")!, expectedLength: nil)
        let toast = PageToast.openingPDF(pdf) {}
        XCTAssertEqual(toast.text, "This PDF is still loading")
        XCTAssertEqual(toast.detail, "books.example")
    }

    // MARK: - Helpers

    @discardableResult
    private func tab(in session: BrowserSession) throws -> UUID {
        let space = try XCTUnwrap(session.spaces.first)
        let tab = Tab(spaceID: space.id, kind: .today, url: URL(string: "https://example.invalid/page")!)
        session.persistAll(session.list.insert(tab, at: TabList.openIndex(for: .today)))
        return tab.id
    }

    private func makeSession() async throws -> BrowserSession {
        try await BrowserSession.restored(store: BrowserStore(path: directory.appending(path: "luna.sqlite")))
    }
}
