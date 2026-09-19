//
//  PublicSuffixTests.swift
//  LunaTests
//
//  §14.3's match rule. These are the tests that matter most in the whole
//  feature: every assertion below that flips from pass to fail is a credential
//  offered to a site that does not own it.
//

import XCTest
import BrowserKit
@testable import Luna

final class PublicSuffixTests: XCTestCase {

    // MARK: - The ordinary case

    func testStripsSubdomains() {
        XCTAssertEqual(PublicSuffix.siteKey(forHost: "www.example.com"), "example.com")
        XCTAssertEqual(PublicSuffix.siteKey(forHost: "a.b.c.example.com"), "example.com")
        XCTAssertEqual(PublicSuffix.siteKey(forHost: "example.com"), "example.com")
    }

    func testIsCaseAndTrailingDotInsensitive() {
        XCTAssertEqual(PublicSuffix.siteKey(forHost: "WWW.Example.COM."), "example.com")
    }

    // MARK: - Multi-label suffixes

    /// The failure this prevents: `bbc.co.uk` and `itv.co.uk` both reducing to
    /// `co.uk`, and one being offered the other's password.
    func testMultiLabelSuffixesDoNotCollapse() {
        XCTAssertEqual(PublicSuffix.siteKey(forHost: "www.bbc.co.uk"), "bbc.co.uk")
        XCTAssertEqual(PublicSuffix.siteKey(forHost: "itv.co.uk"), "itv.co.uk")
        XCTAssertFalse(PublicSuffix.isSameSite("www.bbc.co.uk", "itv.co.uk"))
    }

    func testSuffixItselfHasNoSite() {
        XCTAssertNil(PublicSuffix.siteKey(forHost: "co.uk"))
        XCTAssertNil(PublicSuffix.siteKey(forHost: "com.au"))
    }

    // MARK: - The private section

    /// Two GitHub Pages sites are two strangers. A "last two labels" reading
    /// makes them one site, which is exactly the leak §14.3 forbids.
    func testMultiTenantHostsAreSeparateSites() {
        XCTAssertEqual(PublicSuffix.siteKey(forHost: "alice.github.io"), "alice.github.io")
        XCTAssertEqual(PublicSuffix.siteKey(forHost: "bob.github.io"), "bob.github.io")
        XCTAssertFalse(PublicSuffix.isSameSite("alice.github.io", "bob.github.io"))
        XCTAssertFalse(PublicSuffix.isSameSite("a.herokuapp.com", "b.herokuapp.com"))
        XCTAssertFalse(PublicSuffix.isSameSite("one.vercel.app", "two.vercel.app"))
    }

    // MARK: - Wildcards and exceptions

    /// `*.ck` with `!www.ck` is the canonical pair the algorithm's exception
    /// step exists for. Without the exception, every `.ck` site collapses into
    /// one.
    func testWildcardAndItsException() {
        XCTAssertEqual(PublicSuffix.siteKey(forHost: "site.example.ck"), "site.example.ck")
        XCTAssertEqual(PublicSuffix.siteKey(forHost: "www.ck"), "www.ck")
    }

    // MARK: - Things that are not sites

    func testHostsWithNoRegistrableDomain() {
        XCTAssertNil(PublicSuffix.siteKey(forHost: "localhost"))
        XCTAssertNil(PublicSuffix.siteKey(forHost: "192.168.1.1"))
        XCTAssertNil(PublicSuffix.siteKey(forHost: "[::1]"))
        XCTAssertNil(PublicSuffix.siteKey(forHost: ""))
        XCTAssertNil(PublicSuffix.siteKey(forHost: nil))
        XCTAssertNil(PublicSuffix.siteKey(forHost: "a..b.com"))
    }

    /// Nil on either side is never a match — "we could not work out what site
    /// this is" must not read as "same site".
    func testUnknownHostsNeverMatch() {
        XCTAssertFalse(PublicSuffix.isSameSite(nil, nil))
        XCTAssertFalse(PublicSuffix.isSameSite("localhost", "localhost"))
        XCTAssertFalse(PublicSuffix.isSameSite("192.168.1.1", "192.168.1.1"))
    }

    // MARK: - The attacks the rule exists to stop

    func testSuffixConfusionIsNotAMatch() {
        XCTAssertFalse(PublicSuffix.isSameSite("example.com", "example.com.evil.net"))
        XCTAssertFalse(PublicSuffix.isSameSite("example.com", "notexample.com"))
        XCTAssertFalse(PublicSuffix.isSameSite("example.com", "example.com.co"))
        XCTAssertFalse(PublicSuffix.isSameSite("bank.com", "bank.com.attacker.io"))
    }

    func testSubdomainsOfOneSiteDoMatch() {
        XCTAssertTrue(PublicSuffix.isSameSite("accounts.example.com", "www.example.com"))
        XCTAssertTrue(PublicSuffix.isSameSite("login.bbc.co.uk", "www.bbc.co.uk"))
    }

    /// PSL step 4: an unlisted suffix falls back to "the rightmost label is the
    /// public suffix". The point of the test is the *direction* of the error —
    /// an unlisted multi-label suffix splits sites apart (a declined fill),
    /// never merges them (a leak).
    func testUnlistedSuffixFallsBackNarrowly() {
        XCTAssertEqual(PublicSuffix.siteKey(forHost: "shop.example.zzqq"), "example.zzqq")
    }
}
