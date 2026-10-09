//
//  AgentMarkdown.swift
//  Luna
//
//  The agent's words as the panel draws them: the Markdown it writes —
//  paragraphs, headings, bulleted and numbered lists, quotes, code — set as
//  type rather than shown as asterisks and hashes. Parsed by Foundation
//  (`AttributedString(markdown:)`, full syntax), then each block given a
//  paragraph style: lists hang their text off the bullet, headings step up a
//  weight, code is monospaced on a wash.
//
//  The text arrives a few words at a time, so half a list or an unclosed
//  `**` is ordinary input; Foundation reads what is there, and anything it
//  cannot parse is shown as plain text.
//

import AppKit

@MainActor
enum AgentMarkdown {

    /// How far a list's text stands in from its bullet, per level.
    static let listIndent: CGFloat = 20
    /// The column's leading: 13 pt type on 3.5 pt more than its line, about
    /// 1.4 of the size, which a column ~45 characters wide reads easily at.
    /// At 2 the paragraphs set as one grey block.
    static let lineGap: CGFloat = 3.5
    /// Between paragraphs, most of a line; between list items, a third of that.
    static let paragraphGap: CGFloat = 10
    static let itemGap: CGFloat = 5

    /// The words alone, every block set as text — tables and code included.
    /// `segments` is what the panel draws; this is the same reading as one string.
    static func render(_ markdown: String) -> NSAttributedString {
        guard let parsed = parse(markdown) else { return plain(markdown) }
        var text = TextBuilder()
        for run in parsed.runs { text.append(run, of: parsed) }
        return text.result
    }

    static func parse(_ markdown: String) -> AttributedString? {
        let options = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: false, interpretedSyntax: .full, failurePolicy: .returnPartiallyParsedIfPossible
        )
        return try? AttributedString(markdown: markdown, options: options)
    }

    static func plain(_ text: String) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [.font: Tokens.TypeScale.agentBody, .foregroundColor: Tokens.Text.primary])
    }

    /// Runs of prose, set one after another: a line break between blocks,
    /// and each list item's bullet or number before its first run.
    @MainActor
    struct TextBuilder {
        let result = NSMutableAttributedString()
        private var block: PresentationIntent?
        private var listItem: Int?

        mutating func append(_ run: AttributedString.Runs.Run, of parsed: AttributedString) {
            let intent = run.presentationIntent
            if intent != block {
                if result.length > 0 { result.append(NSAttributedString(string: "\n", attributes: [.font: Tokens.TypeScale.agentBody])) }
                block = intent
                if let item = intent.flatMap(AgentMarkdown.listItem), item.identity != listItem {
                    listItem = item.identity
                    let marker = AgentMarkdown.style(for: intent, marker: true)
                    result.append(NSAttributedString(string: item.marker + "\t", attributes: marker))
                }
            }
            var text = String(parsed[run.range].characters)
            // A code block brings its own last line break, and blocks are
            // already parted by one.
            if intent?.components.contains(where: { AgentMarkdown.isCode($0.kind) }) == true, text.hasSuffix("\n") {
                text.removeLast()
            }
            result.append(NSAttributedString(string: text, attributes: AgentMarkdown.attributes(of: run, intent: intent)))
        }
    }

    /// A run's attributes: its block's style, then its own bold, italics,
    /// code and link.
    static func attributes(of run: AttributedString.Runs.Run, intent: PresentationIntent?, base: NSFont? = nil)
        -> [NSAttributedString.Key: Any] {
        var attributes = style(for: intent, marker: false)
        if let base { attributes[.font] = base }
        inline(run.inlinePresentationIntent ?? [], into: &attributes)
        if let link = run.link {
            attributes[.link] = link
            attributes[.foregroundColor] = Tokens.Astro.link
            let font = attributes[.font] as? NSFont ?? Tokens.TypeScale.agentBody
            let medium = font.fontDescriptor.addingAttributes([.traits: [NSFontDescriptor.TraitKey.weight: NSFont.Weight.medium]])
            attributes[.font] = NSFont(descriptor: medium, size: font.pointSize) ?? font
        }
        return attributes
    }

    static func isCode(_ kind: PresentationIntent.Kind) -> Bool {
        if case .codeBlock = kind { true } else { false }
    }

    struct ListItem {
        var identity: Int
        var marker: String
    }

    /// The innermost list item a block is in, and the mark it opens with.
    static func listItem(_ intent: PresentationIntent) -> ListItem? {
        let components = intent.components
        guard let index = components.firstIndex(where: { if case .listItem = $0.kind { true } else { false } }),
              case let .listItem(ordinal) = components[index].kind else { return nil }
        let ordered = components[(index + 1)...].first { component in
            switch component.kind {
            case .orderedList, .unorderedList: true
            default: false
            }
        }.map { if case .orderedList = $0.kind { true } else { false } } ?? false
        return ListItem(identity: components[index].identity, marker: ordered ? "\(ordinal)." : "•")
    }

    static func style(for intent: PresentationIntent?, marker: Bool) -> [NSAttributedString.Key: Any] {
        let body = Tokens.TypeScale.agentBody
        let paragraph = NSMutableParagraphStyle()
        paragraph.paragraphSpacing = paragraphGap
        paragraph.lineSpacing = lineGap
        var font = body
        var colour = Tokens.Text.primary
        var attributes: [NSAttributedString.Key: Any] = [:]
        for component in intent?.components ?? [] {
            switch component.kind {
            case let .header(level):
                // Each level a clear step: bold and four up for the first,
                // semibold two up, then semibold at the body's size.
                font = .systemFont(ofSize: body.pointSize + (level <= 1 ? 4 : level == 2 ? 2 : 0), weight: level <= 1 ? .bold : .semibold)
                paragraph.paragraphSpacingBefore = paragraphGap / 2
                paragraph.paragraphSpacing = paragraphGap / 2
            case .codeBlock:
                font = .monospacedSystemFont(ofSize: body.pointSize - 1.5, weight: .regular)
                attributes[.backgroundColor] = Tokens.Surface.hover
            case .blockQuote:
                // Its rule is drawn beside it (`AgentQuoteView`).
                colour = Tokens.Text.secondary
            default:
                break
            }
        }
        let depth = intent?.components.filter { if case .listItem = $0.kind { true } else { false } }.count ?? 0
        if depth > 0 {
            let indent = CGFloat(depth) * listIndent
            paragraph.headIndent = indent
            paragraph.firstLineHeadIndent = indent - listIndent
            paragraph.tabStops = [NSTextTab(textAlignment: .left, location: indent)]
            paragraph.paragraphSpacing = itemGap
            if marker { colour = Tokens.Text.secondary }
        }
        attributes[.font] = font
        attributes[.foregroundColor] = colour
        attributes[.paragraphStyle] = paragraph
        return attributes
    }

    private static func inline(_ intent: InlinePresentationIntent, into attributes: inout [NSAttributedString.Key: Any]) {
        let font = attributes[.font] as? NSFont ?? Tokens.TypeScale.agentBody
        if intent.contains(.code) {
            attributes[.font] = NSFont.monospacedSystemFont(ofSize: font.pointSize - 1, weight: .regular)
            attributes[.backgroundColor] = Tokens.Astro.from.withAlphaComponent(0.18)
            return
        }
        if intent.contains(.strikethrough) { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        var traits: NSFontDescriptor.SymbolicTraits = []
        if intent.contains(.stronglyEmphasized) { traits.insert(.bold) }
        if intent.contains(.emphasized) { traits.insert(.italic) }
        guard !traits.isEmpty else { return }
        attributes[.font] = NSFont(descriptor: font.fontDescriptor.withSymbolicTraits(traits), size: font.pointSize) ?? font
        // Bold is the agent marking what matters, so it keeps the primary
        // ink even in a quote, which is set in the secondary.
        if intent.contains(.stronglyEmphasized) { attributes[.foregroundColor] = Tokens.Text.primary }
    }
}
