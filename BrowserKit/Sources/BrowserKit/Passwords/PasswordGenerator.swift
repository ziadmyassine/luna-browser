import Foundation

/// §14.5 — a strong password, generated to the site's own rules when it states
/// them.
///
/// **Why the rules matter.** The failure this avoids is not aesthetic: a
/// generator that ignores a bank's "no more than 16 characters, no symbols"
/// produces a password the form rejects *after* Luna has offered to save it,
/// and the user ends up with a saved credential that does not work. Apple
/// publishes the `passwordrules` attribute for exactly this, Safari honours it,
/// and every site that bothers to set it is a site with a picky validator.
///
/// The grammar is Apple's "Password Rules" syntax, e.g.
/// `minlength: 12; maxlength: 20; required: lower, upper; required: digit;
/// allowed: [-().&@]; max-consecutive: 2;`
public enum PasswordGenerator {

    /// Luna's own default when a site says nothing: 20 characters drawn from
    /// upper, lower, digit and a conservative symbol set.
    ///
    /// 20 rather than a round 16 because the cost of a longer password is zero
    /// when nobody types it, and the symbol set is conservative because the
    /// most common silent rejection is a site that accepts `!` and not `\``.
    public static let defaultLength = 20

    public struct Rules: Equatable, Sendable {
        public var minLength: Int
        public var maxLength: Int
        /// Character sets the password must draw at least one character from.
        public var required: [CharacterSetSpec]
        /// The pool to draw the remainder from. Empty means "the union of
        /// `required`", which is what the grammar implies when a site states
        /// requirements and no allowance.
        public var allowed: [CharacterSetSpec]
        /// `max-consecutive: N` — no character may repeat more than N times in
        /// a row. Zero means unconstrained.
        public var maxConsecutive: Int

        public init(
            minLength: Int = defaultLength,
            maxLength: Int = 64,
            required: [CharacterSetSpec] = [.lower, .upper, .digit],
            allowed: [CharacterSetSpec] = [.lower, .upper, .digit, .special],
            maxConsecutive: Int = 0
        ) {
            self.minLength = minLength
            self.maxLength = maxLength
            self.required = required
            self.allowed = allowed
            self.maxConsecutive = maxConsecutive
        }

        public static let `default` = Rules()
    }

    /// One named class from the grammar, or a literal `[…]` set.
    public enum CharacterSetSpec: Equatable, Sendable {
        case upper, lower, digit, special, asciiPrintable
        case literal(String)

        /// Apple's `special` set. Not "every punctuation character": `<`, `>`
        /// and backslash are left out because they are the ones that get
        /// HTML-escaped, shell-quoted or stripped somewhere between the form
        /// and the database, and a password that survives the round trip is
        /// worth more than four extra symbols of entropy.
        public var characters: String {
            switch self {
            case .upper: "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
            case .lower: "abcdefghijklmnopqrstuvwxyz"
            case .digit: "0123456789"
            case .special: "-!#$%&'()*+,./:;=?@[]^_`{|}~"
            case .asciiPrintable:
                CharacterSetSpec.upper.characters + CharacterSetSpec.lower.characters
                    + CharacterSetSpec.digit.characters + CharacterSetSpec.special.characters
            case let .literal(value): value
            }
        }
    }

    // MARK: - Generating

    /// A password satisfying `rules`.
    ///
    /// Every draw is from `SecRandomCopyBytes` via ``randomIndex(below:)`` —
    /// `Int.random(in:)` uses the system RNG, which is fine for a shuffle and
    /// not what a password should come from.
    public static func generate(rules: Rules = .default) -> String {
        let pool = characters(of: rules.allowed.isEmpty ? rules.required : rules.allowed)
        guard !pool.isEmpty else { return generate(rules: .default) }

        let length = max(rules.minLength, min(rules.maxLength, max(defaultLength, rules.minLength)))

        // Retry rather than repair: a password patched afterwards to satisfy a
        // requirement has a *known* character in a known position, and that is
        // exactly the structure an attacker's mask exploits. Drawing again is
        // cheap and keeps every position uniform.
        for _ in 0 ..< 64 {
            let candidate = draw(length: length, from: pool, maxConsecutive: rules.maxConsecutive)
            if satisfies(candidate, rules: rules) { return candidate }
        }
        // A rule set nothing satisfies in 64 draws is a rule set we cannot
        // honour — a site demanding four classes out of a two-character pool.
        // Luna's own default is a better answer than an empty field.
        return draw(length: max(defaultLength, rules.minLength), from: characters(of: Rules.default.allowed), maxConsecutive: 0)
    }

    private static func draw(length: Int, from pool: [Character], maxConsecutive: Int) -> String {
        var out: [Character] = []
        out.reserveCapacity(length)
        while out.count < length {
            let next = pool[randomIndex(below: pool.count)]
            if maxConsecutive > 0, out.count >= maxConsecutive,
               out.suffix(maxConsecutive).allSatisfy({ $0 == next }) {
                continue
            }
            out.append(next)
        }
        return String(out)
    }

    private static func satisfies(_ candidate: String, rules: Rules) -> Bool {
        for spec in rules.required {
            let set = Set(spec.characters)
            guard candidate.contains(where: { set.contains($0) }) else { return false }
        }
        return candidate.count >= rules.minLength && candidate.count <= rules.maxLength
    }

    private static func characters(of specs: [CharacterSetSpec]) -> [Character] {
        // Deduplicated: a site listing `allowed: lower, ascii-printable` would
        // otherwise weight lowercase letters twice.
        Array(Set(specs.flatMap { Array($0.characters) })).sorted()
    }

    /// Uniform in `0 ..< bound`, from the system CSPRNG.
    ///
    /// Rejection-sampled: taking a random `UInt32` modulo `bound` biases the
    /// low indices whenever `bound` does not divide `2³²`, which for a 70-odd
    /// character pool it never does.
    static func randomIndex(below bound: Int) -> Int {
        precondition(bound > 0)
        let limit = UInt32.max - (UInt32.max % UInt32(bound))
        while true {
            var raw: UInt32 = 0
            let status = withUnsafeMutableBytes(of: &raw) { buffer in
                SecRandomCopyBytes(kSecRandomDefault, buffer.count, buffer.baseAddress!)
            }
            // The CSPRNG failing is not a condition to paper over with a weaker
            // source; on Apple platforms it does not fail.
            precondition(status == errSecSuccess, "SecRandomCopyBytes failed: \(status)")
            if raw < limit { return Int(raw % UInt32(bound)) }
        }
    }

    // MARK: - Parsing the `passwordrules` attribute

    /// Parses Apple's Password Rules syntax. Unknown keys are ignored rather
    /// than treated as an error: the grammar is versioned by addition, and a
    /// site using a directive we have not heard of should still get the
    /// length and the classes it did state.
    ///
    /// - Returns: nil when the string yields nothing usable, so the caller
    ///   falls back to ``Rules/default`` rather than to an empty pool.
    public static func parse(_ attribute: String) -> Rules? {
        var rules = Rules(minLength: 0, maxLength: 0, required: [], allowed: [], maxConsecutive: 0)
        var sawAnything = false

        for clause in attribute.split(separator: ";") {
            let parts = clause.split(separator: ":", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard parts.count == 2 else { continue }
            let key = parts[0].lowercased()
            let value = parts[1]

            switch key {
            case "minlength":
                if let n = Int(value) { rules.minLength = n; sawAnything = true }
            case "maxlength":
                if let n = Int(value) { rules.maxLength = n; sawAnything = true }
            case "max-consecutive":
                if let n = Int(value) { rules.maxConsecutive = n; sawAnything = true }
            case "required":
                let specs = parseSpecs(value)
                if !specs.isEmpty { rules.required += specs; sawAnything = true }
            case "allowed":
                let specs = parseSpecs(value)
                if !specs.isEmpty { rules.allowed += specs; sawAnything = true }
            default:
                continue
            }
        }
        guard sawAnything else { return nil }

        // Fill in what the site did not say. A site that states only
        // `maxlength: 16` still wants a strong password within it, and a site
        // that states only `required:` means "and nothing else is allowed".
        if rules.minLength <= 0 { rules.minLength = min(defaultLength, rules.maxLength > 0 ? rules.maxLength : defaultLength) }
        if rules.maxLength <= 0 { rules.maxLength = max(rules.minLength, 64) }
        if rules.maxLength < rules.minLength { rules.maxLength = rules.minLength }
        // **`required` is implicitly allowed.** Apple's grammar says so, and the
        // common real-world shape depends on it:
        //
        //     required: lower; required: upper; required: digit; allowed: [!@#$%^&*];
        //
        // Read literally, that permits *only* the eight symbols — and then
        // demands a lowercase letter the pool cannot supply, so no password
        // satisfies it and the generator falls back to its own default,
        // quietly ignoring the site's length limits. Taking the union is both
        // what the grammar means and the only reading under which that rule
        // set is satisfiable at all.
        rules.allowed = rules.required + rules.allowed
        if rules.allowed.isEmpty { rules.allowed = Rules.default.allowed }
        return rules
    }

    /// `lower, upper, [-().&@]` → three specs. A bracketed literal may itself
    /// contain commas, so it is scanned rather than split on.
    private static func parseSpecs(_ value: String) -> [CharacterSetSpec] {
        var specs: [CharacterSetSpec] = []
        var token = ""
        var literal: String?

        func flush() {
            let name = token.trimmingCharacters(in: .whitespaces).lowercased()
            token = ""
            guard !name.isEmpty else { return }
            switch name {
            case "upper": specs.append(.upper)
            case "lower": specs.append(.lower)
            case "digit": specs.append(.digit)
            case "special": specs.append(.special)
            case "ascii-printable", "unicode": specs.append(.asciiPrintable)
            default: break
            }
        }

        for character in value {
            if literal != nil {
                if character == "]" {
                    if let body = literal, !body.isEmpty { specs.append(.literal(body)) }
                    literal = nil
                } else {
                    literal?.append(character)
                }
            } else if character == "[" {
                flush()
                literal = ""
            } else if character == "," {
                flush()
            } else {
                token.append(character)
            }
        }
        flush()
        if let body = literal, !body.isEmpty { specs.append(.literal(body)) }
        return specs
    }
}
