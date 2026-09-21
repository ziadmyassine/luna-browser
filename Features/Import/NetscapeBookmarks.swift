//
//  NetscapeBookmarks.swift
//  Luna — §23.2 (generic import) and §23.4 (export)
//
//  The Netscape bookmarks HTML format: every browser exports it and every
//  browser reads it. It is the only route to Safari's bookmarks without Full
//  Disk Access (§23.2 asks for the exported file first), and half of §23.4's
//  backup and export.
//
//  The format, as every browser writes it:
//
//      <!DOCTYPE NETSCAPE-Bookmark-file-1>
//      <DL><p>
//          <DT><H3 PERSONAL_TOOLBAR_FOLDER="true">Bookmarks Bar</H3>
//          <DL><p>
//              <DT><A HREF="https://…" ADD_DATE="1756588800">Title</A>
//          </DL><p>
//      </DL><p>
//
//  `ADD_DATE` here is seconds since the Unix epoch — not Chromium's
//  microseconds since 1601. Different file, different epoch.
//
//  The toolbar folder is transparent: it is the bar itself, so its direct URLs
//  are Favorites and its subfolders top-level folders — the same rule
//  `ChromiumReader.flatten` applies to `roots.bookmark_bar`, which is what makes
//  write-then-read a round trip.
//

import Foundation

enum NetscapeBookmarks {

    // MARK: - Parse

    /// Parses a bookmarks HTML file.
    ///
    /// Tag-scanning rather than HTML parsing on purpose: these files are
    /// hand-rolled by every browser, are frequently not well-formed, and the
    /// only structure that matters is `DL` nesting plus `H3`/`A` elements.
    /// A malformed document yields fewer bookmarks, never an error — the
    /// caller decides what "zero bookmarks" means.
    static func parse(_ html: String) -> [ImportedBookmark] {
        let pattern = #"<dl\b|</dl\s*>|<h3\b([^>]*)>(.*?)</h3\s*>|<a\b([^>]*)>(.*?)</a\s*>"#
        guard
            let regex = try? NSRegularExpression(
                pattern: pattern,
                options: [.caseInsensitive, .dotMatchesLineSeparators]
            )
        else { return [] }

        /// One open `<DL>`. `name` is `nil` for the document root and for the
        /// transparent toolbar folder, so `compactMap` gives the real path.
        struct Frame { var name: String? }

        var stack: [Frame] = []
        var pendingFolder: Frame?
        var bookmarks: [ImportedBookmark] = []
        let text = html as NSString
        let whole = NSRange(location: 0, length: text.length)

        regex.enumerateMatches(in: html, range: whole) { match, _, _ in
            guard let match else { return }
            let token = text.substring(with: match.range).lowercased()

            if token.hasPrefix("</dl") {
                if !stack.isEmpty { stack.removeLast() }
                return
            }
            if token.hasPrefix("<dl") {
                stack.append(pendingFolder ?? Frame(name: nil))
                pendingFolder = nil
                return
            }
            if token.hasPrefix("<h3") {
                let attributes = group(match, 1, in: text)
                let name = decodeEntities(group(match, 2, in: text)).trimmingCharacters(in: .whitespacesAndNewlines)
                // The bar is not a folder the user made; it is the bar.
                let isToolbar = attribute("personal_toolbar_folder", in: attributes)?.lowercased() == "true"
                pendingFolder = Frame(name: isToolbar || name.isEmpty ? nil : name)
                return
            }

            if let bookmark = bookmark(from: match, in: text, path: stack.compactMap(\.name)) {
                bookmarks.append(bookmark)
            }
        }
        return bookmarks
    }

    /// The `<A …>…</A>` half of the scan. An anchor with no usable `HREF` is
    /// skipped rather than reported: these files routinely carry `place:` rows,
    /// `javascript:` bookmarklets and empty separators.
    private static func bookmark(
        from match: NSTextCheckingResult,
        in text: NSString,
        path: [String]
    ) -> ImportedBookmark? {
        let attributes = group(match, 3, in: text)
        guard
            let href = attribute("href", in: attributes),
            let url = URL(string: href.trimmingCharacters(in: .whitespaces)),
            url.scheme != nil
        else { return nil }
        let title = decodeEntities(group(match, 4, in: text)).trimmingCharacters(in: .whitespacesAndNewlines)
        return ImportedBookmark(
            url: url,
            title: title.isEmpty ? (url.host() ?? href) : title,
            // `ADD_DATE` is whole seconds since 1970 in this format — not
            // Chromium's microseconds since 1601.
            dateAdded: attribute("add_date", in: attributes)
                .flatMap { TimeInterval($0) }
                .map { Date(timeIntervalSince1970: $0) },
            folderPath: path,
            placement: path.isEmpty ? .favorite : .folder
        )
    }

    // MARK: - Write

    /// Serialises bookmarks back to the same format.
    ///
    /// Round-trip invariant, which the tests pin:
    /// `parse(write(x)) == x` for any `x` where a bookmark is `.favorite`
    /// exactly when its `folderPath` is empty — which is what every reader in
    /// this feature produces. An input that breaks that invariant is
    /// normalised into a folder named "Bookmarks" rather than silently
    /// changing placement.
    static func write(_ bookmarks: [ImportedBookmark], title: String = "Bookmarks") -> String {
        let normalised = bookmarks.map { bookmark -> ImportedBookmark in
            guard bookmark.placement == .folder, bookmark.folderPath.isEmpty else { return bookmark }
            var copy = bookmark
            copy.folderPath = ["Bookmarks"]
            return copy
        }

        var root = Folder(name: "")
        for bookmark in normalised {
            root.insert(bookmark, at: bookmark.folderPath[...])
        }

        var out = """
        <!DOCTYPE NETSCAPE-Bookmark-file-1>
        <!-- This is an automatically generated file. It will be read and overwritten. -->
        <META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">
        <TITLE>\(escape(title))</TITLE>
        <H1>\(escape(title))</H1>
        <DL><p>
            <DT><H3 PERSONAL_TOOLBAR_FOLDER="true">Bookmarks Bar</H3>
            <DL><p>

        """
        // Favorites and every folder live inside the toolbar folder, which is
        // transparent on the way back in — so the paths survive the round trip
        // and another browser still sees a populated bookmarks bar.
        out += body(of: root, indent: 3)
        out += """
            </DL><p>
        </DL><p>

        """
        return out
    }

    /// A folder tree, assembled from the flat list's `folderPath`s.
    private struct Folder {
        var name: String
        var bookmarks: [ImportedBookmark] = []
        var children: [Folder] = []

        mutating func insert(_ bookmark: ImportedBookmark, at path: ArraySlice<String>) {
            guard let next = path.first else {
                bookmarks.append(bookmark)
                return
            }
            if let index = children.firstIndex(where: { $0.name == next }) {
                children[index].insert(bookmark, at: path.dropFirst())
            } else {
                var child = Folder(name: next)
                child.insert(bookmark, at: path.dropFirst())
                children.append(child)
            }
        }
    }

    private static func body(of folder: Folder, indent: Int) -> String {
        let pad = String(repeating: "    ", count: indent)
        var out = ""
        for bookmark in folder.bookmarks {
            let date = bookmark.dateAdded.map { " ADD_DATE=\"\(Int($0.timeIntervalSince1970))\"" } ?? ""
            out += "\(pad)<DT><A HREF=\"\(escape(bookmark.url.absoluteString))\"\(date)>\(escape(bookmark.title))</A>\n"
        }
        for child in folder.children {
            out += "\(pad)<DT><H3>\(escape(child.name))</H3>\n"
            out += "\(pad)<DL><p>\n"
            out += body(of: child, indent: indent + 1)
            out += "\(pad)</DL><p>\n"
        }
        return out
    }

    // MARK: - Text

    private static func group(_ match: NSTextCheckingResult, _ index: Int, in text: NSString) -> String {
        let range = match.range(at: index)
        return range.location == NSNotFound ? "" : text.substring(with: range)
    }

    /// Pulls one double- or single-quoted attribute out of a tag's attribute
    /// text. Case-insensitive because these files are written by hand as often
    /// as by a browser.
    private static func attribute(_ name: String, in attributes: String) -> String? {
        let pattern = "\(NSRegularExpression.escapedPattern(for: name))\\s*=\\s*[\"']([^\"']*)[\"']"
        guard
            let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
            let match = regex.firstMatch(in: attributes, range: NSRange(attributes.startIndex..., in: attributes)),
            let range = Range(match.range(at: 1), in: attributes)
        else { return nil }
        return String(attributes[range])
    }

    /// The five entities these files actually contain. `&amp;` is decoded last
    /// on the way in and encoded first on the way out, or `&amp;lt;` breaks.
    private static let entities = [("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'")]

    static func escape(_ string: String) -> String {
        var out = string.replacingOccurrences(of: "&", with: "&amp;")
        for (entity, character) in entities {
            out = out.replacingOccurrences(of: character, with: entity)
        }
        return out
    }

    static func decodeEntities(_ string: String) -> String {
        var out = string
        for (entity, character) in entities {
            out = out.replacingOccurrences(of: entity, with: character)
        }
        return out.replacingOccurrences(of: "&amp;", with: "&")
    }
}
