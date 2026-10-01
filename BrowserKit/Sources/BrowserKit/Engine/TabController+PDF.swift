//
//  TabController+PDF.swift
//  BrowserKit
//
//  §15.5: a PDF opens in the tab, in WebKit's own viewer, and stays there.
//  What this adds is the way out of it — the same file in Downloads — and a
//  word for the big one, which the viewer shows nothing of until the last
//  byte has arrived: a 200 MB book over a slow line was a tab that looked
//  broken for minutes.
//
//  WebKit says nothing public about what a frame is showing, so the response
//  is the record: its MIME type at `decidePolicyFor`, made the document's at
//  `didCommit`. A script cannot ask either — the viewer is a plugin document
//  and `evaluateJavaScript` fails in it.
//

import WebKit

/// A PDF the main frame is receiving.
public struct PDFArrival: Sendable, Equatable {
    public let url: URL
    /// What the server said it would send, or nil when it did not say.
    public let expectedLength: Int64?

    public init(url: URL, expectedLength: Int64?) {
        self.url = url
        self.expectedLength = expectedLength
    }
}

/// The pure half: which responses are PDFs, and which of them to say something about.
enum PDFPolicy {

    /// WebKit's own list (`MIMETypeRegistry::pdfMIMETypes`).
    static func isPDF(mimeType: String?) -> Bool {
        guard let type = mimeType?.lowercased() else { return false }
        return type == "application/pdf" || type == "text/pdf"
    }

    /// Past this the wait is long enough to offer Downloads instead: about
    /// eight seconds at 10 Mbit/s, the speed a hotel line or a tethered phone gives.
    static let largeLength: Int64 = 10 << 20

    /// How long a PDF of unknown size may load before it gets the same offer.
    /// A generated invoice is sent without a length and arrives in well under this.
    static let patience: Duration = .seconds(3)

    enum Notice: Equatable {
        case none
        /// Large by its own account, so said as it starts.
        case now
        /// Said only if it is still arriving once `patience` is up.
        case ifStillLoading
    }

    /// A file on this Mac is read, not downloaded, and never needs the offer.
    static func notice(for url: URL, expectedLength: Int64?) -> Notice {
        guard !url.isFileURL else { return .none }
        guard let expectedLength else { return .ifStillLoading }
        return expectedLength >= largeLength ? .now : .none
    }

    /// `NSURLResponseUnknownLength` is -1; a server may send 0 for "not saying" too.
    static func length(_ expected: Int64) -> Int64? {
        expected > 0 ? expected : nil
    }
}

extension TabController {

    /// The tab is showing a PDF from somewhere other than this Mac, which Downloads
    /// can take a copy of.
    public var canDownloadPDF: Bool {
        guard state.isPDF, let url = webView?.url else { return false }
        return !url.isFileURL
    }

    /// The PDF on screen, to Downloads. The data store is the tab's own, so the
    /// request carries the cookies that let the page show it.
    public func downloadPDF() {
        guard canDownloadPDF, let url = webView?.url else { return }
        startDownload(of: url)
    }

    /// The offer `tabController(_:isSlowToOpen:)` puts to the user: stop waiting
    /// for the viewer and fetch the file into Downloads. Started again from the
    /// first byte — WebKit cannot hand a load it has accepted over to a download.
    ///
    /// Once the viewer has committed, the tab goes back to the page the link was
    /// on rather than being left on an empty viewer. If the PDF finished first,
    /// this is a plain download of it.
    public func downloadArrivingPDFInstead() {
        guard let webView, let pdf = arrivingPDF else { return downloadPDF() }
        let committed = state.isPDF
        forgetArrivingPDF()
        webView.stopLoading()
        startDownload(of: pdf.url)
        if committed, webView.canGoBack { webView.goBack() }
    }

    private func startDownload(of url: URL) {
        webView?.startDownload(using: URLRequest(url: url)) { [weak self] download in
            guard let self else { return download.cancel() }
            self.delegate?.tabController(self, didStartDownload: download)
        }
    }

    // MARK: - From the navigation delegate

    /// Every main-frame response the tab is about to show. Anything but a PDF
    /// clears what an earlier one left.
    func noteMainFrameResponse(_ response: URLResponse) {
        forgetArrivingPDF()
        guard PDFPolicy.isPDF(mimeType: response.mimeType), let url = response.url else { return }
        let pdf = PDFArrival(url: url, expectedLength: PDFPolicy.length(response.expectedContentLength))
        arrivingPDF = pdf
        switch PDFPolicy.notice(for: url, expectedLength: pdf.expectedLength) {
        case .none:
            break
        case .now:
            delegate?.tabController(self, isSlowToOpen: pdf)
        case .ifStillLoading:
            pdfPatience = Task { [weak self] in
                try? await Task.sleep(for: PDFPolicy.patience)
                guard let self, !Task.isCancelled, self.arrivingPDF == pdf, self.webView?.isLoading == true else { return }
                self.delegate?.tabController(self, isSlowToOpen: pdf)
            }
        }
    }

    /// The document that just committed is the PDF the response announced.
    func commitArrivingPDF() {
        showsPDF = arrivingPDF != nil
    }

    /// The load ended, one way or the other.
    func forgetArrivingPDF() {
        pdfPatience?.cancel()
        pdfPatience = nil
        arrivingPDF = nil
    }
}
