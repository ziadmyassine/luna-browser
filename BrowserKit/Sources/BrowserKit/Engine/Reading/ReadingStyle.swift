import Foundation

/// The stylesheet every reading page wears: Reader's article and a rendered
/// Markdown document, anything inside `.luna-reading`.
///
/// Preferences are not baked in. The sheet maps the root's `data-luna-*`
/// attributes and `--luna-reading-size` to values, so a change is the page
/// script setting an attribute rather than a new sheet — and a page the script
/// has not touched yet reads as the defaults.
public enum ReadingStyle {

    /// The fixed page colours: every one but Match, which follows the system.
    static var fixedPages: [ReadingPreferences.Page] { ReadingPreferences.Page.allCases.filter { $0 != .match } }

    /// Each fixed page's `--luna-reading-<page>-<part>`, and the surface
    /// variable it stands in for.
    private static let pageParts = [
        ("bg", "--luna-surface-base"), ("text", "--luna-text-primary"),
        ("text2", "--luna-text-secondary"), ("text3", "--luna-text-tertiary"),
        ("hairline", "--luna-line-hairline"), ("border", "--luna-line-border"),
        ("wash", "--luna-surface-hover")
    ]

    /// Classes a highlighter marks code with, each read as `--luna-syntax-<class>`.
    static let syntaxTokens = ["kw", "str", "com", "fn", "num"]

    /// What this sheet needs from the palette beyond what the internal pages do.
    static var paletteVariables: [String] {
        fixedPages.flatMap { page in pageParts.map { "--luna-reading-\(page.rawValue)-\($0.0)" } }
            + syntaxTokens.map { "--luna-syntax-\($0)" }
    }

    /// A rendered Markdown document's own parts: the outline, the copy
    /// buttons, and the Source view that `data-view` switches to.
    private static let markdownCSS =
        "body:not([data-view=\"source\"]) .luna-source,body[data-view=\"source\"] .luna-reading{display:none}" +
        ":root[data-luna-outline=\"false\"] .luna-outline{display:none}" +
        ".luna-outline{position:fixed;top:64px;left:24px;width:200px;max-height:calc(100vh - 128px);overflow:auto;" +
        "font:var(--luna-size-row)/1.4 -apple-system,BlinkMacSystemFont,sans-serif}" +
        ".luna-outline p{margin:0 0 8px 10px;color:var(--luna-text-tertiary);font-size:var(--luna-size-label)}" +
        ".luna-outline ul{list-style:none;margin:0;padding:0}" +
        ".luna-outline a{display:block;padding:4px 10px;border-radius:var(--luna-row-radius);" +
        "color:var(--luna-text-secondary);text-decoration:none;transition:background var(--luna-motion-hover)}" +
        ".luna-outline .h3 a{padding-left:22px}" +
        ".luna-outline a:hover,.luna-outline a[aria-current]{background:var(--luna-surface-hover);" +
        "color:var(--luna-text-primary)}" +
        // Below this the outline would sit over the text column.
        "@media (max-width:1200px){.luna-outline{display:none}}" +
        ".luna-code{position:relative}" +
        ".luna-copy{position:absolute;top:8px;right:8px;border:0;padding:4px 8px;" +
        "border-radius:var(--luna-row-radius);background:transparent;color:var(--luna-text-secondary);" +
        "font:var(--luna-size-label) -apple-system,BlinkMacSystemFont,sans-serif;" +
        "transition:background var(--luna-motion-hover),transform var(--luna-motion-hover)}" +
        ".luna-copy::before{content:\"Copy\"}" +
        ".luna-copy:hover{background:var(--luna-surface-hover)}" +
        ".luna-copy:active{background:var(--luna-surface-selected)}" +
        editCSS

    /// Source and Edit. Edit's textarea text is transparent over a backdrop
    /// drawing the same text highlighted, so both must lay a line out
    /// identically: one font, one padding, one wrap. The backdrop sets the
    /// height and the textarea is stretched over it, so the column scrolls as one.
    private static let editCSS =
        "body:not([data-view=\"edit\"]) .luna-edit,body[data-view=\"edit\"]>.luna-reading," +
        "body[data-view=\"edit\"] .luna-outline{display:none}" +
        ".luna-edit{display:grid;grid-template-columns:1fr 1fr;height:100vh}" +
        ".luna-editor,.luna-preview{overflow:auto}" +
        ".luna-editor{border-right:var(--luna-hairline) solid var(--luna-line-hairline)}" +
        ".luna-stack{position:relative;min-height:100%}" +
        ".luna-source,.luna-backdrop,.luna-input{box-sizing:border-box;margin:0;" +
        "font:13px/1.6 ui-monospace,Menlo,monospace;white-space:pre-wrap;overflow-wrap:break-word;tab-size:4;" +
        "color:var(--luna-text-primary)}" +
        ".luna-source{padding:64px 24px 160px;max-width:var(--luna-reading-width);margin:0 auto}" +
        ".luna-backdrop,.luna-input{padding:24px 24px 50vh}" +
        ".luna-backdrop{position:relative;pointer-events:none}" +
        ".src-line{min-height:1.6em}" +
        ".md-mark{color:var(--luna-text-tertiary)}" +
        syntaxTokens.map { ".luna-source .tok-\($0),.luna-backdrop .tok-\($0){color:var(--luna-syntax-\($0))}" }.joined() +
        ".luna-band{position:absolute;left:0;right:0;background:var(--luna-surface-hover);pointer-events:none}" +
        ".luna-input{position:absolute;top:0;left:0;width:100%;height:100%;overflow:hidden;resize:none;" +
        "border:0;outline:0;background:transparent;color:transparent;caret-color:var(--luna-text-primary)}" +
        ".luna-preview .luna-reading{padding-top:24px}"

    public static func css(palette: String) -> String {
        let defaults = ReadingPreferences()
        let widths = ReadingPreferences.Width.allCases.map {
            ":root[data-luna-width=\"\($0.rawValue)\"]{--luna-reading-width:\($0.points)px}"
        }
        let typefaces = ReadingPreferences.Typeface.allCases.map {
            ":root[data-luna-typeface=\"\($0.rawValue)\"]{--luna-reading-font:\($0.stack)}"
        }
        // A fixed page swaps the surface and text variables for its own and
        // pins `color-scheme`, which is what `--luna-syntax-*`'s `light-dark()`
        // picks by. Outranks the palette's `:root` blocks by specificity.
        let pages = fixedPages.map { page in
            let scheme = page == .night ? "dark" : "light"
            let swaps = pageParts.map { "\($0.1):var(--luna-reading-\(page.rawValue)-\($0.0))" }
            return ":root[data-luna-page=\"\(page.rawValue)\"]{color-scheme:\(scheme);\(swaps.joined(separator: ";"))}"
        }
        let syntax = syntaxTokens.map { ".luna-reading .tok-\($0){color:var(--luna-syntax-\($0))}" }
        return palette +
            ":root{color-scheme:light dark}" +
            "html,body{margin:0;padding:0;background:var(--luna-surface-base)}" +
            ":root{--luna-reading-width:\(defaults.width.points)px;--luna-reading-size:\(defaults.size)px;" +
            "--luna-reading-font:\(defaults.typeface.stack)}" +
            widths.joined() + typefaces.joined() + pages.joined() +
            ".luna-reading{box-sizing:border-box;max-width:var(--luna-reading-width);margin:0 auto;" +
            "padding:64px 24px 160px;font:var(--luna-reading-size)/1.65 var(--luna-reading-font);" +
            "color:var(--luna-text-primary);overflow-wrap:break-word}" +
            ".luna-reading .luna-site{font:500 var(--luna-size-label)/1.4 -apple-system,BlinkMacSystemFont,sans-serif;" +
            "letter-spacing:.06em;text-transform:uppercase;color:var(--luna-text-tertiary);margin:0 0 12px}" +
            ".luna-reading .luna-title{font:700 34px/1.2 -apple-system,BlinkMacSystemFont,sans-serif;" +
            "letter-spacing:-.01em;margin:0 0 40px}" +
            ".luna-reading h2,.luna-reading h3,.luna-reading h4{font-family:-apple-system,BlinkMacSystemFont,sans-serif;" +
            "line-height:1.3;margin:1.8em 0 .6em}" +
            ".luna-reading h2{font-size:1.35em}.luna-reading h3{font-size:1.15em}.luna-reading h4{font-size:1em}" +
            ".luna-reading p{margin:0 0 1.2em}" +
            ".luna-reading a{color:inherit;text-decoration-color:var(--luna-text-tertiary);text-underline-offset:3px}" +
            ".luna-reading img,.luna-reading video{display:block;max-width:100%;height:auto;margin:1.5em auto;" +
            "border-radius:var(--luna-row-radius)}" +
            ".luna-reading iframe{display:block;width:100%;height:auto;aspect-ratio:16/9;border:0;margin:1.5em 0;" +
            "border-radius:var(--luna-row-radius)}" +
            ".luna-reading figure{margin:1.8em 0}" +
            ".luna-reading figcaption{font:var(--luna-size-row)/1.45 -apple-system,BlinkMacSystemFont,sans-serif;" +
            "color:var(--luna-text-secondary);margin-top:.6em}" +
            ".luna-reading blockquote{margin:1.5em 0;padding-left:1em;border-left:3px solid var(--luna-line-border);" +
            "color:var(--luna-text-secondary)}" +
            ".luna-reading pre,.luna-reading code{font-family:ui-monospace,Menlo,monospace;font-size:.85em}" +
            ".luna-reading pre{background:var(--luna-surface-hover);padding:14px;" +
            "border-radius:var(--luna-row-radius);overflow:auto}" +
            ".luna-reading table{border-collapse:collapse;width:100%;font-size:.9em}" +
            ".luna-reading td,.luna-reading th{border-bottom:var(--luna-hairline) solid var(--luna-line-hairline);" +
            "padding:6px 8px;text-align:left}" +
            ".luna-reading hr{border:0;border-top:var(--luna-hairline) solid var(--luna-line-hairline);margin:2em 0}" +
            syntax.joined() +
            // Reader strips buttons from the article, so this reaches only the
            // reading surface's own controls.
            ".luna-reading button:active{transform:scale(var(--luna-press-swell))}" +
            markdownCSS
    }
}
