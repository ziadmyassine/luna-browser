import Foundation
import UniformTypeIdentifiers

/// A Markdown file as read from disk: its text and what saving it back has to
/// preserve.
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
        return MarkdownDocument(url: url, data: data, modificationDate: modificationDate(of: url))
    }

    public enum SaveError: Error { case changedOnDisk, notEditable }

    /// Whether Edit is offered: a file on this Mac whose bytes were UTF-8.
    public var isEditable: Bool { url.isFileURL && !isReadOnly }

    /// `text` as a `<textarea>` hands it back, which is with `\n` line endings.
    public var editorText: String { text.replacingOccurrences(of: "\r\n", with: "\n") }

    /// Writes `text` over this document's own file, and nowhere else, with the
    /// line endings the file had. Throws `changedOnDisk` rather than writing
    /// when the file's date is no longer the one it was read with, unless
    /// `overwritingChanges` says the user chose to.
    public func save(_ text: String, overwritingChanges: Bool = false) throws -> MarkdownDocument {
        guard isEditable else { throw SaveError.notEditable }
        let lf = text.replacingOccurrences(of: "\r\n", with: "\n")
        let data = Data((lineEnding == .crlf ? lf.replacingOccurrences(of: "\n", with: "\r\n") : lf).utf8)
        var coordination: NSError?
        var failure: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordination) { target in
            do {
                if !overwritingChanges, Self.modificationDate(of: target) != modificationDate {
                    throw SaveError.changedOnDisk
                }
                try data.write(to: target, options: .atomic)
            } catch {
                failure = error
            }
        }
        if let error = failure ?? coordination { throw error }
        return MarkdownDocument(url: url, data: data, modificationDate: Self.modificationDate(of: url))
    }

    /// From the file system each time: `URL.resourceValues` caches on the URL,
    /// and a cached date would hide the very change it is compared to find.
    static func modificationDate(of url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
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
