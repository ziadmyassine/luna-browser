@testable import BrowserKit
import Foundation
import Testing

/// The Markdown renderer: GitHub's structure in, a `.luna-reading` fragment out.
@Suite("Markdown HTML")
struct MarkdownHTMLTests {

    private func render(_ markdown: String, fileName: String = "README.md") -> MarkdownHTML {
        MarkdownHTML(markdown: markdown, fileName: fileName)
    }

    // MARK: - Structure

    @Test func headingsGetUniqueGitHubSlugs() {
        let page = render("# Hello World\n## Hello World\n## Hello World\n### What's `new`?\n")
        #expect(page.html.contains(#"<h1 id="hello-world">Hello World</h1>"#))
        #expect(page.html.contains(#"<h2 id="hello-world-1">Hello World</h2>"#))
        #expect(page.html.contains(#"<h2 id="hello-world-2">Hello World</h2>"#))
        #expect(page.html.contains(#"<h3 id="whats-new">What&#39;s <code>new</code>?</h3>"#))
    }

    @Test func headingListFeedsTheOutline() {
        let page = render("# Title\n\ntext\n\n## Install\n### From source\n## Install\n")
        #expect(page.headings == [
            .init(level: 1, text: "Title", id: "title"),
            .init(level: 2, text: "Install", id: "install"),
            .init(level: 3, text: "From source", id: "from-source"),
            .init(level: 2, text: "Install", id: "install-1")
        ])
    }

    @Test func titleIsTheFirstH1ElseTheFileName() {
        #expect(render("## Sub\n# First\n# Second\n").title == "First")
        #expect(render("## Only a subheading\n", fileName: "notes.md").title == "notes.md")
        #expect(render("", fileName: "empty.md").title == "empty.md")
    }

    @Test func paragraphsAndInlineFormatting() {
        let html = render("A *b* **c** ~~d~~ `e<f>`\nnext").html
        #expect(html == "<p>A <em>b</em> <strong>c</strong> <del>d</del> <code>e&lt;f&gt;</code>\nnext</p>\n")
    }

    @Test func tightListsHaveNoParagraphsNestedAndOrderedWork() {
        let html = render("- one\n- two\n  1. inner\n  2. more\n- three\n").html
        #expect(html == "<ul>\n<li>one</li>\n<li>two\n<ol>\n<li>inner</li>\n<li>more</li>\n</ol>\n</li>\n<li>three</li>\n</ul>\n")
    }

    @Test func looseListsKeepParagraphs() {
        let html = render("- one\n\n- two\n").html
        #expect(html == "<ul>\n<li><p>one</p>\n</li>\n<li><p>two</p>\n</li>\n</ul>\n")
    }

    @Test func orderedListKeepsItsStart() {
        let html = render("3. c\n4. d\n").html
        #expect(html.hasPrefix(#"<ol start="3">"#))
    }

    @Test func taskListsAreDisabledCheckboxes() {
        let html = render("- [ ] todo\n- [x] done\n").html
        #expect(html.contains(#"<li class="task"><input type="checkbox" disabled> todo</li>"#))
        #expect(html.contains(#"<li class="task"><input type="checkbox" disabled checked> done</li>"#))
    }

    @Test func tablesCarryColumnAlignment() {
        let html = render("| a | b | c | d |\n|:--|:-:|--:|---|\n| 1 | 2 | 3 | 4 |\n").html
        #expect(html.contains(#"<th style="text-align:left">a</th>"#))
        #expect(html.contains(#"<th style="text-align:center">b</th>"#))
        #expect(html.contains(#"<th style="text-align:right">c</th>"#))
        #expect(html.contains("<th>d</th>"))
        #expect(html.contains(#"<td style="text-align:right">3</td>"#))
        #expect(html.contains("<thead>") && html.contains("<tbody>"))
    }

    @Test func blockquoteAndRule() {
        let html = render("> quoted\n\n---\n").html
        #expect(html == "<blockquote>\n<p>quoted</p>\n</blockquote>\n<hr>\n")
    }

    @Test func linksAndAutolinks() {
        let html = render("[site](https://a.example \"T\") <https://b.example> and https://c.example/x.\n").html
        #expect(html.contains(#"<a href="https://a.example" title="T">site</a>"#))
        #expect(html.contains(#"<a href="https://b.example">https://b.example</a>"#))
        #expect(html.contains(#"<a href="https://c.example/x">https://c.example/x</a>."#))
    }

    @Test func relativeImagesAreKeptAsIs() {
        let html = render("![Logo](docs/logo.png) ![up](../a b.png)").html
        #expect(html.contains(#"<img src="docs/logo.png" alt="Logo">"#))
        #expect(render("![x](#frag)").html.contains(##"src="#frag""##))
    }

    @Test func fencedCodeCarriesLanguageHighlightAndCopyButton() {
        let html = render("```swift\nlet x = \"hi\" // note\n```\n").html
        #expect(html.contains(#"<div class="luna-code">"#))
        #expect(html.contains(#"<button class="luna-copy" type="button" aria-label="Copy code"></button>"#))
        #expect(html.contains(#"<pre data-lang="swift"><code class="language-swift">"#))
        #expect(html.contains(#"<span class="tok-kw">let</span>"#))
        #expect(html.contains(#"<span class="tok-str">&quot;hi&quot;</span>"#))
        #expect(html.contains(#"<span class="tok-com">// note</span>"#))
    }

    @Test func fenceLanguageCannotBreakTheAttribute() {
        let html = render("```\"><script>x\ncode\n```\n").html
        #expect(!html.contains("<script"))
        #expect(!html.contains(#"data-lang="""#))
    }

    // MARK: - Security

    @Test func rawHTMLBlocksAreShownAsText() {
        let html = render("<script>alert(1)</script>\n\n<iframe src=\"https://x\"></iframe>\n").html
        #expect(!html.contains("<script"))
        #expect(!html.contains("<iframe"))
        #expect(html.contains("&lt;script&gt;alert(1)&lt;/script&gt;"))
    }

    @Test func inlineHTMLIsShownAsText() {
        let html = render("hi <img src=x onerror=alert(1)> there <b>bold</b>").html
        #expect(!html.contains("<img"))
        #expect(!html.contains("<b>"))
        #expect(html.contains("&lt;img src=x onerror=alert(1)&gt;"))
    }

    @Test func htmlCommentsAreDropped() {
        let html = render("<!-- hidden -->\n\ntext <!-- also --> more\n").html
        #expect(!html.contains("hidden"))
        #expect(!html.contains("also"))
    }

    @Test(arguments: [
        "[a](javascript:alert(1))",
        "[a](JavaScript:alert(1))",
        "[a](javascript&#58;alert(1))",
        "[a](vbscript:msgbox)",
        "[a](data:text/html,<script>alert(1)</script>)",
        "[a](file:///etc/passwd)",
        "<javascript:alert(1)>",
        "![a](javascript:alert(1))",
        "![a](data:text/html;base64,PHNjcmlwdD4=)",
        "![a](data:image/svg+xml,<svg onload=alert(1)>)"
    ])
    func dangerousDestinationsAreDropped(_ markdown: String) {
        let html = render(markdown).html
        #expect(!html.contains("href="), "\(html)")
        #expect(!html.contains("src="), "\(html)")
        #expect(!html.lowercased().contains("=\"javascript"), "\(html)")
    }

    @Test func droppedLinksKeepTheirText() {
        #expect(render("[click](javascript:alert(1))").html == "<p>click</p>\n")
        #expect(render("![alt text](javascript:x)").html == "<p>alt text</p>\n")
    }

    @Test func safeDestinationsSurvive() {
        let html = render("[m](mailto:a@b.c) [f](#install) [r](docs/a.md) ![p](data:image/png;base64,AAAA)").html
        #expect(html.contains(#"href="mailto:a@b.c""#))
        #expect(html.contains(##"href="#install""##))
        #expect(html.contains(#"href="docs/a.md""#))
        #expect(html.contains(#"src="data:image/png;base64,AAAA""#))
    }

    @Test func quotesCannotBreakOutOfAttributes() {
        let html = render(#"[a](https://x.example/"onmouseover="alert(1) "t\"itle' onclick='x")"#).html
        #expect(!html.contains(#"" onmouseover"#))
        #expect(!html.contains("' onclick"))
        #expect(!html.contains(#"="alert"#))
        let image = render(#"![a"b](https://x.example/i.png "x\" onerror=\"y")"#).html
        #expect(image.contains(#"alt="a&quot;b""#))
        #expect(!image.contains(#"" onerror"#))
    }

    // MARK: - Performance

    @Test func aLargeReadmeRendersQuickly() {
        let markdown = Self.largeReadme(lines: 5_000)
        _ = render(markdown)
        let clock = ContinuousClock()
        var best = Duration.seconds(10)
        for _ in 0..<5 {
            let elapsed = clock.measure { _ = render(markdown) }
            best = min(best, elapsed)
        }
        let ms = Double(best.components.attoseconds) / 1e15 + Double(best.components.seconds) * 1000
        print("MarkdownHTML: 5,000-line README rendered in \(String(format: "%.1f", ms)) ms (best of 5)")
        #expect(ms < 100)
    }

    static func largeReadme(lines: Int) -> String {
        let chunk = """
        ## Section heading

        Some *emphasis*, **strong**, `code` and a [link](https://example.com/page).
        - item one
        - [x] item two

        | a | b |
        |---|--:|
        | 1 | 2 |

        ```swift
        func hello(_ name: String) -> Int { return 42 } // comment
        ```

        """
        let per = chunk.split(separator: "\n", omittingEmptySubsequences: false).count - 1
        return String(repeating: chunk, count: lines / per)
    }
}
