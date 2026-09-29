import Foundation

/// The stylesheet every reading page wears: Reader's article and a rendered
/// Markdown document, anything inside `.luna-reading`.
///
/// Preferences are not baked in. The sheet maps the root's `data-luna-*`
/// attributes and `--luna-reading-size` to values, so a change is the page
/// script setting an attribute rather than a new sheet — and a page the script
/// has not touched yet reads as the defaults.
public enum ReadingStyle {

    public static func css(palette: String) -> String {
        let defaults = ReadingPreferences()
        let widths = ReadingPreferences.Width.allCases.map {
            ":root[data-luna-width=\"\($0.rawValue)\"]{--luna-reading-width:\($0.points)px}"
        }
        let typefaces = ReadingPreferences.Typeface.allCases.map {
            ":root[data-luna-typeface=\"\($0.rawValue)\"]{--luna-reading-font:\($0.stack)}"
        }
        return palette +
            ":root{color-scheme:light dark}" +
            "html,body{margin:0;padding:0;background:var(--luna-surface-base)}" +
            ":root{--luna-reading-width:\(defaults.width.points)px;--luna-reading-size:\(defaults.size)px;" +
            "--luna-reading-font:\(defaults.typeface.stack)}" +
            widths.joined() + typefaces.joined() +
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
            ".luna-reading hr{border:0;border-top:var(--luna-hairline) solid var(--luna-line-hairline);margin:2em 0}"
    }
}
