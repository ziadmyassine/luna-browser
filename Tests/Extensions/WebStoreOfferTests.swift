//
//  WebStoreOfferTests.swift
//  LunaTests
//
//  The toast on a Chrome Web Store extension's page: which addresses are one,
//  and what the toast says before and after.
//

import Combine
import XCTest
@testable import Luna

@MainActor
final class WebStoreOfferTests: XCTestCase {

    private let id = "cjpalhdlnbpafiamejdnhcphjbkeiagm"
    private let tab = UUID()

    private func detailURL() -> URL {
        URL(string: "https://chromewebstore.google.com/detail/ublock-origin/\(id)")!
    }

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

    // MARK: - The hybrid: hijack first, toast as fallback

    /// Reaching the page arms the fallback and waits — the hijacked button is
    /// given its chance before any toast.
    func testReachingThePageArmsTheFallbackAndShowsNoToastYet() {
        let offer = WebStoreOffer()
        var fire: (@MainActor () -> Void)?
        var shown = 0
        offer.schedule = { _, body in fire = body; return AnyCancellable {} }
        offer.present = { _, _ in shown += 1 }
        offer.offer(for: detailURL(), tab: tab, window: nil)
        XCTAssertNotNil(fire)
        XCTAssertEqual(shown, 0)
    }

    /// The button reporting in before the timer cancels it, and no toast appears.
    func testButtonReadyCancelsTheFallback() {
        let offer = WebStoreOffer()
        var cancelled = false
        var shown = 0
        offer.isInstalled = { _ in false }
        offer.schedule = { _, _ in AnyCancellable { cancelled = true } }
        offer.present = { _, _ in shown += 1 }
        offer.offer(for: detailURL(), tab: tab, window: nil)
        offer.buttonReady(url: detailURL(), tab: tab, markAdded: {})
        XCTAssertTrue(cancelled)
        XCTAssertEqual(shown, 0)
    }

    /// Arriving on the page of an extension already in turns the button to "Added"
    /// at once — it reads the install register, not a session flag.
    func testButtonReadyFlipsWhenAlreadyInstalled() {
        let offer = WebStoreOffer()
        var flipped = 0
        offer.isInstalled = { _ in true }
        offer.buttonReady(url: detailURL(), tab: tab, markAdded: { flipped += 1 })
        XCTAssertEqual(flipped, 1)

        offer.isInstalled = { _ in false }
        offer.buttonReady(url: detailURL(), tab: tab, markAdded: { flipped += 1 })
        XCTAssertEqual(flipped, 1)
    }

    /// No button reports in, so the timer fires the existing Add toast, and its
    /// Add action runs the one install endpoint.
    func testTheFallbackFiresTheToastAndItsAddInstalls() {
        let offer = WebStoreOffer()
        var fire: (@MainActor () -> Void)?
        var shown: [PageToast] = []
        var installed: [URL] = []
        offer.schedule = { _, body in fire = body; return AnyCancellable {} }
        offer.present = { toast, _ in shown.append(toast) }
        offer.install = { url, _, _ in installed.append(url) }
        offer.offer(for: detailURL(), tab: tab, window: nil)
        fire?()
        XCTAssertEqual(shown.count, 1)
        XCTAssertEqual(shown.first?.actions.map(\.title), ["Add"])
        shown.first?.actions.first?.run()
        XCTAssertEqual(installed, [detailURL()])
    }

    /// The hijacked button's own press runs the same install, once.
    func testAddRunsTheInstallOnce() {
        let offer = WebStoreOffer()
        var installed: [URL] = []
        offer.install = { url, _, _ in installed.append(url) }
        offer.add(url: detailURL(), tab: tab, onInstalled: {})
        XCTAssertEqual(installed, [detailURL()])
    }

    /// The button is turned to "Added" only when the install actually goes
    /// through — `onInstalled` fires on success and not otherwise.
    func testAddFlipsTheButtonOnlyOnInstall() {
        let offer = WebStoreOffer()
        var flipped = 0
        offer.install = { _, _, onInstalled in onInstalled() }
        offer.add(url: detailURL(), tab: tab, onInstalled: { flipped += 1 })
        XCTAssertEqual(flipped, 1)

        offer.install = { _, _, _ in }
        offer.add(url: detailURL(), tab: UUID(), onInstalled: { flipped += 1 })
        XCTAssertEqual(flipped, 1)
    }

    /// The same page reached again arms nothing new: one offer per page.
    func testReEntryIsDedupedByTheOfferedTab() {
        let offer = WebStoreOffer()
        var schedules = 0
        offer.schedule = { _, _ in schedules += 1; return AnyCancellable {} }
        offer.offer(for: detailURL(), tab: tab, window: nil)
        offer.offer(for: detailURL(), tab: tab, window: nil)
        XCTAssertEqual(schedules, 1)
    }
}
