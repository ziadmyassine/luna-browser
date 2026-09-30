import Foundation

/// The languages `SyntaxHighlighter` knows, keyed by the fence names GitHub
/// accepts for them. Keyword lists stop at what a README snippet shows.
extension SyntaxHighlighter.Grammar {

    static func named(_ name: String) -> Self? { byName[name.lowercased()] }

    private static let byName: [String: Self] = {
        let aliases: [(String, Self)] = [
            ("swift", swift),
            ("js javascript jsx mjs cjs ts typescript tsx", javaScript),
            ("py python python3", python),
            ("sh bash zsh shell console shellsession", shell),
            ("json jsonc json5", json),
            ("html xml xhtml svg plist vue", markup),
            ("css scss less", css),
            ("go golang", go),
            ("rs rust", rust),
            ("rb ruby", ruby),
            ("yml yaml", yaml),
            ("c h cpp c++ cc hpp objc objective-c java kotlin kt cs csharp", cFamily)
        ]
        var table: [String: Self] = [:]
        for (names, grammar) in aliases {
            for name in names.split(separator: " ") { table[String(name)] = grammar }
        }
        return table
    }()

    private static func words(_ list: String) -> Set<String> {
        Set(list.split(whereSeparator: \.isWhitespace).map(String.init))
    }

    static let swift = Self(
        keywords: words("""
        actor any as associatedtype async await break case catch class continue default defer deinit do else enum
        extension fallthrough false fileprivate final for func guard if import in init inout internal is lazy let
        mutating nil nonisolated open operator override private protocol public repeat rethrows return self Self
        some static struct subscript super switch throw throws true try typealias var weak where while
        """),
        quotes: [UInt8(ascii: "\"")], tripleQuotes: true
    )

    static let javaScript = Self(
        keywords: words("""
        abstract as async await break case catch class const continue debugger declare default delete do else enum
        export extends false finally for from function get if implements import in instanceof interface let new null
        of private protected public readonly return set static super switch this throw true try type typeof undefined
        var void while yield
        """),
        multilineQuotes: [UInt8(ascii: "`")]
    )

    static let python = Self(
        keywords: words("""
        and as assert async await break class continue def del elif else except False finally for from global if
        import in is lambda None nonlocal not or pass raise return self True try while with yield
        """),
        lineComments: ["#"], blockComment: nil, tripleQuotes: true
    )

    static let shell = Self(
        keywords: words("""
        case do done elif else esac exit export fi for function if in local readonly return select source then
        until while
        """),
        lineComments: ["#"], blockComment: nil
    )

    static let json = Self(keywords: words("true false null"))

    static let markup = Self(keywords: [], lineComments: [], blockComment: ("<!--", "-->"), markup: true)

    static let css = Self(keywords: words("important inherit initial unset none auto"), lineComments: [], atKeywords: true)

    static let go = Self(
        keywords: words("""
        break case chan const continue default defer else fallthrough false for func go goto if import interface
        iota map nil package range return select struct switch true type var
        """),
        multilineQuotes: [UInt8(ascii: "`")]
    )

    // Rust's apostrophe is as often a lifetime (`'a`) as a char, so only
    // double quotes open a string.
    static let rust = Self(
        keywords: words("""
        as async await break const continue crate dyn else enum extern false fn for if impl in let loop match mod
        move mut pub ref return self Self static struct super trait true type unsafe use where while
        """),
        quotes: [UInt8(ascii: "\"")]
    )

    static let ruby = Self(
        keywords: words("""
        alias and begin break case class def defined do else elsif end ensure false for if in module next nil not
        or redo rescue retry return self super then true undef unless until when while yield
        """),
        lineComments: ["#"], blockComment: nil
    )

    static let yaml = Self(
        keywords: words("true false null yes no on off True False Null"),
        lineComments: ["#"], blockComment: nil
    )

    static let cFamily = Self(
        keywords: words("""
        abstract auto bool break case catch char class const constexpr continue default delete do double else enum
        extends extern false final float for fun if implements import include int interface long namespace new null
        nullptr override package private protected public return short signed sizeof static struct super switch
        template this throw true try typedef typename union unsigned using val var virtual void volatile when while
        """)
    )
}
