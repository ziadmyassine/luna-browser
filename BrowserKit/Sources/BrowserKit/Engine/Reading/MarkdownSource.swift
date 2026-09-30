import Foundation

/// The Source view: the file's own text, one `<div class="src-line">` per line
/// so CSS can number and wrap rows, with Markdown's syntax in
/// `<span class="md-mark">` so it can be dimmed behind the words.
///
/// A line scanner, not a parse: what the reader wants dimmed is the characters
/// on the line, and a parse tree's ranges would only point back at them.
public enum MarkdownSource {

    public static func html(_ text: String) -> String {
        var lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        if lines.count > 1, lines.last?.isEmpty == true { lines.removeLast() }
        let tableRows = tableLines(lines)
        var out = ""
        out.reserveCapacity(text.utf8.count * 2)
        var fence: (marker: String, language: String?, body: [String])?
        for (number, line) in lines.enumerated() {
            if var open = fence {
                if isClosingFence(line, marker: open.marker) {
                    out += codeRows(open.body, language: open.language) + row(mark(line))
                    fence = nil
                } else {
                    open.body.append(line)
                    fence = open
                }
            } else if let opening = openingFence(line) {
                fence = (opening.marker, opening.language, [])
                out += row(mark(line))
            } else {
                out += row(markLine(line, inTable: tableRows.contains(number)))
            }
        }
        if let open = fence {
            // An unclosed fence runs to the end of the file, as it does when rendered.
            out += codeRows(open.body, language: open.language)
        }
        return out
    }

    /// Highlighted as one block, so a comment or string spanning lines is
    /// coloured on all of them; the highlighter never lets a span cross a line.
    private static func codeRows(_ body: [String], language: String?) -> String {
        guard !body.isEmpty else { return "" }
        return SyntaxHighlighter.html(body.joined(separator: "\n"), language: language)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { row($0) }
            .joined()
    }

    private static func row(_ html: some StringProtocol) -> String { "<div class=\"src-line\">\(html)</div>" }

    private static func mark(_ text: some StringProtocol) -> String {
        "<span class=\"md-mark\">\(HTML.escape(String(text)))</span>"
    }

    // MARK: Fences

    private static func openingFence(_ line: String) -> (marker: String, language: String?)? {
        let trimmed = line.drop { $0 == " " }
        guard line.count - trimmed.count <= 3, let first = trimmed.first, first == "`" || first == "~" else { return nil }
        let marker = trimmed.prefix { $0 == first }
        guard marker.count >= 3 else { return nil }
        let info = trimmed.dropFirst(marker.count).trimmingCharacters(in: .whitespaces)
        if first == "`", info.contains("`") { return nil }
        return (String(marker), info.split(separator: " ").first.map(String.init))
    }

    private static func isClosingFence(_ line: String, marker: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let first = marker.first, trimmed.count >= marker.count else { return false }
        return trimmed.allSatisfy { $0 == first }
    }

    // MARK: Lines

    /// Rows of a GFM table: the header, its delimiter row and the rows up to
    /// the next blank line.
    private static func tableLines(_ lines: [String]) -> Set<Int> {
        var rows = Set<Int>()
        for (number, line) in lines.enumerated() where number > 0 && isDelimiterRow(line) && lines[number - 1].contains("|") {
            rows.insert(number - 1)
            var cursor = number
            while cursor < lines.count, lines[cursor].contains("|") {
                rows.insert(cursor)
                cursor += 1
            }
        }
        return rows
    }

    private static func isDelimiterRow(_ line: String) -> Bool {
        line.contains("-") && line.allSatisfy { "|:- \t".contains($0) } && line.contains("|")
    }

    private static func markLine(_ line: String, inTable: Bool) -> String {
        var rest = Substring(line)
        let indent = rest.prefix { $0 == " " || $0 == "\t" }
        rest = rest.dropFirst(indent.count)
        var out = String(indent)
        if isThematicBreak(rest) { return out + mark(rest) }
        if let hashes = headingMarker(rest) {
            return out + mark(hashes) + inline(rest.dropFirst(hashes.count), inTable: false)
        }
        while rest.first == ">" {
            let quote = rest.prefix { $0 == ">" }
            out += mark(quote)
            rest = rest.dropFirst(quote.count)
            let space = rest.prefix { $0 == " " }
            out += space
            rest = rest.dropFirst(space.count)
        }
        if let bullet = listMarker(rest) {
            out += mark(bullet) + " "
            rest = rest.dropFirst(bullet.count + 1)
            if let box = rest.prefix(3).wholeMatch(of: /\[[ xX]\]/), rest.dropFirst(3).first.map({ $0 == " " }) ?? true {
                out += mark(box.output)
                rest = rest.dropFirst(3)
            }
        }
        return out + inline(rest, inTable: inTable)
    }

    private static func isThematicBreak(_ text: Substring) -> Bool {
        let marks = text.filter { $0 != " " && $0 != "\t" }
        guard marks.count >= 3, let first = marks.first, "-*_".contains(first) else { return false }
        return marks.allSatisfy { $0 == first }
    }

    private static func headingMarker(_ text: Substring) -> Substring? {
        let hashes = text.prefix { $0 == "#" }
        guard (1...6).contains(hashes.count) else { return nil }
        let after = text.dropFirst(hashes.count).first
        return after == nil || after == " " || after == "\t" ? hashes : nil
    }

    /// `-`, `*`, `+`, or a number with `.` or `)`, followed by a space.
    private static func listMarker(_ text: Substring) -> Substring? {
        if let first = text.first, "-*+".contains(first), text.dropFirst().first == " " { return text.prefix(1) }
        let digits = text.prefix { $0.isASCII && $0.isNumber }
        guard (1...9).contains(digits.count) else { return nil }
        let rest = text.dropFirst(digits.count)
        guard let delimiter = rest.first, delimiter == "." || delimiter == ")", rest.dropFirst().first == " " else { return nil }
        return text.prefix(digits.count + 1)
    }

    /// Link and image syntax around the words, and a table's pipes.
    private static func inline(_ text: Substring, inTable: Bool) -> String {
        var out = ""
        var rest = text
        while let link = rest.firstMatch(of: /!?\[([^\]]*)\]\(([^)\s]*(?:\s+"[^"]*")?)\)/) {
            out += plain(rest[..<link.range.lowerBound], inTable: inTable)
            let opener = link.output.0.hasPrefix("!") ? "![" : "["
            out += mark(opener) + plain(link.output.1, inTable: inTable) + mark("](\(link.output.2))")
            rest = rest[link.range.upperBound...]
        }
        return out + plain(rest, inTable: inTable)
    }

    private static func plain(_ text: Substring, inTable: Bool) -> String {
        guard inTable, text.contains("|") else { return HTML.escape(String(text)) }
        return text.split(separator: "|", omittingEmptySubsequences: false)
            .map { HTML.escape(String($0)) }
            .joined(separator: mark("|"))
    }
}
