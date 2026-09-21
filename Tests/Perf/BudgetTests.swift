//
//  BudgetTests.swift
//  LunaTests
//
//  The two §19.1 budgets that only exist inside the app: the `⌘T` command bar
//  (< 100 ms) and the sidebar at 120 fps. The other two — cold launch and the
//  40-tab memory ceiling — are measured against real processes by
//  `Tools/perf`, because neither is observable from inside a test host.
//
//  These are skipped unless `LUNA_PERF=1`. A wall-clock assertion in the
//  everyday suite fails for reasons that have nothing to do with the code —
//  another agent's build, a Spotlight pass — and a flaky red test teaches
//  people to ignore red tests. `Tools/perf/run.sh` sets the variable; the
//  numbers land in `docs/PERF.md`.
//

import BrowserKit
import XCTest
@testable import Luna

@MainActor
final class BudgetTests: XCTestCase {

    /// Optional, and torn down only if it exists: `XCTSkipUnless` below aborts
    /// `setUp` before this is assigned, and `tearDown` still runs. A skipped
    /// test that takes the suite down with it is worse than no test.
    private var directory: URL?

    /// The opt-in is a file, not an environment variable, because
    /// `xcodebuild test` does not pass its environment to a hosted unit test's
    /// host app — verified: with `LUNA_PERF=1` in the environment and as
    /// `TEST_RUNNER_LUNA_PERF=1` on the command line, the test host still saw
    /// neither and skipped. `run.sh` touches this path and removes it after.
    static let enabledMarker = "/tmp/luna-perf-enabled"
    static let defaultOutput = "/tmp/luna-perf-ui.txt"

    override func setUpWithError() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["LUNA_PERF"] == "1"
                || FileManager.default.fileExists(atPath: Self.enabledMarker),
            "§19.1 budget measurement — run Tools/perf/run.sh ui"
        )
        directory = URL.temporaryDirectory.appending(path: "luna-perf-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        guard let directory else { return }
        try? FileManager.default.removeItem(at: directory)
        self.directory = nil
    }

    /// `print` from a test host does not reach `xcodebuild`'s log, so the number
    /// goes to a file `run.sh` can read. Without this the measurement exists
    /// only inside a process that has already exited.
    private func record(_ line: String) {
        print(line)
        let path = ProcessInfo.processInfo.environment["LUNA_PERF_OUT"] ?? Self.defaultOutput
        let url = URL(fileURLWithPath: path)
        let data = Data((line + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }

    private func percentile(_ values: [Double], _ fraction: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        return sorted[min(sorted.count - 1, Int(Double(sorted.count) * fraction))]
    }

    private func window() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1440, height: 900),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = NSView(frame: window.contentLayoutRect)
        return window
    }

    /// §19.1: `⌘T` to a command bar you can type into, < 100 ms.
    ///
    /// Measures `present(.newTab:in:)` — panel construction, the local source
    /// snapshot (§9.7) and first responder — which is everything between the
    /// keystroke and the caret. It does not include AppKit's own event
    /// dispatch, which no test can see and no code of ours can change.
    func testCommandBarPresentation() async throws {
        let directory = try XCTUnwrap(directory)
        let store = try BrowserStore(path: directory.appending(path: "luna.sqlite"))
        let session = try await BrowserSession.restored(store: store)
        // A realistic list to rank against: the bar snapshots every open tab.
        for index in 0..<40 {
            session.newTab(url: URL(string: "https://example.com/\(index)")!)
        }
        let bar = CommandBarController(session: session, adaptive: AdaptiveHistory(store: store))
        let window = window()

        var times: [Double] = []
        for _ in 0..<20 {
            let start = CFAbsoluteTimeGetCurrent()
            bar.present(.newTab, in: window)
            times.append((CFAbsoluteTimeGetCurrent() - start) * 1000)
        }
        let first = times[0]
        let median = percentile(times, 0.5)
        record(String(format: "PERF command-bar first %.1f ms, median %.1f ms (budget 100 ms)", first, median))
        XCTAssertLessThan(first, 100, "first ⌘T is the one the user notices")
        XCTAssertLessThan(median, 100)

        session.tearDown()
    }

    /// §19.1: the sidebar scrolls at 120 fps on ProMotion — 8.33 ms per frame.
    ///
    /// What is measured is the main-thread cost of a scroll step: layout plus a
    /// synchronous draw of everything on screen. That is a ceiling test, not
    /// a frame-rate reading — it cannot see the compositor, and a test host has
    /// no ProMotion display. If this is over budget, 120 fps is impossible; if
    /// it is under, 120 fps is merely possible, and §19.5's Animation Hitches
    /// instrument is what confirms it.
    func testSidebarScrollFrameCost() throws {
        let spaceID = UUID()
        let tabs = (0..<40).map { index in
            Tab(
                spaceID: spaceID,
                kind: index < 4 ? .essential : (index < 8 ? .pinned : .today),
                url: URL(string: "https://example.com/\(index)")!,
                title: "A tab with a reasonably long title \(index)",
                order: index
            )
        }
        let list = TabListController()
        let window = window()
        list.scrollView.frame = NSRect(x: 0, y: 0, width: 260, height: 800)
        window.contentView?.addSubview(list.scrollView)
        list.show(tabs, activeTabID: tabs.first?.id)
        window.contentView?.layoutSubtreeIfNeeded()
        window.contentView?.display()

        let clip = list.scrollView.contentView
        let travel = max(1, list.scrollView.documentView.map { $0.frame.height - clip.bounds.height } ?? 1)
        var frames: [Double] = []
        for step in 0..<120 {
            // 120 steps over the full travel, both ways: a flick, not a crawl.
            let progress = Double(step % 60) / 60
            let offset = travel * (step < 60 ? progress : 1 - progress)
            clip.scroll(to: NSPoint(x: 0, y: offset))
            list.scrollView.reflectScrolledClipView(clip)
            let start = CFAbsoluteTimeGetCurrent()
            list.movePills()
            window.contentView?.layoutSubtreeIfNeeded()
            window.contentView?.display()
            frames.append((CFAbsoluteTimeGetCurrent() - start) * 1000)
        }
        let median = percentile(frames, 0.5)
        let worst = percentile(frames, 0.95)
        record(String(format: "PERF sidebar frame median %.2f ms, p95 %.2f ms (budget 8.33 ms)", median, worst))
        XCTAssertLessThan(worst, 8.33, "a frame over 8.33 ms cannot be delivered at 120 Hz")
    }
}
