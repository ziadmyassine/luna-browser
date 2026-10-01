//
//  BudgetTests+Keystroke.swift
//  LunaTests
//
//  §9.7's per-keystroke budget, measured on the real bar. Apart from
//  `BudgetTests.swift` for SwiftLint's type-body limit; it is the same opt-in
//  suite, skipped unless `Tools/perf/run.sh ui` turns it on.
//

import BrowserKit
import XCTest
@testable import Luna

extension BudgetTests {

    /// §9.7: a keystroke in the bar, to its rows on screen.
    ///
    /// The real bar over a store of 3,000 visited pages, typed into a
    /// character at a time through the window, as a key press arrives. Two
    /// clocks start at the key-down. The first stops once the synchronous
    /// half has run — the in-memory merge — and the window has laid out and
    /// drawn the rows it put up: what §9.7 holds to one frame. The second stops
    /// once the store's answer has landed and been laid out and drawn in turn,
    /// which is the moment the list stops changing under the hand.
    ///
    /// AppKit's event dispatch before `sendEvent` and the compositor after
    /// `display` are outside both, as they are outside `testCommandBarPresentation`.
    func testCommandBarKeystroke() async throws {
        let directory = try XCTUnwrap(directory)
        let store = try BrowserStore(path: directory.appending(path: "luna-keystroke.sqlite"))
        try await store.seedIfEmpty()
        let spaces = try await store.spaces()
        let space = try XCTUnwrap(spaces.first).id
        try await Self.fillHistory(store, inSpace: space)
        let session = try await BrowserSession.restored(store: store)
        for index in 0..<40 {
            session.newTab(url: URL(string: "https://tab\(index).example/")!)
        }
        let bar = CommandBarController(session: session, windowID: session.keyWindowID, adaptive: AdaptiveHistory(store: store))
        let window = window()

        // The first word is the session's first typing, and pays for what
        // AppKit loads once — row views, glass, symbol images. It is reported
        // on its own and held to nothing: the budget is for typing.
        var first: [Double] = []
        var local: [Double] = []
        var landed: [Double] = []
        for (index, word) in ["swift", "github", "stackov", "wikipedia", "developer", "news", "youtube"].enumerated() {
            let times = try await type(word, into: bar, in: window, session: session)
            if index == 0 {
                first += times.map(\.local)
            } else {
                local += times.map(\.local)
                landed += times.map(\.landed)
            }
        }
        record(String(
            format: "PERF command-bar keystroke over 3000 pages, %d keys: local rows median %.1f ms, p95 %.1f ms; "
                + "with the store's rows median %.1f ms, p95 %.1f ms (budgets 16/33 and 50/100 ms); "
                + "the session's first word, local rows worst %.1f ms",
            local.count, percentile(local, 0.5), percentile(local, 0.95),
            percentile(landed, 0.5), percentile(landed, 0.95), first.max() ?? 0
        ))
        // One frame for the typical key and two for the slow one, which is
        // where the first keys after the bar opens fall; docs/PERF.md has the
        // spread these were set over.
        XCTAssertLessThan(percentile(local, 0.5), 16, "local rows miss the frame §9.7 gives them")
        XCTAssertLessThan(percentile(local, 0.95), 33, "a slow key's local rows take more than two frames")
        XCTAssertLessThan(percentile(landed, 0.5), 50, "the store's rows land too long after the key")
        XCTAssertLessThan(percentile(landed, 0.95), 100, "a slow key's store rows land too long after it")
        session.tearDown()
    }

    /// Opens the bar, waits for it to finish opening, and types `word` a key
    /// at a time, giving back each key's two times in milliseconds.
    private func type(
        _ word: String, into bar: CommandBarController, in window: NSWindow, session: BrowserSession
    ) async throws -> [(local: Double, landed: Double)] {
        bar.present(.newTab, in: window)
        let panel = try XCTUnwrap(window.contentView?.subviews.compactMap { $0 as? CommandBarPanel }.last)
        try await Task.sleep(for: .milliseconds(400))
        while panel.isOpening { try await Task.sleep(for: .milliseconds(10)) }
        var times: [(local: Double, landed: Double)] = []
        var typed = ""
        for character in word {
            typed.append(character)
            let start = CFAbsoluteTimeGetCurrent()
            window.sendEvent(try Self.keyDown(String(character), in: window))
            window.contentView?.layoutSubtreeIfNeeded()
            window.contentView?.display()
            let local = (CFAbsoluteTimeGetCurrent() - start) * 1000
            while bar.historyAnswered != typed, CFAbsoluteTimeGetCurrent() - start < 1 {
                try await Task.sleep(for: .microseconds(250))
            }
            window.contentView?.layoutSubtreeIfNeeded()
            window.contentView?.display()
            times.append((local, (CFAbsoluteTimeGetCurrent() - start) * 1000))
            XCTAssertEqual(bar.historyAnswered, typed, "the store never answered “\(typed)”")
            // Before either asks the network or loads a page: the suggestions
            // wait 180 ms and the top hit 150.
            SearchSuggestions.shared.cancel()
            session.topHit.cancel()
            try await Task.sleep(for: .milliseconds(60))
        }
        bar.dismiss()
        try await Task.sleep(for: .milliseconds(300))
        return times
    }

    /// 3,000 pages on 60 sites, visited one to four times each over four
    /// months, about one visit in seven typed: the shape of a few months'
    /// browsing. `.example` hosts, so nothing here can be fetched.
    private static func fillHistory(_ store: BrowserStore, inSpace space: UUID) async throws {
        let sites = [
            "github", "stackoverflow", "wikipedia", "developer", "news", "youtube", "reddit", "apple", "swift",
            "google", "maps", "mail", "calendar", "docs", "drive", "figma", "linear", "notion", "slack", "twitter",
            "bbc", "guardian", "nytimes", "amazon", "ebay", "netflix", "spotify", "medium", "substack", "arxiv",
            "kagi", "duckduckgo", "mozilla", "webkit", "chromium", "rust", "python", "npm", "crates", "pypi",
            "hackernews", "lobsters", "dr", "politiken", "borsen", "finans", "dba", "zalando", "ikea", "booking",
            "airbnb", "dsb", "rejseplanen", "skat", "borger", "mitid", "nordea", "danskebank", "lunar", "revolut"
        ]
        var generator = SystemRandomNumberGenerator()
        for page in 0..<3000 {
            let site = sites[page % sites.count]
            let url = URL(string: "https://\(site).example/\(page / sites.count)/article")!
            let title = "\(site.capitalized) — a page about topic \(page / sites.count)"
            for _ in 0..<Int.random(in: 1...4, using: &generator) {
                let kind: VisitKind = Int.random(in: 0..<7, using: &generator) == 0 ? .typed : .link
                let at = Date().addingTimeInterval(-Double.random(in: 0..<(120 * 86_400), using: &generator))
                try await store.recordVisit(url: url, title: title, kind: kind, at: at, inSpace: space)
            }
        }
        try await store.flush()
    }

    private static func keyDown(_ character: String, in window: NSWindow) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, characters: character,
            charactersIgnoringModifiers: character, isARepeat: false, keyCode: 0
        ))
    }

    private static func descendant<T: NSView>(of root: NSView, ofType type: T.Type) -> T? {
        for child in root.subviews {
            if let match = child as? T ?? descendant(of: child, ofType: type) { return match }
        }
        return nil
    }
}
