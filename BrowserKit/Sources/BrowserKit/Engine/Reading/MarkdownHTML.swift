import Foundation
import Markdown

/// A Markdown document rendered for `<article class="luna-reading">`: the
/// article's inner HTML, the title the tab shows and the headings the outline
/// lists.
///
/// Parsed by swift-markdown (cmark-gfm, GitHub's own parser) with smart
/// punctuation off, since GitHub leaves quotes straight. The output is built
/// here rather than by cmark's HTML renderer because every node needs Luna's
/// rules: raw HTML is never passed through, and a link or image keeps its
/// destination only when that destination cannot run anything.
public struct MarkdownHTML: Sendable, Equatable {

    public struct Heading: Sendable, Equatable {
        public let level: Int
        public let text: String
        public let id: String
    }

    public let html: String
    /// The first level-one heading, else the file name.
    public let title: String
    public let headings: [Heading]

    public init(markdown: String, fileName: String) {
        let document = Document(parsing: markdown, options: [.disableSmartOpts])
        var writer = HTMLWriter(source: markdown)
        writer.visit(document)
        html = writer.out
        headings = writer.headings
        title = writer.headings.first { $0.level == 1 }?.text ?? fileName
    }

    /// `destination` when it is safe to put in `href` or `src`, else nil.
    ///
    /// Allowed: http, https, mailto, and anything without a scheme (relative
    /// paths, `#fragment`, `//host`), which resolves against the document's
    /// own URL. An image may also be an inline raster `data:` URL; SVG is not
    /// one of them, since an SVG can carry script.
    static func safeDestination(_ destination: String, image: Bool) -> String? {
        // A browser drops tabs, newlines and leading spaces before it reads a
        // scheme, so `java\tscript:` is `javascript:` to it; check it that way.
        let squeezed = String(String.UnicodeScalarView(destination.unicodeScalars.filter { $0.value > 0x20 && $0.value != 0x7F }))
        guard let colon = squeezed.firstIndex(of: ":") else { return destination }
        let scheme = squeezed[..<colon]
        if scheme.contains(where: { "/?#".contains($0) }) { return destination }
        switch scheme.lowercased() {
        case "http", "https", "mailto": return destination
        case "data" where image && squeezed.range(of: #"^data:image/(png|jpeg|gif|webp)[;,]"#,
                                                   options: [.regularExpression, .caseInsensitive]) != nil:
            return destination
        default: return nil
        }
    }

    /// GitHub's anchor for a heading: lowercase, punctuation dropped, spaces
    /// turned into hyphens.
    static func slug(_ text: String) -> String {
        var slug = ""
        for character in text.lowercased() {
            if character == " " {
                slug.append("-")
            } else if character.isLetter || character.isNumber || character == "-" || character == "_" {
                slug.append(character)
            }
        }
        return slug.isEmpty ? "section" : slug
    }
}

private struct HTMLWriter: MarkupVisitor {
    var out = ""
    var headings: [MarkdownHTML.Heading] = []
    private var slugUses: [String: Int] = [:]
    /// Whether each open list is tight, innermost last.
    private var tightLists: [Bool] = []
    private var linkDepth = 0
    private var alignments: [Table.ColumnAlignment?] = []
    /// Blank-ness of each source line (1-based through `line - 1`), for list tightness.
    private let blankLines: [Bool]

    init(source: String) {
        blankLines = source.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .map { $0.allSatisfy(\.isWhitespace) }
        out.reserveCapacity(source.utf8.count * 2)
    }

    mutating func defaultVisit(_ markup: any Markup) {
        for child in markup.children { visit(child) }
    }

    /// Blocks start on their own line, which in a tight list item follows the
    /// item's text directly.
    private mutating func block(_ open: String) {
        if let last = out.utf8.last, last != UInt8(ascii: "\n") { out += "\n" }
        out += open
    }

    // MARK: Blocks

    mutating func visitParagraph(_ paragraph: Paragraph) {
        if paragraph.parent is ListItem, tightLists.last == true {
            defaultVisit(paragraph)
        } else {
            out += "<p>"
            defaultVisit(paragraph)
            out += "</p>\n"
        }
    }

    mutating func visitHeading(_ heading: Markdown.Heading) {
        let text = heading.plainText
        let base = MarkdownHTML.slug(text)
        let uses = slugUses[base, default: 0]
        slugUses[base] = uses + 1
        let id = uses == 0 ? base : "\(base)-\(uses)"
        headings.append(.init(level: heading.level, text: text, id: id))
        block("<h\(heading.level) id=\"\(HTML.escape(id))\">")
        defaultVisit(heading)
        out += "</h\(heading.level)>\n"
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) {
        block("<blockquote>\n")
        defaultVisit(blockQuote)
        out += "</blockquote>\n"
    }

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) {
        block("<hr>\n")
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) {
        let language = codeBlock.language ?? ""
        let token = String(language.filter { $0.isASCII && ($0.isLetter || $0.isNumber || "+#-_.".contains($0)) })
        let attributes = token.isEmpty ? "" : " data-lang=\"\(HTML.escape(token))\""
        let codeClass = token.isEmpty ? "" : " class=\"language-\(HTML.escape(token))\""
        block("<div class=\"luna-code\"><button class=\"luna-copy\" type=\"button\" aria-label=\"Copy code\"></button>")
        out += "<pre\(attributes)><code\(codeClass)>"
        out += SyntaxHighlighter.html(codeBlock.code, language: codeBlock.language)
        out += "</code></pre></div>\n"
    }

    /// Raw HTML is shown as the text it is. Passing it through would let a
    /// README run script in the reader; dropping it would hide what the
    /// author wrote with no sign anything was there. Comments are the
    /// exception: they were written to be invisible.
    mutating func visitHTMLBlock(_ html: HTMLBlock) {
        let raw = html.rawHTML.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.hasPrefix("<!--"), raw.hasSuffix("-->") { return }
        block("<pre class=\"luna-raw-html\">\(HTML.escape(raw))</pre>\n")
    }

    // MARK: Lists

    mutating func visitUnorderedList(_ unorderedList: UnorderedList) {
        list(unorderedList, open: "<ul>\n", close: "</ul>\n")
    }

    mutating func visitOrderedList(_ orderedList: OrderedList) {
        let start = orderedList.startIndex == 1 ? "" : " start=\"\(orderedList.startIndex)\""
        list(orderedList, open: "<ol\(start)>\n", close: "</ol>\n")
    }

    private mutating func list(_ list: any ListItemContainer, open: String, close: String) {
        tightLists.append(isTight(list))
        block(open)
        defaultVisit(list)
        out += close
        tightLists.removeLast()
    }

    /// CommonMark's rule: a list is loose when a blank line separates two of
    /// its items, or two blocks directly inside one item. swift-markdown does
    /// not expose cmark's flag, so the source lines answer it.
    private func isTight(_ list: any ListItemContainer) -> Bool {
        let items = Array(list.listItems)
        if items.dropFirst().contains(where: blankLineBefore) { return false }
        return !items.contains { item in Array(item.children).dropFirst().contains(where: blankLineBefore) }
    }

    private func blankLineBefore(_ markup: any Markup) -> Bool {
        guard let line = markup.range?.lowerBound.line, line >= 2, line - 2 < blankLines.count else { return false }
        return blankLines[line - 2]
    }

    mutating func visitListItem(_ listItem: ListItem) {
        switch listItem.checkbox {
        case .checked: out += "<li class=\"task\"><input type=\"checkbox\" disabled checked> "
        case .unchecked: out += "<li class=\"task\"><input type=\"checkbox\" disabled> "
        case nil: out += "<li>"
        }
        defaultVisit(listItem)
        out += "</li>\n"
    }

    // MARK: Tables

    mutating func visitTable(_ table: Table) {
        alignments = table.columnAlignments
        block("<table>\n")
        defaultVisit(table)
        out += "</table>\n"
    }

    mutating func visitTableHead(_ tableHead: Table.Head) {
        out += "<thead>\n<tr>\n"
        defaultVisit(tableHead)
        out += "</tr>\n</thead>\n"
    }

    mutating func visitTableBody(_ tableBody: Table.Body) {
        guard tableBody.childCount > 0 else { return }
        out += "<tbody>\n"
        defaultVisit(tableBody)
        out += "</tbody>\n"
    }

    mutating func visitTableRow(_ tableRow: Table.Row) {
        out += "<tr>\n"
        defaultVisit(tableRow)
        out += "</tr>\n"
    }

    mutating func visitTableCell(_ tableCell: Table.Cell) {
        let tag = tableCell.parent is Table.Head ? "th" : "td"
        let column = tableCell.indexInParent
        let alignment = column < alignments.count ? alignments[column] : nil
        let style = switch alignment {
        case .left: " style=\"text-align:left\""
        case .center: " style=\"text-align:center\""
        case .right: " style=\"text-align:right\""
        case nil: ""
        }
        out += "<\(tag)\(style)>"
        defaultVisit(tableCell)
        out += "</\(tag)>\n"
    }

    // MARK: Inlines

    mutating func visitText(_ text: Markdown.Text) {
        if linkDepth == 0 { writeLinkified(text.string) } else { out += HTML.escape(text.string) }
    }

    mutating func visitSoftBreak(_ softBreak: SoftBreak) { out += "\n" }

    mutating func visitLineBreak(_ lineBreak: LineBreak) { out += "<br>\n" }

    mutating func visitInlineCode(_ inlineCode: InlineCode) {
        out += "<code>\(HTML.escape(inlineCode.code))</code>"
    }

    mutating func visitEmphasis(_ emphasis: Emphasis) { wrap("em", emphasis) }

    mutating func visitStrong(_ strong: Strong) { wrap("strong", strong) }

    mutating func visitStrikethrough(_ strikethrough: Strikethrough) { wrap("del", strikethrough) }

    private mutating func wrap(_ tag: String, _ markup: any Markup) {
        out += "<\(tag)>"
        defaultVisit(markup)
        out += "</\(tag)>"
    }

    /// See `visitHTMLBlock`.
    mutating func visitInlineHTML(_ inlineHTML: InlineHTML) {
        if inlineHTML.rawHTML.hasPrefix("<!--") { return }
        out += HTML.escape(inlineHTML.rawHTML)
    }

    mutating func visitLink(_ link: Markdown.Link) {
        guard let destination = link.destination.flatMap({ MarkdownHTML.safeDestination($0, image: false) }) else {
            defaultVisit(link)
            return
        }
        out += "<a href=\"\(HTML.escape(destination))\"\(titleAttribute(link.title))>"
        linkDepth += 1
        defaultVisit(link)
        linkDepth -= 1
        out += "</a>"
    }

    mutating func visitImage(_ image: Markdown.Image) {
        let alt = HTML.escape(image.plainText)
        guard let source = image.source.flatMap({ MarkdownHTML.safeDestination($0, image: true) }) else {
            out += alt
            return
        }
        out += "<img src=\"\(HTML.escape(source))\" alt=\"\(alt)\"\(titleAttribute(image.title))>"
    }

    private func titleAttribute(_ title: String?) -> String {
        guard let title, !title.isEmpty else { return "" }
        return " title=\"\(HTML.escape(title))\""
    }

    /// GitHub's extended autolinks for bare `http://` and `https://` URLs,
    /// which swift-markdown's parser does not enable. `www.` without a scheme
    /// is not linked.
    private mutating func writeLinkified(_ text: String) {
        var rest = Substring(text)
        while let found = rest.range(of: "http") {
            let candidate = rest[found.lowerBound...]
            let end = Self.urlEnd(in: candidate)
            let url = candidate[..<end]
            guard url.hasPrefix("https://") || url.hasPrefix("http://"), !url.hasSuffix("//") else {
                out += HTML.escape(String(rest[..<found.upperBound]))
                rest = rest[found.upperBound...]
                continue
            }
            let escaped = HTML.escape(String(url))
            out += HTML.escape(String(rest[..<found.lowerBound]))
            out += "<a href=\"\(escaped)\">\(escaped)</a>"
            rest = candidate[end...]
        }
        out += HTML.escape(String(rest))
    }

    /// Where a bare URL stops: at whitespace or `<`, less trailing punctuation
    /// and any `)` that does not close a `(` inside the URL.
    private static func urlEnd(in candidate: Substring) -> Substring.Index {
        var end = candidate.firstIndex { $0.isWhitespace || $0 == "<" } ?? candidate.endIndex
        while end > candidate.startIndex {
            let last = candidate[candidate.index(before: end)]
            let url = candidate[..<end]
            if last == ")", url.filter({ $0 == "(" }).count >= url.filter({ $0 == ")" }).count { break }
            guard ".,:;!?'\"*_~)".contains(last) else { break }
            end = candidate.index(before: end)
        }
        return end
    }
}
