@testable import BrowserKit
import Foundation
import Testing

@Suite("Markdown source view")
struct MarkdownSourceTests {

    private func rows(_ text: String) -> [String] {
        let html = MarkdownSource.html(text)
        return html.components(separatedBy: "</div>").dropLast().map {
            $0.replacingOccurrences(of: #"<div class="src-line">"#, with: "")
        }
    }

    private func mark(_ text: String) -> String { #"<span class="md-mark">\#(text)</span>"# }

    @Test func oneRowPerLineIncludingEmptyOnes() {
        #expect(rows("a\n\nb").count == 3)
        #expect(rows("a\r\n\r\nb\r\n").count == 3)
        #expect(rows("").count == 1)
    }

    @Test func textIsEscaped() {
        #expect(rows("<script>&")[0] == "&lt;script&gt;&amp;")
    }

    @Test func headingBulletAndQuoteMarkersAreWrapped() {
        let lines = rows("## Title\n- item\n12. step\n> quote\n---")
        #expect(lines[0] == mark("##") + " Title")
        #expect(lines[1] == mark("-") + " item")
        #expect(lines[2] == mark("12.") + " step")
        #expect(lines[3] == mark("&gt;") + " quote")
        #expect(lines[4] == mark("---"))
    }

    @Test func taskBracketsAndLinkURLsAreWrapped() {
        let lines = rows("- [x] done\nsee [docs](https://a.example) now")
        #expect(lines[0] == mark("-") + " " + mark("[x]") + " done")
        #expect(lines[1] == "see " + mark("[") + "docs" + mark("](https://a.example)") + " now")
    }

    @Test func tablePipesAreWrapped() {
        let lines = rows("| a | b |\n|---|---|\n| 1 | 2 |")
        #expect(lines[0] == mark("|") + " a " + mark("|") + " b " + mark("|"))
        #expect(lines[2].hasPrefix(mark("|")))
    }

    @Test func fencesAreMarkedAndTheirContentHighlighted() {
        let lines = rows("```swift\nlet x = 1 // # not a heading\n```\n# Real")
        #expect(lines[0] == mark("```swift"))
        #expect(lines[1].contains(#"<span class="tok-kw">let</span>"#))
        #expect(lines[1].contains(#"<span class="tok-com">// # not a heading</span>"#))
        #expect(lines[2] == mark("```"))
        #expect(lines[3] == mark("#") + " Real")
    }
}
