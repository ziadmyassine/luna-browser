import Foundation

/// Pictures beside a Markdown file on this Mac, written into its page as
/// `data:` URLs.
///
/// The page is a simulated load under the file's own URL, which is what gives
/// it a history entry, and a simulated load carries no read access to the
/// file's folder: `![dot](dot.png)` beside a README loaded nothing. Inlined,
/// the picture needs no access at all. The reach is the one `loadFileURL`
/// grants a file opened directly — its folder and below — and the formats are
/// the ones `MarkdownHTML.safeDestination` already lets through as `data:`.
@MainActor
enum MarkdownLocalImages {

    /// Larger pictures keep their path and do not load, rather than putting
    /// megabytes of base64 through every keystroke of the editor's preview.
    static let sizeLimit = 8 * 1024 * 1024

    private static let types = [
        "png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg", "gif": "image/gif", "webp": "image/webp"
    ]

    /// Read once per file and change: the editor renders on every edit.
    private static var inlined: [URL: (modified: Date, source: String)] = [:]

    /// Nil for a document that is not a local file, whose pictures load over
    /// the network as they are.
    static func resolver(for document: URL) -> ((String) -> String?)? {
        guard document.isFileURL else { return nil }
        let folder = document.deletingLastPathComponent().resolvingSymlinksInPath()
        return { source in MainActor.assumeIsolated { inline(source, in: folder) } }
    }

    /// A relative `source` inside `folder` as a `data:` URL, or nil to leave it.
    static func inline(_ source: String, in folder: URL) -> String? {
        guard !source.contains(":"), !source.hasPrefix("/"),
              let path = source.split(separator: "#").first?.split(separator: "?").first,
              let decoded = String(path).removingPercentEncoding
        else { return nil }
        let file = URL(fileURLWithPath: decoded, relativeTo: folder).resolvingSymlinksInPath()
        let root = folder.path.hasSuffix("/") ? folder.path : folder.path + "/"
        guard file.path.hasPrefix(root), let type = types[file.pathExtension.lowercased()],
              let values = try? file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
              let size = values.fileSize, size <= sizeLimit,
              let modified = values.contentModificationDate
        else { return nil }
        if let known = inlined[file], known.modified == modified { return known.source }
        guard let data = try? Data(contentsOf: file) else { return nil }
        let inline = "data:\(type);base64,\(data.base64EncodedString())"
        if inlined.count >= 64 { inlined.removeAll() }
        inlined[file] = (modified, inline)
        return inline
    }
}
