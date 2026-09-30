@testable import BrowserKit
import Foundation
import Testing

@Suite("Syntax highlighter")
struct SyntaxHighlighterTests {

    private func kw(_ word: String) -> String { #"<span class="tok-kw">\#(word)</span>"# }
    private func str(_ text: String) -> String { #"<span class="tok-str">\#(text)</span>"# }
    private func com(_ text: String) -> String { #"<span class="tok-com">\#(text)</span>"# }

    /// One sample per language: its name, the code, and the keyword, string
    /// and comment it must find.
    @Test(arguments: [
        ["swift", "let s = \"a\" // c", "let", "&quot;a&quot;", "// c"],
        ["js", "const s = 'a' /* c */", "const", "&#39;a&#39;", "/* c */"],
        ["typescript", "export const s = `a` // c", "export", "`a`", "// c"],
        ["python", "def f(): return 'a'  # c", "def", "&#39;a&#39;", "# c"],
        ["bash", "if [ -f x ]; then echo \"a\"; fi # c", "if", "&quot;a&quot;", "# c"],
        ["zsh", "for f in *; do echo 'a'; done # c", "for", "&#39;a&#39;", "# c"],
        ["go", "func main() { s := \"a\" } // c", "func", "&quot;a&quot;", "// c"],
        ["rust", "fn main() { let s = \"a\"; } // c", "fn", "&quot;a&quot;", "// c"],
        ["ruby", "def f; puts \"a\"; end # c", "def", "&quot;a&quot;", "# c"],
        ["yaml", "on: true # c\nname: \"a\"", "true", "&quot;a&quot;", "# c"],
        ["c", "int main() { return \"a\"; } /* c */", "int", "&quot;a&quot;", "/* c */"],
        ["css", "@media screen { a { content: \"a\"; } } /* c */", "@media", "&quot;a&quot;", "/* c */"]
    ])
    func findsKeywordStringAndComment(_ sample: [String]) {
        let html = SyntaxHighlighter.html(sample[1], language: sample[0])
        #expect(html.contains(kw(sample[2])), "\(sample[0]): \(html)")
        #expect(html.contains(str(sample[3])), "\(sample[0]): \(html)")
        #expect(html.contains(com(sample[4])), "\(sample[0]): \(html)")
    }

    @Test func jsonHasStringsNumbersAndLiterals() {
        let html = SyntaxHighlighter.html(#"{"a": 1.5, "b": null}"#, language: "json")
        #expect(html.contains(str("&quot;a&quot;")))
        #expect(html.contains(#"<span class="tok-num">1.5</span>"#))
        #expect(html.contains(kw("null")))
    }

    @Test func htmlTagsAttributesAndComments() {
        let html = SyntaxHighlighter.html("<a href=\"x\">it's</a><!-- c -->", language: "html")
        #expect(html.contains(#"&lt;<span class="tok-kw">a</span>"#))
        #expect(html.contains(str("&quot;x&quot;")))
        #expect(html.contains("it&#39;s"))
        #expect(!html.contains(str("&#39;s")))
        #expect(html.contains(com("&lt;!-- c --&gt;")))
    }

    @Test func functionCallsAndNumbers() {
        let html = SyntaxHighlighter.html("print(42)", language: "python")
        #expect(html.contains(#"<span class="tok-fn">print</span>"#))
        #expect(html.contains(#"<span class="tok-num">42</span>"#))
    }

    @Test func unknownLanguageIsEscapedPlainText() {
        #expect(SyntaxHighlighter.html("if <b> & \"x\"", language: "klingon") == "if &lt;b&gt; &amp; &quot;x&quot;")
        #expect(SyntaxHighlighter.html("let x", language: nil) == "let x")
    }

    @Test func angleBracketsInCodeAreEscaped() {
        let html = SyntaxHighlighter.html("if a < b && c > d { \"<script>\" }", language: "swift")
        #expect(!html.contains("<script"))
        #expect(html.contains("a &lt; b &amp;&amp; c &gt; d"))
    }

    @Test func spansNeverCrossALine() {
        let html = SyntaxHighlighter.html("/* one\ntwo */ x", language: "c")
        for line in html.split(separator: "\n", omittingEmptySubsequences: false) {
            #expect(line.components(separatedBy: "<span").count == line.components(separatedBy: "</span>").count)
        }
    }

    @Test func unterminatedInputNeverTraps() {
        for language in ["swift", "python", "html", "css", "bash", "json", "rust"] {
            for code in ["\"", "'", "/*", "<!--", "<", "0x", "\"\"\"", "#", "`", "\\"] {
                _ = SyntaxHighlighter.html(code, language: language)
            }
        }
    }
}
