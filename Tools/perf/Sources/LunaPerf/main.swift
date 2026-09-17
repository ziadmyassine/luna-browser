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
    var idle: (rss: Int, footprint: Int) = (0, 0)
    var helperCount = 0

    for run in 1...runs {
        let baseline = Measure.webKitHelpers()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        let start = DispatchTime.now()
        try process.run()
        guard let milliseconds = Measure.waitForWindow(pid: process.processIdentifier, since: start, timeout: 20)
        else {
            print("  run \(run): no window within 20 s")
            process.terminate()
            continue
        }
        times.append(milliseconds)
        print(String(format: "  run %d: %.0f ms to first window", run, milliseconds))

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
    print(String(format: "LAUNCH median %.0f ms  (budget 800 ms)  min %.0f max %.0f",
                 Measure.median(times), times.min() ?? 0, times.max() ?? 0))
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

default:
    print("usage: luna-perf seed <db> <spaces> <tabs> | launch <binary> <runs> "
          + "| tabs <total> <spaces> <live> | leak")
}
