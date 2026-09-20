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

    /// A host with no registrable domain is its own site key.
    ///
    /// This used to return nil for all of these, on the reasoning that there
    /// was "no site here". The reasoning was wrong, and the cost was the whole
    /// feature going silently dead on `http://localhost:8080/` — the first
    /// place anyone building a login form tries it — and on every router and
    /// NAS on a home network. An exact host is a perfectly good key; what
    /// §14.3 forbids is a *wildcard* spanning two owners, and there is no
    /// wildcard here.
    func testHostsWithNoRegistrableDomainAreTheirOwnSite() {
        XCTAssertEqual(PublicSuffix.siteKey(forHost: "localhost"), "localhost")
        XCTAssertEqual(PublicSuffix.siteKey(forHost: "localhost."), "localhost")
        XCTAssertEqual(PublicSuffix.siteKey(forHost: "LocalHost"), "localhost")
        XCTAssertEqual(PublicSuffix.siteKey(forHost: "nas"), "nas")
        XCTAssertEqual(PublicSuffix.siteKey(forHost: "192.168.1.1"), "192.168.1.1")
        XCTAssertEqual(PublicSuffix.siteKey(forHost: "127.0.0.1"), "127.0.0.1")
        XCTAssertEqual(PublicSuffix.siteKey(forHost: "[::1]"), "::1")
        XCTAssertEqual(PublicSuffix.siteKey(forHost: "::1"), "::1")
    }

    /// The exact-host key must stay exact. The PSL path would reduce every
    /// dotted quad to its last two labels, which would make `10.0.0.1` and
    /// `192.168.1.1` the same site and offer one router's password to another.
    func testExactHostsNeverWiden() {
        XCTAssertFalse(PublicSuffix.isSameSite("10.0.0.1", "192.168.1.1"))
        XCTAssertFalse(PublicSuffix.isSameSite("10.0.0.1", "10.0.0.2"))
        XCTAssertFalse(PublicSuffix.isSameSite("localhost", "notlocalhost"))
        XCTAssertFalse(PublicSuffix.isSameSite("localhost", "localhost.evil.com"))
        XCTAssertFalse(PublicSuffix.isSameSite("nas", "nas.example.com"))
        XCTAssertTrue(PublicSuffix.isSameSite("localhost", "localhost"))
        XCTAssertTrue(PublicSuffix.isSameSite("10.0.0.1", "10.0.0.1"))
    }

    func testMalformedHostsStillHaveNoSite() {
        XCTAssertNil(PublicSuffix.siteKey(forHost: ""))
        XCTAssertNil(PublicSuffix.siteKey(forHost: nil))
        XCTAssertNil(PublicSuffix.siteKey(forHost: "a..b.com"))
        XCTAssertNil(PublicSuffix.siteKey(forHost: "."))
    }

    /// Nil on either side is never a match — "we could not work out what site
    /// this is" must not read as "same site". Note that two *identical* unknown
    /// hosts still do not match: the comparison is between site keys, and two
    /// absent keys are not one key.
    func testUnknownHostsNeverMatch() {
        XCTAssertFalse(PublicSuffix.isSameSite(nil, nil))
        XCTAssertFalse(PublicSuffix.isSameSite("co.uk", "co.uk"))
        XCTAssertFalse(PublicSuffix.isSameSite("a..b.com", "a..b.com"))
        XCTAssertFalse(PublicSuffix.isSameSite("", ""))
        XCTAssertFalse(PublicSuffix.isSameSite(nil, "example.com"))
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
