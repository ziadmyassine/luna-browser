import Foundation

/// Domain normalisation for `if-domain`/`unless-domain` (§17.1).
///
/// WebKit requires those entries to be lowercase ASCII, punycoded, and enforces it:
/// a single `EXAMPLE.com` or `日本.jp` fails the whole list with "Domains must be lower
/// case ASCII. Use punycode to encode non-ASCII characters." (measured 2026-09-17).
///
/// Foundation will not do this for us, which is the trap. `URL.host()` percent-encodes
/// (`日本.jp` → `%E6%97%A5%E6%9C%AC.jp`) and `URLComponents.host` actively decodes
/// punycode back to Unicode (`xn--wgv71a.jp` → `日本.jp`), so routing a domain through
/// either of them produces a rule WebKit rejects. Hence RFC 3492 here, ~50 lines, tested
/// against the RFC's own vectors.
enum Punycode {

    private static let base = 36, tmin = 1, tmax = 26, skew = 38, damp = 700
    private static let initialBias = 72, initialN = 128
    private static let delimiter: Character = "-"

    /// Lowercases and punycodes a domain so WebKit will accept it.
    ///
    /// Returns nil for anything that cannot become a domain — empty input, a label that
    /// will not encode. Callers drop those rules: a rule WebKit rejects costs the
    /// other 149,999 in the list, so silence here is cheaper than optimism.
    static func asciiDomain(_ domain: String) -> String? {
        // A leading `*` is WebKit's own "this domain and its subdomains" marker and a
        // leading `.` appears in filter lists; neither is part of a label.
        var prefix = ""
        var rest = Substring(domain)
        if rest.hasPrefix("*") { prefix = "*"; rest = rest.dropFirst() }
        if rest.hasPrefix(".") { rest = rest.dropFirst() }
        // Trailing dot is the DNS root; WebKit accepts it but it is never what a filter
        // list means, and it would make an otherwise-identical domain a second entry.
        while rest.hasSuffix(".") { rest = rest.dropLast() }
        guard !rest.isEmpty else { return nil }

        var labels: [String] = []
        for label in rest.lowercased().split(separator: ".", omittingEmptySubsequences: false) {
            guard !label.isEmpty else { return nil }
            if label.allSatisfy(\.isASCII) {
                // A port is legal in `if-domain`; other non-host characters are not, and
                // a rule carrying one is a parse failure we should not pass on.
                guard label.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == ":" })
                else { return nil }
                labels.append(String(label))
            } else {
                guard let encoded = encode(String(label)) else { return nil }
                labels.append("xn--" + encoded)
            }
        }
        return prefix + labels.joined(separator: ".")
    }

    // swiftlint:disable identifier_name
    /// RFC 3492 §6.3, the encoding half. Input is one label, already lowercased.
    ///
    /// `n`, `q`, `k`, `t` and `delta` are the RFC's own names. Renaming them to satisfy a
    /// style rule would make this impossible to check against the specification, which is
    /// the only way anyone will ever verify it.
    static func encode(_ input: String) -> String? {
        let scalars = Array(input.unicodeScalars)
        var output = String(String.UnicodeScalarView(scalars.filter { $0.isASCII }))
        let basicCount = output.unicodeScalars.count
        if basicCount > 0 { output.append(delimiter) }

        var handled = basicCount
        var n = initialN
        var delta = 0
        var bias = initialBias

        while handled < scalars.count {
            // The next code point to encode: the smallest one we have not reached yet.
            guard let next = scalars.filter({ $0.value >= UInt32(n) }).map({ Int($0.value) }).min() else { return nil }
            // Overflow here means a label no DNS will ever carry; refusing beats wrapping.
            let (scaled, overflow) = (next - n).multipliedReportingOverflow(by: handled + 1)
            guard !overflow else { return nil }
            delta += scaled
            n = next

            for scalar in scalars {
                let value = Int(scalar.value)
                if value < n { delta += 1 }
                guard value == n else { continue }
                var q = delta
                var k = base
                while true {
                    let t = k <= bias ? tmin : min(max(k - bias, tmin), tmax)
                    if q < t { break }
                    output.append(digit(t + (q - t) % (base - t)))
                    q = (q - t) / (base - t)
                    k += base
                }
                output.append(digit(q))
                bias = adapt(delta: delta, numPoints: handled + 1, firstTime: handled == basicCount)
                delta = 0
                handled += 1
            }
            delta += 1
            n += 1
        }
        return output.isEmpty ? nil : output
    }

    // swiftlint:enable identifier_name

    private static func adapt(delta: Int, numPoints: Int, firstTime: Bool) -> Int {
        var delta = firstTime ? delta / damp : delta / 2
        delta += delta / numPoints
        var shift = 0
        while delta > ((base - tmin) * tmax) / 2 {
            delta /= base - tmin
            shift += base
        }
        return shift + (base - tmin + 1) * delta / (delta + skew)
    }

    /// 0…25 → a…z, 26…35 → 0…9. Lowercase only: WebKit rejects the uppercase form.
    private static func digit(_ value: Int) -> Character {
        value < 26
            ? Character(UnicodeScalar(UInt8(value) + UInt8(ascii: "a")))
            : Character(UnicodeScalar(UInt8(value - 26) + UInt8(ascii: "0")))
    }
}
