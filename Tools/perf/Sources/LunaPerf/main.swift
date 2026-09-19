//
//  main.swift
//  luna-perf — the §19.1 harness
//
//  Three scenarios, all of them measuring the real thing:
//
//    seed   <db> <spaces> <tabs>   fills a Luna database so the launch and idle
//                                  numbers are taken with a realistic session
//    launch <app> <runs>           spawn → first on-screen window, and the idle
//                                  cost of the app once it has restored
//    tabs   <total> <spaces> <live> the headline budget: N tabs across M Spaces,
//                                  `live` of them awake, measured across every
//                                  WebKit process they spawn
//
//  `tabs` links `BrowserKit` and drives the **real** `TabController`, so what it
//  measures is Luna's engine and not an approximation of it. What it does not
//  have is Luna's chrome — the sidebar, the command bar, AppKit's own
//  allocations. `launch` measures that half separately; §19.1's budget is the
//  sum, and `docs/PERF.md` adds them up with that caveat stated.
//

import AppKit
import BrowserKit
import WebKit

// Top-level code is `@MainActor`, which is what every `WKWebView` here needs.

let arguments = Array(CommandLine.arguments.dropFirst())

/// Runs the main run loop for real — WebKit does nothing without it — until
/// `condition` goes false or the deadline passes.
func pump(seconds: TimeInterval, while condition: () -> Bool = { true }) {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline, condition() {
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
    }
}

func report(_ title: String, _ processes: [ProcMemory]) -> (rss: Int, footprint: Int) {
    let rss = processes.reduce(0) { $0 + $1.rssKB }
    let footprint = processes.reduce(0) { $0 + $1.footprintKB }
    print("  \(title): \(Measure.mb(rss)) RSS / \(Measure.mb(footprint)) footprint over \(processes.count) processes")
    for process in processes.sorted(by: { $0.rssKB > $1.rssKB }) {
        print("      \(process.name) [\(process.pid)] \(Measure.mb(process.rssKB)) / \(Measure.mb(process.footprintKB))")
    }
    return (rss, footprint)
}

// The pages the live tabs load. A fixed list, so two runs measure the same web.
let pages = [
    "https://en.wikipedia.org/wiki/WebKit",
    "https://news.ycombinator.com/",
    "https://developer.mozilla.org/en-US/docs/Web/API/Window",
    "https://www.apple.com/",
    "https://github.com/WebKit/WebKit",
    "https://www.theverge.com/"
]

switch arguments.first {

// MARK: - seed

case "seed":
    let path = URL(fileURLWithPath: arguments[1])
    let spaceCount = Int(arguments[2]) ?? 3
    let tabCount = Int(arguments[3]) ?? 40
    let done = DispatchSemaphore(value: 0)
    // `Task.detached`, not `Task`: a `Task` started here would inherit the main
    // actor and then deadlock against the semaphore below.
    Task.detached {
        let store = try BrowserStore(path: path)
        var spaces: [Space] = []
        for index in 0..<spaceCount {
            let profile = Profile(name: "Perf \(index)")
            let space = Space(
                name: "Perf \(index)",
                symbolName: "moon.stars.fill",
                gradient: .defaultSpace,
                profileID: profile.id,
                order: index
            )
            try await store.upsert(profile)
            try await store.upsert(space)
            spaces.append(space)
        }
        for index in 0..<tabCount {
            let space = spaces[index % spaceCount]
            try await store.upsert(Tab(
                spaceID: space.id,
                kind: index < 3 ? .pinned : .today,
                url: URL(string: pages[index % pages.count])!,
                title: "Perf tab \(index)",
                lastActiveAt: Date().addingTimeInterval(-Double(index) * 60),
                order: index
            ))
        }
        done.signal()
    }
    done.wait()
    print("seeded \(tabCount) tabs across \(spaceCount) Spaces into \(path.path)")

// MARK: - launch (§19.1 cold launch, §19.4 zero web views at rest)

case "launch":
    let binary = arguments[1]
    let runs = Int(arguments[2]) ?? 5
    var times: [Double] = []
    var readyTimes: [Double] = []
    var tape: [(name: String, ms: Double)] = []
    var idle: (rss: Int, footprint: Int) = (0, 0)
    var helperCount = 0

    for run in 1...runs {
        let baseline = Measure.webKitHelpers()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        // §19.1's "to interactive" is Luna's own to report: it knows when the
        // window has the restored session in it and nothing outside can see that
        // moment. The file must not exist beforehand or the poll below answers
        // instantly with the last run's answer.
        let readyPath = NSTemporaryDirectory() + "luna-perf-ready-\(run)"
        try? FileManager.default.removeItem(atPath: readyPath)
        var environment = ProcessInfo.processInfo.environment
        environment["LUNA_PERF_READY"] = readyPath
        process.environment = environment
        let start = DispatchTime.now()
        try process.run()
        let launched = Measure.waitForLaunch(
            pid: process.processIdentifier, readyPath: readyPath, since: start, timeout: 20
        )
        if let window = launched.window { times.append(window) }
        guard let ready = launched.ready else {
            print("  run \(run): never became interactive within 20 s")
            process.terminate()
            continue
        }
        readyTimes.append(ready)
        tape = Measure.readTape(at: readyPath)
        print(String(format: "  run %d: %.0f ms to interactive, %@",
                     run, ready,
                     launched.window.map { String(format: "%.0f ms to first window", $0) }
                        ?? "window never reported on screen"))
        try? FileManager.default.removeItem(atPath: readyPath)

        if run == runs {
            // Let the session restore land, then measure what a restored Luna
            // costs before the user has touched anything.
            pump(seconds: 5)
            let helpers = Measure.webKitHelpers().subtracting(baseline)
            helperCount = helpers.count
            idle = report("idle, session restored", Measure.memory(of: [process.processIdentifier] + helpers))
        }
        process.terminate()
        pump(seconds: 2)
    }
    if !times.isEmpty {
        print(String(format: "LAUNCH median %.0f ms to first window  min %.0f max %.0f",
                     Measure.median(times), times.min() ?? 0, times.max() ?? 0))
    }
    if !readyTimes.isEmpty {
        print(String(format: "INTERACTIVE median %.0f ms  (budget 800 ms)  min %.0f max %.0f",
                     Measure.median(readyTimes), readyTimes.min() ?? 0, readyTimes.max() ?? 0))
        // The milestones of the last run, as deltas: which phase spent what.
        var previous = 0.0
        let phases = tape.map { milestone -> String in
            defer { previous = milestone.ms }
            return String(format: "%@ +%.0f", milestone.name, milestone.ms - previous)
        }
        print("PHASES " + phases.joined(separator: ", ") + " (ms since exec, last run)")
    }
    print("IDLE \(Measure.mb(idle.rss)) RSS / \(Measure.mb(idle.footprint)) footprint, "
          + "\(helperCount) WebKit helper processes (§19.4 expects 0)")

// MARK: - tabs (§19.1's headline: 40 tabs, 3 Spaces, 6 live, < 3.5 GB)

case "tabs":
    let total = Int(arguments.count > 1 ? arguments[1] : "") ?? 40
    let spaceCount = Int(arguments.count > 2 ? arguments[2] : "") ?? 3
    let live = Int(arguments.count > 3 ? arguments[3] : "") ?? 6

    let baseline = Measure.webKitHelpers()
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    app.finishLaunching()

    // One identified data store per Space, exactly as `ProfileStore` does — a
    // shared store would understate the cost, since WebKit keeps per-store
    // network and storage state.
    let stores = (0..<spaceCount).map { _ in WKWebsiteDataStore(forIdentifier: UUID()) }

    // The window. Only the active tab is ever in the view hierarchy; the other
    // live tabs are awake and off-screen, which is what Luna does.
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 1440, height: 900),
        styleMask: [.titled, .closable, .resizable],
        backing: .buffered,
        defer: false
    )
    window.title = "luna-perf"
    window.makeKeyAndOrderFront(nil)
    app.activate(ignoringOtherApps: true)

    // A weak box per web view: `controller.webView == nil` only proves the
    // controller let go, not that the object — and with it the WebContent
    // process — actually died.
    final class WeakView { weak var view: WKWebView?; init(_ view: WKWebView?) { self.view = view } }

    var controllers: [TabController] = []
    var boxes: [WeakView] = []
    var leaked = 0
    var coldTabs: [Tab] = []
    var liveHelpers: Set<Int32> = []
    var hot: (rss: Int, footprint: Int) = (0, 0)

    // **Everything that touches a web view runs inside this pool.**
    //
    // Top-level code in a command-line tool has no autorelease pool that ever
    // drains, so every `controller.webView` read — including the one in the load
    // poll below — parks the web view for the lifetime of the process. Measured:
    // without this, the liveness check reports "5 of 5 web views still alive"
    // and the WebContent processes never exit, which looks exactly like a bug in
    // `TabController` and is in fact a bug in this harness. `LunaPerf leak`,
    // which always had a pool, releases every one of the same six sites in ≤5 s.
    autoreleasepool {
        for index in 0..<live {
            let controller = TabController(id: UUID(), dataStore: stores[index % spaceCount])
            controller.load(URL(string: pages[index % pages.count])!)
            controllers.append(controller)
            if index == 0, let view = controller.webView {
                view.frame = window.contentView?.bounds ?? .zero
                view.autoresizingMask = [.width, .height]
                window.contentView?.addSubview(view)
            }
        }

        print("  loading \(live) tabs…")
        pump(seconds: 60) { controllers.contains { $0.webView?.isLoading ?? false } }
        // Settle: late subresources, ads and the JIT warming up are part of the cost.
        pump(seconds: 15)

        // The cold tabs. A restored cold tab is a `Tab` value carrying a real
        // `interactionState` blob and nothing else, so give them real ones.
        let blob = controllers.first?.captureInteractionState()
        for index in live..<total {
            coldTabs.append(Tab(
                spaceID: UUID(),
                url: URL(string: pages[index % pages.count])!,
                title: "Cold tab \(index)",
                interactionState: blob,
                order: index
            ))
        }
        print("  \((blob?.count ?? 0) * coldTabs.count / 1024) KB of session blobs "
              + "across \(coldTabs.count) cold tabs")

        liveHelpers = Measure.webKitHelpers().subtracting(baseline)
        hot = report("\(total) tabs, \(live) live", Measure.memory(of: [getpid()] + liveHelpers))

        boxes = controllers.dropFirst().map { WeakView($0.webView) }
        for controller in controllers.dropFirst() { controller.hibernate() }
        leaked = controllers.dropFirst().filter { $0.webView != nil }.count
    }

    // Sampled over time rather than once: dropping the last reference to a
    // `WKWebView` does not synchronously end its WebContent process, and how
    // long WebKit keeps it is the difference between §19.2's claim and what the
    // user's Mac does.
    var cold = hot
    var afterHelpers = liveHelpers
    var elapsed: TimeInterval = 0
    let waits = (ProcessInfo.processInfo.environment["LUNA_PERF_DECAY"] ?? "10,20,30,60")
        .split(separator: ",").compactMap { Double($0) }
    for wait in waits {
        pump(seconds: wait)
        elapsed += wait
        afterHelpers = Measure.webKitHelpers().subtracting(baseline)
        cold = report("+\(Int(elapsed)) s after hibernating \(live - 1)",
                      Measure.memory(of: [getpid()] + afterHelpers))
    }

    print("TABS \(Measure.mb(hot.rss)) RSS / \(Measure.mb(hot.footprint)) footprint  (budget 3.5 GB = 3584 MB)")
    let undead = boxes.filter { $0.view != nil }.count
    print("HIBERNATED \(Measure.mb(cold.rss)) RSS / \(Measure.mb(cold.footprint)) footprint, "
          + "WebKit processes \(liveHelpers.count) → \(afterHelpers.count), "
          + "tabs still holding a WKWebView: \(leaked) (must be 0), "
          + "WKWebViews still alive after release: \(undead) of \(boxes.count) (must be 0)")
    // Give the data stores back rather than leaving cookie jars behind.
    for controller in controllers { controller.hibernate() }
    controllers.removeAll()

// MARK: - leak (§19.2: does the web view actually go away?)

case "leak":
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    app.finishLaunching()
    final class WeakView { weak var view: WKWebView?; init(_ view: WKWebView?) { self.view = view } }

    for page in pages {
        var box = WeakView(nil)
        // See the note in `tabs`: top-level code's autorelease pool never drains.
        autoreleasepool {
            let controller = TabController(id: UUID(), dataStore: WKWebsiteDataStore(forIdentifier: UUID()))
            controller.load(URL(string: page)!)
            pump(seconds: 30) { controller.webView?.isLoading ?? false }
            pump(seconds: 3)
            box = WeakView(controller.webView)
            controller.hibernate()
        }
        var died: TimeInterval?
        for step in stride(from: 5.0, through: 90.0, by: 5.0) {
            pump(seconds: 5)
            if box.view == nil {
                died = step
                break
            }
        }
        let host = URL(string: page)?.host() ?? page
        print("  \(host): web view released after \(died.map { "\(Int($0)) s" } ?? "never (>90 s)")")
    }

// MARK: - page (what Luna's own stack adds to a page load)

case "page":
    let repeats = Int(arguments.count > 1 ? arguments[1] : "") ?? 10
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    app.finishLaunching()

    // **Local files, not websites.** The question here is what *Luna* costs a
    // page load — its four injected scripts, its four message handlers, its
    // KVO observations and the `publishState` behind them — and against a real
    // site that answer is buried under several hundred milliseconds of network
    // that varies by more than the thing being measured.
    //
    // Two documents, because two of Luna's scripts are injected into **every
    // frame**: a plain page says what one document costs, and the same page
    // wrapped around ten same-origin iframes says what the all-frames ones
    // cost when a page is shaped like a real one with ads in it.
    func writePage(iframes: Int) throws -> URL {
        let rows = Array(repeating: "<li>a row of the sort a page is made of</li>", count: 300).joined()
        let frames = (0..<iframes)
            .map { _ in #"<iframe src="about:blank" width="60" height="40"></iframe>"# }
            .joined()
        let document = """
        <!doctype html><html><head><meta charset="utf-8">
        <meta name="theme-color" content="#1f6feb"><title>luna-perf</title>
        <style>body{font:14px/1.5 -apple-system;margin:2rem}li{padding:2px}</style>
        </head><body><h1>luna-perf</h1><ul>\(rows)</ul>\(frames)
        <img src="data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7">
        <script>document.title = "ready " + document.querySelectorAll("li").length;</script>
        </body></html>
        """
        let file = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "luna-perf-page-\(iframes).html")
        try Data(document.utf8).write(to: file)
        return file
    }

    /// Milliseconds from `start` until the view has begun **and** finished a
    /// load. Polled, and every arm is polled by the same function on purpose:
    /// a navigation delegate on one side and `isLoading` on the other would be
    /// two different moments dressed as one comparison.
    func timeLoad(_ view: @autoclosure () -> WKWebView?, since start: DispatchTime) -> Double? {
        var began = false
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.002))
            guard let view = view() else { continue }
            if view.isLoading {
                began = true
            } else if began {
                return Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
            }
        }
        return nil
    }

    /// One load of `file` through `arm`, timed. See the note in `tabs`:
    /// top-level code's autorelease pool never drains, and a web view read
    /// outside a pool never dies.
    func load(_ file: URL, through arm: String) -> Double? {
        var result: Double?
        autoreleasepool {
            switch arm {
            case "bare":
                let configuration = WKWebViewConfiguration()
                configuration.websiteDataStore = .nonPersistent()
                let view = WKWebView(frame: .zero, configuration: configuration)
                let start = DispatchTime.now()
                // Exactly what `TabController.load` does for a file URL —
                // `load(URLRequest)` on one fails silently without the grant.
                view.loadFileURL(file, allowingReadAccessTo: file.deletingLastPathComponent())
                result = timeLoad(view, since: start)
            case "factory":
                // Luna's configuration and nothing else: the scheme handler,
                // the user agent, the preferences and `ContentBlocker.apply`,
                // without the scripts and observations `attach` puts on top.
                let view = WebViewFactory.makeWebView(dataStore: .nonPersistent())
                let start = DispatchTime.now()
                view.loadFileURL(file, allowingReadAccessTo: file.deletingLastPathComponent())
                result = timeLoad(view, since: start)
            default:
                PasswordSettings.isEnabled = arm != "no-passwords"
                let controller = TabController(id: UUID(), dataStore: .nonPersistent())
                let start = DispatchTime.now()
                controller.load(file)
                result = timeLoad(controller.webView, since: start)
                controller.hibernate()
                PasswordSettings.isEnabled = true
            }
        }
        return result
    }

    let arms = ["bare", "factory", "no-passwords", "luna"]
    for iframes in [0, 10] {
        let file = try writePage(iframes: iframes)
        var times: [String: [Double]] = [:]
        for round in 0..<repeats {
            // Rotated, because the first web view of a round pays for the
            // WebContent and GPU processes the rest of it finds warm.
            let turn = round % arms.count
            for arm in Array(arms[turn...] + arms[..<turn]) {
                if let ms = load(file, through: arm) { times[arm, default: []].append(ms) }
            }
        }
        let median = arms.reduce(into: [String: Double]()) { $0[$1] = Measure.median(times[$1] ?? []) }
        print("  \(iframes == 0 ? "one frame" : "\(iframes + 1) frames"):")
        for arm in arms {
            print(String(format: "    %-13@ median %6.1f ms  min %6.1f max %6.1f  (n=%d)",
                         arm as NSString, median[arm] ?? 0,
                         times[arm]?.min() ?? 0, times[arm]?.max() ?? 0, times[arm]?.count ?? 0))
        }
        print(String(format: "PAGE %d frame(s): bare %.1f ms, %+.1f configuration, %+.1f scripts and observers "
                     + "(of which %+.1f is §14's form detection), Luna %.1f ms (%+.1f ms)",
                     iframes + 1, median["bare"] ?? 0,
                     (median["factory"] ?? 0) - (median["bare"] ?? 0),
                     (median["luna"] ?? 0) - (median["factory"] ?? 0),
                     (median["luna"] ?? 0) - (median["no-passwords"] ?? 0),
                     median["luna"] ?? 0, (median["luna"] ?? 0) - (median["bare"] ?? 0)))
    }

    // **Setup, with no page in it at all.** Everything above measures a load;
    // this measures only the building of the thing that does the loading.
    // `activate()` on a controller with no URL builds the web view, registers
    // the handlers, adds the scripts and installs the observations, and loads
    // nothing.
    var bareSetup: [Double] = []
    var lunaSetup: [Double] = []
    for round in 0..<(repeats * 2) {
        for arm in round.isMultiple(of: 2) ? ["bare", "luna"] : ["luna", "bare"] {
            autoreleasepool {
                if arm == "bare" {
                    let configuration = WKWebViewConfiguration()
                    configuration.websiteDataStore = .nonPersistent()
                    let start = DispatchTime.now()
                    let view = WKWebView(frame: .zero, configuration: configuration)
                    bareSetup.append(Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1e6)
                    _ = view
                } else {
                    let controller = TabController(id: UUID(), dataStore: .nonPersistent())
                    let start = DispatchTime.now()
                    controller.activate()
                    lunaSetup.append(Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1e6)
                    controller.hibernate()
                }
            }
        }
    }
    print(String(format: "PAGE building a web view: bare %.2f ms, Luna %.2f ms (%+.2f ms)",
                 Measure.median(bareSetup), Measure.median(lunaSetup),
                 Measure.median(lunaSetup) - Measure.median(bareSetup)))

// MARK: - blocking (§17.1: what a filter-list refresh costs the main thread)

case "blocking":
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    app.finishLaunching()

    // **A heartbeat, because a compile does not block the main thread outright.**
    // `WKContentRuleListStore.compileContentRuleList` keeps the run loop turning
    // and stalls it in bursts, so the number that matters is not "did it block"
    // but "how long did it go without answering". A 10 ms timer that misses its
    // slot by 300 ms is a window that missed 300 ms of a drag.
    // `@MainActor` so the timer's `@Sendable` closure may hold it: a main-actor
    // class is Sendable, and the timer only ever fires on the main run loop.
    @MainActor final class Heartbeat {
        var last = DispatchTime.now()
        var gaps: [Double] = []
        func beat() {
            let now = DispatchTime.now()
            gaps.append(Double(now.uptimeNanoseconds - last.uptimeNanoseconds) / 1_000_000)
            last = now
        }
    }
    let heartbeat = Heartbeat()
    let timer = Timer(timeInterval: 0.01, repeats: true) { _ in
        MainActor.assumeIsolated { heartbeat.beat() }
    }
    RunLoop.main.add(timer, forMode: .common)

    print("  fetching and compiling all three lists (this is the once-a-day job)…")
    let start = DispatchTime.now()
    var done = false
    Task { @MainActor in
        await ContentBlocker.shared.refresh(force: true)
        done = true
    }
    pump(seconds: 300) { !done }
    let total = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1000

    timer.invalidate()
    // The first gap is from the timer being installed, not from any stall.
    let gaps = heartbeat.gaps.dropFirst()
    let stalls = gaps.filter { $0 > 100 }
    let lost = gaps.map { max(0, $0 - 10) }.reduce(0, +)
    print(String(format: "BLOCKING refresh %.1f s, worst main-thread stall %.0f ms, "
                 + "%d stalls over 100 ms, %.1f s of main thread lost in total",
                 total / 1_000_000, gaps.max() ?? 0, stalls.count, lost / 1000))

default:
    print("usage: luna-perf seed <db> <spaces> <tabs> | launch <binary> <runs> "
          + "| tabs <total> <spaces> <live> | page <repeats> | blocking | leak")
}
