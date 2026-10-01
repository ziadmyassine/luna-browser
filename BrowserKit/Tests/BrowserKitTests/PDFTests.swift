import CoreGraphics
import Foundation
import Testing
import WebKit
@testable import BrowserKit

/// §15.5: which responses are PDFs, which of them are slow enough to offer
/// Downloads for, and the tab knowing it is showing one.
@Suite("PDFs (§15.5)")
@MainActor
struct PDFTests {

    @MainActor private final class Recorder: TabControllerDelegate {
        var slow: [PDFArrival] = []
        var downloads: [WKDownload] = []
        func tabController(_ controller: TabController, didChange state: TabState) {}
        func tabController(
            _ controller: TabController,
            wantsNewTabFor url: URL?,
            configuration: WKWebViewConfiguration
        ) -> WKWebView? { nil }
        func tabController(_ controller: TabController, didStartDownload download: WKDownload) {
            downloads.append(download)
            download.cancel()
        }
        func tabController(_ controller: TabController, didFailWith error: Error) {}
        func tabController(_ controller: TabController, isSlowToOpen pdf: PDFArrival) { slow.append(pdf) }
    }

    private let book = URL(string: "https://books.invalid/atlas.pdf")!

    private func response(_ url: URL, _ type: String, length: Int) -> URLResponse {
        URLResponse(url: url, mimeType: type, expectedContentLength: length, textEncodingName: nil)
    }

    // MARK: - The policy

    @Test func knowsWebKitsPDFTypes() {
        #expect(PDFPolicy.isPDF(mimeType: "application/pdf"))
        #expect(PDFPolicy.isPDF(mimeType: "Application/PDF"))
        #expect(PDFPolicy.isPDF(mimeType: "text/pdf"))
        #expect(!PDFPolicy.isPDF(mimeType: "text/html"))
        #expect(!PDFPolicy.isPDF(mimeType: nil))
    }

    @Test func aLargePDFIsSaidAtOnceAndASmallOneNever() {
        #expect(PDFPolicy.notice(for: book, expectedLength: 48 << 20) == .now)
        #expect(PDFPolicy.notice(for: book, expectedLength: PDFPolicy.largeLength) == .now)
        #expect(PDFPolicy.notice(for: book, expectedLength: 900_000) == PDFPolicy.Notice.none)
    }

    /// A server that does not say how much is coming might be sending a page
    /// or a book; only the wait tells.
    @Test func aPDFOfUnknownSizeWaitsToBeSlow() {
        #expect(PDFPolicy.notice(for: book, expectedLength: nil) == .ifStillLoading)
        #expect(PDFPolicy.length(-1) == nil)
        #expect(PDFPolicy.length(0) == nil)
        #expect(PDFPolicy.length(12) == 12)
    }

    @Test func aFileOnThisMacIsNeverSlow() {
        let file = URL(fileURLWithPath: "/tmp/atlas.pdf")
        #expect(PDFPolicy.notice(for: file, expectedLength: 400 << 20) == PDFPolicy.Notice.none)
        #expect(PDFPolicy.notice(for: file, expectedLength: nil) == PDFPolicy.Notice.none)
    }

    // MARK: - The tab

    @Test func aLargePDFResponseTellsTheHost() {
        let recorder = Recorder()
        let controller = TabController(id: UUID(), dataStore: .nonPersistent())
        controller.delegate = recorder
        controller.noteMainFrameResponse(response(book, "application/pdf", length: 48 << 20))
        #expect(recorder.slow == [PDFArrival(url: book, expectedLength: 48 << 20)])

        controller.noteMainFrameResponse(response(book, "application/pdf", length: 2 << 20))
        controller.noteMainFrameResponse(response(book, "text/html", length: 48 << 20))
        #expect(recorder.slow.count == 1, "a small PDF or a big page was called slow")
    }

    /// The patience runs out on a load that has already finished: nothing to say.
    @Test func anUnknownSizePDFThatFinishedIsNotCalledSlow() async throws {
        let recorder = Recorder()
        let controller = TabController(id: UUID(), dataStore: .nonPersistent())
        controller.delegate = recorder
        controller.activate()
        controller.noteMainFrameResponse(response(book, "application/pdf", length: -1))
        try await Task.sleep(for: PDFPolicy.patience + .milliseconds(300))
        #expect(recorder.slow.isEmpty)
    }

    /// The toast's Download: the same address, through the tab's own web view
    /// and so its own cookies, handed to the host's downloads.
    @Test func downloadingInsteadFetchesTheSameAddress() async throws {
        let recorder = Recorder()
        let controller = TabController(id: UUID(), dataStore: .nonPersistent())
        controller.delegate = recorder
        controller.activate()
        controller.noteMainFrameResponse(response(book, "application/pdf", length: 48 << 20))

        controller.downloadArrivingPDFInstead()
        for _ in 0..<50 where recorder.downloads.isEmpty { try await Task.sleep(for: .milliseconds(100)) }

        #expect(recorder.downloads.first?.originalRequest?.url == book)
        #expect(controller.arrivingPDF == nil)
    }

    /// WebKit's viewer, recognised from the response: the state says PDF while
    /// it is up and stops saying so on the next page. A file on this Mac is
    /// not offered to Downloads.
    @Test func theTabKnowsItIsShowingAPDF() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "luna-pdf-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let pdf = folder.appending(path: "one.pdf")
        var box = CGRect(x: 0, y: 0, width: 200, height: 200)
        let context = try #require(CGContext(pdf as CFURL, mediaBox: &box, nil))
        context.beginPDFPage(nil)
        context.endPDFPage()
        context.closePDF()
        let page = folder.appending(path: "two.html")
        try "<p>two</p>".write(to: page, atomically: true, encoding: .utf8)

        let controller = TabController(id: UUID(), dataStore: .nonPersistent())
        controller.activate()
        controller.load(pdf)
        try await settle(controller) { $0.isPDF }
        #expect(controller.state.isPDF)
        #expect(!controller.canDownloadPDF, "a file already on this Mac was offered to Downloads")

        controller.load(page)
        try await settle(controller) { !$0.isPDF && $0.url == page }
        #expect(!controller.state.isPDF)
    }

    private func settle(_ controller: TabController, until done: (TabState) -> Bool) async throws {
        for _ in 0..<100 {
            if done(controller.state), !controller.state.isLoading { return }
            try await Task.sleep(for: .milliseconds(100))
        }
    }
}
