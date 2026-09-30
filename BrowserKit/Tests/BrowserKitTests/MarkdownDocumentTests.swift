@testable import BrowserKit
import Foundation
import Testing

@Suite("Markdown document")
struct MarkdownDocumentTests {

    @Test(arguments: [
        ("file:///r/README.md", nil, true),
        ("file:///r/notes.markdown", nil, true),
        ("file:///r/a.mdown", nil, true),
        ("file:///r/a.mkd", nil, true),
        ("file:///r/A.MD", nil, true),
        ("file:///r/a.txt", nil, false),
        ("file:///r/a.html", "text/html", false),
        ("https://x.example/README.md", "text/markdown", true),
        ("https://x.example/raw", "text/markdown; charset=utf-8", true),
        ("https://x.example/raw", "text/x-markdown", true),
        ("https://x.example/README.md", "text/plain", true),
        ("https://x.example/README.md?raw=1", "text/plain; charset=utf-8", true),
        ("https://x.example/notes.txt", "text/plain", false),
        ("https://x.example/README.md", "text/html", false),
        ("https://x.example/README.md", nil, false)
    ] as [(String, String?, Bool)])
    func isMarkdownTruthTable(_ row: (String, String?, Bool)) throws {
        let url = try #require(URL(string: row.0))
        #expect(MarkdownDocument.isMarkdown(url: url, mimeType: row.1) == row.2, "\(row.0) \(row.1 ?? "nil")")
    }

    @Test func utf8WithCRLFIsEditable() {
        let date = Date(timeIntervalSince1970: 1_000)
        let url = URL(fileURLWithPath: "/r/a.md")
        let document = MarkdownDocument(url: url, data: Data("# A\r\nb\r\n".utf8), modificationDate: date)
        #expect(document.text == "# A\r\nb\r\n")
        #expect(document.lineEnding == .crlf)
        #expect(!document.isReadOnly)
        #expect(document.modificationDate == date)
        #expect(document.url == url)
    }

    @Test func lfIsDetected() {
        let document = MarkdownDocument(url: URL(fileURLWithPath: "/a.md"), data: Data("a\nb\r\n".utf8), modificationDate: nil)
        #expect(document.lineEnding == .lf)
    }

    @Test func notUTF8OpensReadOnly() {
        let latin1 = Data([0x63, 0x61, 0x66, 0xE9]) // "café" in Latin-1
        let document = MarkdownDocument(url: URL(fileURLWithPath: "/a.md"), data: latin1, modificationDate: nil)
        #expect(document.isReadOnly)
        #expect(document.text == "café")
    }

    @Test func readsFromDisk() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).md")
        try Data("# Hi\n".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let document = try MarkdownDocument.read(from: url)
        #expect(document.text == "# Hi\n")
        #expect(document.modificationDate != nil)
    }
}
