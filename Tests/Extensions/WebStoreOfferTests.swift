//
//  WebStoreOfferTests.swift
//  LunaTests
//
//  The toast on a Chrome Web Store extension's page: which addresses are one,
//  and what the toast says before and after.
//

import XCTest
@testable import Luna

@MainActor
final class WebStoreOfferTests: XCTestCase {

    private let id = "cjpalhdlnbpafiamejdnhcphjbkeiagm"

    func testTheStoresDetailPageIsAnOffer() {
        let url = URL(string: "https://chromewebstore.google.com/detail/ublock-origin/\(id)")
        XCTAssertEqual(WebStoreOffer.extensionID(on: url), id)
        let withQuery = URL(string: "https://chromewebstore.google.com/detail/ublock-origin/\(id)?hl=en")
        XCTAssertEqual(WebStoreOffer.extensionID(on: withQuery), id)
    }

    func testTheOldStoreAddressIsAnOfferToo() {
        let url = URL(string: "https://chrome.google.com/webstore/detail/ublock-origin/\(id)")
        XCTAssertEqual(WebStoreOffer.extensionID(on: url), id)
    }

    /// The store's home and search, other sites, and plain http are not.
    func testOtherPagesAreNot() {
        for text in [
            "https://chromewebstore.google.com/",
            "https://chromewebstore.google.com/search/ublock",
            "https://example.com/detail/x/\(id)",
            "http://chromewebstore.google.com/detail/ublock-origin/\(id)",
            "https://chromewebstore.google.com/detail/ublock-origin/not-an-id"
        ] {
            XCTAssertNil(WebStoreOffer.extensionID(on: URL(string: text)), text)
        }
        XCTAssertNil(WebStoreOffer.extensionID(on: nil))
    }

    func testTheToastOffersAdd() {
        var added = false
        let toast = PageToast.addExtension { added = true }
        XCTAssertEqual(toast.actions.map(\.title), ["Add"])
        toast.actions.first?.run()
        XCTAssertTrue(added)
    }

    func testTheOutcomeIsSaidAndACancelIsNot() {
        XCTAssertEqual(PageToast.extensionAdded(.installed(name: "uBlock Origin"))?.detail, "uBlock Origin")
        XCTAssertEqual(PageToast.extensionAdded(.failed("No network"))?.text, "No network")
        XCTAssertNil(PageToast.extensionAdded(.cancelled))
    }
}
