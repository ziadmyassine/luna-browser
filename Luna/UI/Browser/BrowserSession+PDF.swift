//
//  BrowserSession+PDF.swift
//  Luna
//
//  §15.5 at the window: File ▸ Print… for whatever the tab in front shows,
//  Download PDF for a PDF in the viewer, and the toast that offers Downloads
//  when a PDF will be a while. Which responses are PDFs, and when one counts
//  as slow, is `TabController+PDF.swift`'s.
//

import AppKit
import BrowserKit
import WebKit

/// How a print operation is run. Replaced in tests: nothing under test may put
/// a print panel up, let alone reach a printer.
@MainActor
enum PagePrinting {

    static var run: (NSPrintOperation, NSWindow) -> Void = { operation, window in
        // Sheeted, never `run()`: WebKit draws the pages from the web content
        // process, and a blocking `run()` on WebKit's operation did not return
        // in 40 s, for a PDF or an HTML page (measured, macOS 26).
        operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
    }

    /// WebKit's own operation for the page. A PDF in the viewer prints as the
    /// document's own pages, not a picture of the viewer: a three-page PDF
    /// saved through this came back three pages with its text still text.
    static func operation(for webView: WKWebView, title: String) -> NSPrintOperation {
        let info = (NSPrintInfo.shared.copy() as? NSPrintInfo) ?? NSPrintInfo()
        info.isHorizontallyCentered = true
        info.isVerticallyCentered = false
        let operation = webView.printOperation(with: info)
        operation.jobTitle = title
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        operation.printPanel.options.formUnion([.showsPaperSize, .showsOrientation, .showsScaling, .showsPreview])
        return operation
    }
}

extension BrowserSession {

    // MARK: - Print

    /// A page has to be live to be printed; a cold tab has nothing drawn yet.
    var canPrint: Bool { activeController?.webView?.window != nil }

    func printActivePage() {
        guard let webView = activeController?.webView, let window = webView.window else { return }
        PagePrinting.run(PagePrinting.operation(for: webView, title: activeTitle), window)
    }

    // MARK: - Download PDF

    var canDownloadActivePDF: Bool { activeController?.canDownloadPDF ?? false }

    func downloadActivePDF() {
        activeController?.downloadPDF()
    }

    /// The tab in front only. A PDF arriving in a tab nobody is looking at
    /// is ready by the time they get there, or still loading with its
    /// progress line saying so.
    func tabController(_ controller: TabController, isSlowToOpen pdf: PDFArrival) {
        guard controller.id == activeTabID else { return }
        PageToast.openingPDF(pdf) { [weak controller] in
            controller?.downloadArrivingPDFInstead()
        }.show(in: hostWindow)
    }
}
