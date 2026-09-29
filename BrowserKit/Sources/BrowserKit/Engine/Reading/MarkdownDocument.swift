import Foundation
import UniformTypeIdentifiers

/// A Markdown file as read from disk: its text and what saving it back has to
/// preserve. Saving itself is Phase 6 of docs/READING-PLAN.md.
public struct MarkdownDocument: Sendable, Equatable {

    public enum LineEnding: Sendable { case lf, crlf }

    public let url: URL
    public let text: String
    /// True when the bytes were not UTF-8: the text shown is a Latin-1 reading
    /// of them, and writing that back would re-encode the file.
    public let isReadOnly: Bool
    public let lineEnding: LineEnding
    /// Compared with the file's date at save time, so a change made on disk
    /// in the meantime is never overwritten silently.
    public let modificationDate: Date?

    public init(url: URL, data: Data, modificationDate: Date?) {
        self.url = url
        self.modificationDate = modificationDate
        if let text = String(data: data, encoding: .utf8) {
            self.text = text
            isReadOnly = false
        } else {
            // Latin-1 maps every byte, so this never fails.
            text = String(data: data, encoding: .isoLatin1) ?? ""
            isReadOnly = true
        }
        // The first line ending decides: a file mixing both is saved as it began.
        let bytes = Array(data)
        let crlf = bytes.firstIndex(of: 0x0A).map { $0 > 0 && bytes[$0 - 1] == 0x0D } ?? false
        lineEnding = crlf ? .crlf : .lf
    }

    public static func read(from url: URL) throws -> MarkdownDocument {
        let data = try Data(contentsOf: url)
        let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        return MarkdownDocument(url: url, data: data, modificationDate: date)
    }

    static let pathExtensions: Set<String> = ["md", "markdown", "mdown", "mkd"]
    private static let markdownType = UTType("net.daringfireball.markdown")

    /// Whether a response is a Markdown document Luna renders rather than shows
    /// as raw text. A web server's `text/plain` counts only with a Markdown path,
    /// since that is how raw.githubusercontent.com and most static hosts serve it.
    public static func isMarkdown(url: URL, mimeType: String?) -> Bool {
        let ext = url.pathExtension.lowercased()
        let hasMarkdownExtension = pathExtensions.contains(ext)
        if url.isFileURL {
            if hasMarkdownExtension { return true }
            if let markdownType, let type = UTType(filenameExtension: ext), type.conforms(to: markdownType) { return true }
        }
        let mime = mimeType?.split(separator: ";").first?.trimmingCharacters(in: .whitespaces).lowercased()
        switch mime {
        case "text/markdown", "text/x-markdown": return true
        case "text/plain": return hasMarkdownExtension
        default: return false
        }
    }
}
