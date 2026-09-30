import Foundation

/// Code in a Markdown fence, coloured by a small hand-written scanner.
///
/// Five token classes (`tok-kw`, `tok-str`, `tok-com`, `tok-fn`, `tok-num`)
/// coloured by `--luna-syntax-*` in the reading stylesheet. A scanner rather
/// than a grammar engine: a README's snippets need keywords, strings and
/// comments told apart, not a parse, and this never throws or backtracks.
/// A span never crosses a newline, so the Source view can split the output
/// into rows.
public enum SyntaxHighlighter {

    /// Escaped HTML for `code`. An unknown or missing language is plain
    /// escaped text.
    public static func html(_ code: String, language: String?) -> String {
        guard let grammar = language.flatMap(Grammar.named) else { return HTML.escape(code) }
        var scanner = Scanner(bytes: Array(code.utf8), grammar: grammar)
        return scanner.run()
    }

    struct Grammar {
        var keywords: Set<String>
        var lineComments: [String] = ["//"]
        var blockComment: (open: String, close: String)? = ("/*", "*/")
        var quotes: Set<UInt8> = [.quote, .apostrophe]
        var multilineQuotes: Set<UInt8> = []
        var tripleQuotes = false
        /// `@media` and friends are CSS's keywords.
        var atKeywords = false
        /// HTML and XML: tag names are keywords, quotes count only inside a tag.
        var markup = false
    }

    struct Scanner {
        let bytes: [UInt8]
        let grammar: Grammar
        var index = 0
        var plainStart = 0
        var inTag = false
        var out = ""

        init(bytes: [UInt8], grammar: Grammar) {
            self.bytes = bytes
            self.grammar = grammar
            out.reserveCapacity(bytes.count * 2)
        }

        mutating func run() -> String {
            while index < bytes.count {
                if let (end, kind) = token(at: index) {
                    if let kind {
                        flushPlain(upTo: index)
                        emit(kind, index..<end)
                        plainStart = end
                    }
                    index = end
                } else {
                    index += 1
                }
            }
            flushPlain(upTo: bytes.count)
            return out
        }

        /// The token starting at `start`: its end and class, or a nil class for
        /// a run that stays plain but must be skipped whole (an identifier that
        /// is not a keyword, so its tail is never read as a number).
        private mutating func token(at start: Int) -> (Int, String?)? {
            if let end = comment(at: start) { return (end, "tok-com") }
            if grammar.markup { return markupToken(at: start) }
            if let end = string(at: start) { return (end, "tok-str") }
            let byte = bytes[start]
            if byte.isDigit, !previousIsIdentifier(start) { return (number(from: start), "tok-num") }
            if grammar.atKeywords, byte == UInt8(ascii: "@"), start + 1 < bytes.count, bytes[start + 1].isIdentifierStart {
                return (identifierEnd(from: start + 1), "tok-kw")
            }
            guard byte.isIdentifierStart else { return nil }
            let end = identifierEnd(from: start)
            let word = text(start..<end)
            if grammar.keywords.contains(word) { return (end, "tok-kw") }
            if end < bytes.count, bytes[end] == UInt8(ascii: "(") { return (end, "tok-fn") }
            return (end, nil)
        }

        private mutating func markupToken(at start: Int) -> (Int, String?)? {
            let byte = bytes[start]
            if inTag {
                if byte == UInt8(ascii: ">") { inTag = false }
                if let end = string(at: start) { return (end, "tok-str") }
                return nil
            }
            guard byte == UInt8(ascii: "<") else { return nil }
            var nameStart = start + 1
            if nameStart < bytes.count, bytes[nameStart] == UInt8(ascii: "/") || bytes[nameStart] == UInt8(ascii: "?") {
                nameStart += 1
            }
            guard nameStart < bytes.count, bytes[nameStart].isIdentifierStart else { return nil }
            inTag = true
            flushPlain(upTo: nameStart)
            index = nameStart
            return (identifierEnd(from: nameStart), "tok-kw")
        }

        private func comment(at start: Int) -> Int? {
            for prefix in grammar.lineComments where matches(prefix, at: start) {
                // `#` opens a comment only as a word of its own: `$#`, `a#b` and
                // YAML's `key#` are not comments.
                if prefix == "#", start > 0, !bytes[start - 1].isSpace { continue }
                return bytes[start...].firstIndex(of: .newline) ?? bytes.count
            }
            if let block = grammar.blockComment, matches(block.open, at: start) {
                return find(block.close, from: start + block.open.utf8.count) ?? bytes.count
            }
            return nil
        }

        private func string(at start: Int) -> Int? {
            let quote = bytes[start]
            guard grammar.quotes.contains(quote) || grammar.multilineQuotes.contains(quote) else { return nil }
            // An apostrophe after a letter is prose ("it's"), not a string.
            if quote == .apostrophe, previousIsIdentifier(start) { return nil }
            if grammar.tripleQuotes, start + 2 < bytes.count, bytes[start + 1] == quote, bytes[start + 2] == quote {
                let close = String(repeating: Character(UnicodeScalar(quote)), count: 3)
                return find(close, from: start + 3) ?? bytes.count
            }
            let multiline = grammar.multilineQuotes.contains(quote)
            var cursor = start + 1
            while cursor < bytes.count {
                let byte = bytes[cursor]
                if byte == .backslash { cursor += 2; continue }
                if byte == quote { return cursor + 1 }
                if byte == .newline, !multiline { return cursor }
                cursor += 1
            }
            return bytes.count
        }

        private func number(from start: Int) -> Int {
            var cursor = start + 1
            while cursor < bytes.count {
                let byte = bytes[cursor]
                let decimalPoint = byte == UInt8(ascii: ".") && cursor + 1 < bytes.count && bytes[cursor + 1].isDigit
                guard byte.isIdentifierPart || decimalPoint else { break }
                cursor += 1
            }
            return cursor
        }

        private func identifierEnd(from start: Int) -> Int {
            var cursor = start + 1
            while cursor < bytes.count, bytes[cursor].isIdentifierPart { cursor += 1 }
            return cursor
        }

        private func previousIsIdentifier(_ position: Int) -> Bool {
            position > 0 && bytes[position - 1].isIdentifierPart
        }

        private func matches(_ text: String, at start: Int) -> Bool {
            let utf8 = text.utf8
            guard start + utf8.count <= bytes.count else { return false }
            return zip(bytes[start...], utf8).allSatisfy { $0 == $1 }
        }

        /// The index just past `text`, searching from `start`.
        private func find(_ text: String, from start: Int) -> Int? {
            var cursor = start
            while cursor < bytes.count {
                if matches(text, at: cursor) { return cursor + text.utf8.count }
                cursor += 1
            }
            return nil
        }

        /// The scanner only cuts at ASCII bytes, so every slice is whole UTF-8
        /// and the non-failable decode cannot substitute anything.
        private func text(_ range: Range<Int>) -> String {
            String(decoding: bytes[range], as: UTF8.self) // swiftlint:disable:this optional_data_string_conversion
        }

        private mutating func flushPlain(upTo end: Int) {
            guard plainStart < end else { return }
            out += HTML.escape(text(plainStart..<end))
            plainStart = end
        }

        /// One span per line of the token, so no span holds a newline.
        private mutating func emit(_ kind: String, _ range: Range<Int>) {
            let lines = text(range).split(separator: "\n", omittingEmptySubsequences: false)
            for (number, line) in lines.enumerated() {
                if number > 0 { out += "\n" }
                if !line.isEmpty { out += "<span class=\"\(kind)\">\(HTML.escape(String(line)))</span>" }
            }
        }
    }
}

private extension UInt8 {
    static let quote = UInt8(ascii: "\"")
    static let apostrophe = UInt8(ascii: "'")
    static let backslash = UInt8(ascii: "\\")
    static let newline = UInt8(ascii: "\n")

    var isDigit: Bool { self >= 0x30 && self <= 0x39 }
    var isSpace: Bool { self == 0x20 || self == 0x09 || self == 0x0A || self == 0x0D }
    var isIdentifierStart: Bool {
        (self >= 0x41 && self <= 0x5A) || (self >= 0x61 && self <= 0x7A) || self == 0x5F || self == 0x24
    }
    var isIdentifierPart: Bool { isIdentifierStart || isDigit }
}
