//
//  PasswordGeneratorTests.swift
//  LunaTests
//
//  §14.5. The rules parser is tested harder than the generator because a
//  mis-parsed rule set produces a password the *site* rejects, and the user
//  discovers that after Luna has offered to save it.
//

import XCTest
@testable import BrowserKit
@testable import Luna

final class PasswordGeneratorTests: XCTestCase {

    // MARK: - Generating

    func testDefaultPasswordIsLongAndMixed() {
        let password = PasswordGenerator.generate()
        XCTAssertEqual(password.count, PasswordGenerator.defaultLength)
        XCTAssertTrue(password.contains(where: \.isLowercase))
        XCTAssertTrue(password.contains(where: \.isUppercase))
        XCTAssertTrue(password.contains(where: \.isNumber))
    }

    func testPasswordsDifferEveryTime() {
        let generated = Set((0 ..< 50).map { _ in PasswordGenerator.generate() })
        XCTAssertEqual(generated.count, 50, "a repeat in 50 draws means the RNG is not random")
    }

    /// The length clamp is the one that actually bites: a bank with
    /// `maxlength: 16` silently truncates anything longer, and the saved
    /// password then does not match the stored one.
    func testHonoursMaxLength() {
        let rules = PasswordGenerator.Rules(minLength: 8, maxLength: 12)
        for _ in 0 ..< 25 {
            XCTAssertLessThanOrEqual(PasswordGenerator.generate(rules: rules).count, 12)
        }
    }

    func testHonoursMinLength() {
        let rules = PasswordGenerator.Rules(minLength: 32, maxLength: 64)
        XCTAssertGreaterThanOrEqual(PasswordGenerator.generate(rules: rules).count, 32)
    }

    func testDrawsOnlyFromTheAllowedSet() {
        let rules = PasswordGenerator.Rules(
            minLength: 20, maxLength: 20, required: [.digit], allowed: [.digit]
        )
        XCTAssertTrue(PasswordGenerator.generate(rules: rules).allSatisfy(\.isNumber))
    }

    func testHonoursMaxConsecutive() {
        let rules = PasswordGenerator.Rules(
            minLength: 40, maxLength: 40,
            required: [.literal("ab")], allowed: [.literal("ab")], maxConsecutive: 2
        )
        for _ in 0 ..< 20 {
            let password = PasswordGenerator.generate(rules: rules)
            XCTAssertFalse(password.contains("aaa"), password)
            XCTAssertFalse(password.contains("bbb"), password)
        }
    }

    /// An unsatisfiable rule set must still produce a usable password rather
    /// than an empty field or a hang.
    func testImpossibleRulesFallBackRatherThanSpin() {
        let rules = PasswordGenerator.Rules(
            minLength: 4, maxLength: 4,
            required: [.upper, .lower, .digit, .special], allowed: [.literal("a")]
        )
        XCTAssertFalse(PasswordGenerator.generate(rules: rules).isEmpty)
    }

    // MARK: - Parsing Apple's `passwordrules`

    func testParsesLengthsAndClasses() {
        let rules = PasswordGenerator.parse("minlength: 12; maxlength: 20; required: lower, upper; required: digit;")
        XCTAssertEqual(rules?.minLength, 12)
        XCTAssertEqual(rules?.maxLength, 20)
        XCTAssertEqual(rules?.required, [.lower, .upper, .digit])
    }

    /// A bracketed literal may contain commas, so it cannot be found by
    /// splitting the clause on them.
    func testParsesBracketedLiteralContainingCommas() {
        let rules = PasswordGenerator.parse("allowed: [-(),.&@]; required: lower;")
        // The union, not the literal alone: Apple's grammar implicitly allows
        // whatever is required, so `lower` belongs in the pool too.
        XCTAssertEqual(rules?.allowed, [.lower, .literal("-(),.&@")])
    }

    /// The shape that exposed the union bug: required classes plus a narrow
    /// `allowed` symbol set. Read without the union it is unsatisfiable, and
    /// the generator silently abandons the site's `maxlength`.
    func testRequiredClassesAreImplicitlyAllowed() {
        let rules = PasswordGenerator.parse(
            "minlength: 8; maxlength: 12; required: lower; required: digit; allowed: [!@#];"
        )
        XCTAssertEqual(rules?.allowed, [.lower, .digit, .literal("!@#")])
        for _ in 0 ..< 25 {
            let password = PasswordGenerator.generate(rules: rules!)
            XCTAssertLessThanOrEqual(password.count, 12, "fell back and lost the site's maxlength")
            XCTAssertTrue(password.contains(where: \.isLowercase))
            XCTAssertTrue(password.contains(where: \.isNumber))
        }
    }

    func testParsesMaxConsecutive() {
        XCTAssertEqual(PasswordGenerator.parse("max-consecutive: 2; required: digit;")?.maxConsecutive, 2)
    }

    /// Unknown directives are ignored rather than failing the parse: the
    /// grammar grows by addition, and a site using a newer key should still
    /// get the length it asked for.
    func testUnknownDirectivesAreIgnored() {
        let rules = PasswordGenerator.parse("minlength: 16; sparkle: yes; required: digit;")
        XCTAssertEqual(rules?.minLength, 16)
    }

    func testNothingUsableReturnsNil() {
        XCTAssertNil(PasswordGenerator.parse(""))
        XCTAssertNil(PasswordGenerator.parse("nonsense"))
        XCTAssertNil(PasswordGenerator.parse("sparkle: yes;"))
    }

    /// `required:` with no `allowed:` means "and nothing else", so the pool
    /// must not silently widen to the default.
    func testRequiredWithoutAllowedNarrowsThePool() {
        let rules = PasswordGenerator.parse("required: digit;")
        XCTAssertEqual(rules?.allowed, [.digit])
        XCTAssertTrue(PasswordGenerator.generate(rules: rules!).allSatisfy(\.isNumber))
    }

    /// A site stating only a maximum still wants a strong password inside it,
    /// and must not be handed one longer than it accepts.
    func testMaxLengthAloneStillProducesSomethingValid() {
        let rules = PasswordGenerator.parse("maxlength: 10;")
        XCTAssertNotNil(rules)
        XCTAssertLessThanOrEqual(PasswordGenerator.generate(rules: rules!).count, 10)
    }

    /// Round trip against a rule string in the shape sites actually ship.
    func testRealWorldRuleString() {
        let attribute = "minlength: 8; maxlength: 32; required: lower; required: upper; "
            + "required: digit; allowed: [!@#$%^&*];"
        let rules = PasswordGenerator.parse(attribute)
        XCTAssertNotNil(rules)
        let password = PasswordGenerator.generate(rules: rules!)
        XCTAssertGreaterThanOrEqual(password.count, 8)
        XCTAssertLessThanOrEqual(password.count, 32)
        XCTAssertTrue(password.contains(where: \.isLowercase))
        XCTAssertTrue(password.contains(where: \.isUppercase))
        XCTAssertTrue(password.contains(where: \.isNumber))
    }

    // MARK: - The RNG

    func testRandomIndexStaysInRangeAndCoversIt() {
        var seen = Set<Int>()
        for _ in 0 ..< 2000 {
            let index = PasswordGenerator.randomIndex(below: 10)
            XCTAssertTrue((0 ..< 10).contains(index))
            seen.insert(index)
        }
        XCTAssertEqual(seen.count, 10, "2000 draws that miss a value are not uniform")
    }
}
