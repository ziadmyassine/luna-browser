import Foundation

/// The last pass over every text a tool returns. The page scripts already
/// keep password, card and one-time-code values out of what they read; this
/// catches the same secrets arriving by any other route — `javascript`, the
/// console, a URL in a tab's address, text a page prints.
///
/// It errs toward hiding. A value wrongly hidden costs the agent a detail it
/// can ask the user for; a token wrongly shown is in a model's context, and
/// whatever logs that keeps, for good.
public enum ControlRedactor {

    public static let hidden = "[hidden]"

    public static func scrub(_ text: String) -> String {
        var text = text
        for (pattern, template) in rules {
            text = pattern.stringByReplacingMatches(
                in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template
            )
        }
        return cards(in: text)
    }

    /// Header names whose value is a credential whatever it looks like.
    private static let headers = "authorization|proxy-authorization|cookie|set-cookie|x-api-key|api-key|x-auth-token"
        + "|x-csrf-token|x-xsrf-token|x-amz-security-token"

    /// A parameter or cookie whose name ends in one of these carries a secret:
    /// `token`, `access_token`, `client_secret`, `sessionid`, `code`.
    private static let secretNames = "token|secret|session|sessionid|sessid|sid|password|passwd|pwd|csrf|xsrf|jwt"
        + "|signature|sig|apikey|api_key|api-key|access_key|auth|code|otp|pin|cvv|cvc"

    private static let rules: [(NSRegularExpression, String)] = [
        // `Cookie: …`, `"x-api-key": "…"`, to the end of the line or the quote.
        (#"(?im)(["']?\b(?:\#(headers))["']?\s*[:=]\s*["']?)[^"'\r\n]+"#, "$1\(hidden)"),
        (#"(?i)\bbearer\s+(?=[A-Za-z0-9._~+/=-]*[0-9_.~+/=-])[A-Za-z0-9._~+/=-]{6,}"#, "Bearer \(hidden)"),
        (#"\beyJ[A-Za-z0-9_-]{5,}\.[A-Za-z0-9_-]{5,}\.[A-Za-z0-9_-]*"#, hidden),
        // `?token=…`, `; sessionid=…` in a cookie string, `"access_token": "…"` in JSON.
        (#"(?im)((?:^|[?&;#\s,{"'])[A-Za-z0-9_.-]*?(?:\#(secretNames))=)[^&;#\s"'<>]+"#, "$1\(hidden)"),
        (#"(?i)(["'][A-Za-z0-9_.-]*?(?:\#(secretNames))["']\s*:\s*["'])[^"']+"#, "$1\(hidden)")
    ].map { pattern, template in
        // swiftlint:disable:next force_try
        (try! NSRegularExpression(pattern: pattern), template)
    }

    /// Runs of 13–19 digits, optionally grouped by single spaces or dashes,
    /// that pass the Luhn check — which an order or tracking number of the
    /// same length does nine times in ten not.
    private static let cardRun = try? NSRegularExpression(pattern: #"(?<![\d-])\d(?:[ -]?\d){12,18}(?![\d-])"#)

    private static func cards(in text: String) -> String {
        guard let cardRun else { return text }
        let ns = text as NSString
        var result = text
        for match in cardRun.matches(in: text, range: NSRange(location: 0, length: ns.length)).reversed() {
            let digits = ns.substring(with: match.range).filter(\.isNumber)
            guard (13 ... 19).contains(digits.count), luhn(digits),
                  let range = Range(match.range, in: result) else { continue }
            result.replaceSubrange(range, with: hidden)
        }
        return result
    }

    static func luhn(_ digits: String) -> Bool {
        var sum = 0
        for (index, character) in digits.reversed().enumerated() {
            guard var digit = character.wholeNumberValue else { return false }
            if index % 2 == 1 {
                digit *= 2
                if digit > 9 { digit -= 9 }
            }
            sum += digit
        }
        return sum % 10 == 0
    }
}
