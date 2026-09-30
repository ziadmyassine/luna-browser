@testable import BrowserKit
import Foundation
import Testing

/// The reading surface Reader and the Markdown reader share: the preferences
/// and the stylesheet built from them. The live page half is in `PageToolsTests`.
@Suite("Reading preferences")
struct ReadingPreferencesTests {

    @Test func defaultsAreSerifNineteenMediumMatch() {
        let preferences = ReadingPreferences.stored(in: scratchDefaults())
        #expect(preferences == ReadingPreferences())
        #expect(preferences.typeface == .serif)
        #expect(preferences.size == 19)
        #expect(preferences.width == .medium)
        #expect(preferences.page == .match)
        #expect(preferences.outline)
        #expect(preferences.wrap)
    }

    @Test func sizeIsClampedToFourteenThroughTwentyEight() {
        var preferences = ReadingPreferences()
        preferences.size = 4
        #expect(preferences.size == 14)
        preferences.size = 90
        #expect(preferences.size == 28)

        let defaults = scratchDefaults()
        defaults.set(99, forKey: ReadingPreferences.Key.size)
        #expect(ReadingPreferences.stored(in: defaults).size == 28)
    }

    @Test func everyKeyRoundTrips() {
        let defaults = scratchDefaults()
        var preferences = ReadingPreferences()
        preferences.typeface = .mono
        preferences.size = 22
        preferences.width = .wide
        preferences.page = .sepia
        preferences.outline = false
        preferences.wrap = false
        preferences.store(in: defaults)
        #expect(ReadingPreferences.stored(in: defaults) == preferences)

        #expect(defaults.string(forKey: "reading.typeface") == "mono")
        #expect(defaults.integer(forKey: "reading.size") == 22)
        #expect(defaults.string(forKey: "reading.width") == "wide")
        #expect(defaults.string(forKey: "reading.page") == "sepia")
        #expect(defaults.object(forKey: "reading.outline") as? Bool == false)
        #expect(defaults.object(forKey: "reading.wrap") as? Bool == false)
    }
}

@Suite("Reading style")
struct ReadingStyleTests {

    @Test func widthsAreFiveEightySixEightyEightTwenty() {
        #expect(ReadingPreferences.Width.narrow.points == 580)
        #expect(ReadingPreferences.Width.medium.points == 680)
        #expect(ReadingPreferences.Width.wide.points == 820)
        let css = ReadingStyle.css(palette: "")
        #expect(css.contains(#":root[data-luna-width="narrow"]{--luna-reading-width:580px}"#))
        #expect(css.contains(#":root[data-luna-width="wide"]{--luna-reading-width:820px}"#))
        #expect(css.contains("--luna-reading-width:680px"))
    }

    /// Reader's stylesheet before it moved onto the shared surface, verbatim.
    /// At default preferences the shared sheet must still carry every rule.
    private static let readerSheet =
        ":root{color-scheme:light dark}" +
        "html,body{margin:0;padding:0;background:var(--luna-surface-base)}" +
        "#luna-reader{box-sizing:border-box;max-width:680px;margin:0 auto;padding:64px 24px 160px;" +
        "font:19px/1.65 ui-serif,\"New York\",Georgia,serif;color:var(--luna-text-primary);overflow-wrap:break-word}" +
        "#luna-reader .luna-site{font:500 var(--luna-size-label)/1.4 -apple-system,BlinkMacSystemFont,sans-serif;" +
        "letter-spacing:.06em;text-transform:uppercase;color:var(--luna-text-tertiary);margin:0 0 12px}" +
        "#luna-reader .luna-title{font:700 34px/1.2 -apple-system,BlinkMacSystemFont,sans-serif;" +
        "letter-spacing:-.01em;margin:0 0 40px}" +
        "#luna-reader h2,#luna-reader h3,#luna-reader h4{font-family:-apple-system,BlinkMacSystemFont,sans-serif;" +
        "line-height:1.3;margin:1.8em 0 .6em}" +
        "#luna-reader h2{font-size:1.35em}#luna-reader h3{font-size:1.15em}#luna-reader h4{font-size:1em}" +
        "#luna-reader p{margin:0 0 1.2em}" +
        "#luna-reader a{color:inherit;text-decoration-color:var(--luna-text-tertiary);text-underline-offset:3px}" +
        "#luna-reader img,#luna-reader video{display:block;max-width:100%;height:auto;margin:1.5em auto;" +
        "border-radius:var(--luna-row-radius)}" +
        "#luna-reader iframe{display:block;width:100%;height:auto;aspect-ratio:16/9;border:0;margin:1.5em 0;" +
        "border-radius:var(--luna-row-radius)}" +
        "#luna-reader figure{margin:1.8em 0}" +
        "#luna-reader figcaption{font:var(--luna-size-row)/1.45 -apple-system,BlinkMacSystemFont,sans-serif;" +
        "color:var(--luna-text-secondary);margin-top:.6em}" +
        "#luna-reader blockquote{margin:1.5em 0;padding-left:1em;border-left:3px solid var(--luna-line-border);" +
        "color:var(--luna-text-secondary)}" +
        "#luna-reader pre,#luna-reader code{font-family:ui-monospace,Menlo,monospace;font-size:.85em}" +
        "#luna-reader pre{background:var(--luna-surface-hover);padding:14px;" +
        "border-radius:var(--luna-row-radius);overflow:auto}" +
        "#luna-reader table{border-collapse:collapse;width:100%;font-size:.9em}" +
        "#luna-reader td,#luna-reader th{border-bottom:var(--luna-hairline) solid var(--luna-line-hairline);" +
        "padding:6px 8px;text-align:left}" +
        "#luna-reader hr{border:0;border-top:var(--luna-hairline) solid var(--luna-line-hairline);margin:2em 0}"

    @Test func everyRuleOfTheOldReaderSheetIsStillThere() {
        let css = ReadingStyle.css(palette: "")
        let rules = Self.readerSheet.replacingOccurrences(of: "#luna-reader", with: ".luna-reading")
            .split(separator: "}").map { $0 + "}" }
        for rule in rules where !rule.hasPrefix(".luna-reading{") {
            #expect(css.contains(rule), "missing \(rule)")
        }
        // The article's own box: what preferences drive is now a custom
        // property, whose default is the old value.
        #expect(css.contains(
            ".luna-reading{box-sizing:border-box;max-width:var(--luna-reading-width);margin:0 auto;" +
                "padding:64px 24px 160px;font:var(--luna-reading-size)/1.65 var(--luna-reading-font);" +
                "color:var(--luna-text-primary);overflow-wrap:break-word}"
        ))
        #expect(css.contains(
            ":root{--luna-reading-width:680px;--luna-reading-size:19px;" +
                "--luna-reading-font:ui-serif,\"New York\",Georgia,serif}"
        ))
    }

    /// A fixed page pins its scheme and repaints from its own variables; Match
    /// gets no rule, so it keeps following `prefers-color-scheme`.
    @Test func fixedPagesPinTheirSchemeAndMatchDoesNot() {
        let css = ReadingStyle.css(palette: "")
        #expect(css.contains(#":root[data-luna-page="paper"]{color-scheme:light;"#))
        #expect(css.contains(#":root[data-luna-page="sepia"]{color-scheme:light;"#))
        #expect(css.contains(#":root[data-luna-page="night"]{color-scheme:dark;"#))
        #expect(css.contains("--luna-surface-base:var(--luna-reading-sepia-bg)"))
        #expect(!css.contains(#"data-luna-page="match""#))
        for token in ["kw", "str", "com", "fn", "num"] {
            #expect(css.contains(".luna-reading .tok-\(token){color:var(--luna-syntax-\(token))}"))
        }
    }

    @Test func thePaletteComesFirst() {
        #expect(ReadingStyle.css(palette: ":root{--x:1}").hasPrefix(":root{--x:1}"))
    }
}
