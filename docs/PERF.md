# Luna performance — measured, not assumed

§19.1's budgets are stated as law. Before 2026-09-17 nobody had measured a single one of
them. This file is the record: what was measured, how, on what, and what the number was —
including where the number is bad or where the measurement cannot reach.

Re-run everything with:

```sh
Tools/perf/run.sh            # all of it, appends a dated block below
Tools/perf/run.sh tabs       # the 40-tab memory budget only
Tools/perf/run.sh launch     # cold launch, to interactive, + the idle cost of a restore
Tools/perf/run.sh page       # what Luna's own stack adds to a page load
Tools/perf/run.sh ui         # command bar + sidebar frame cost (the opt-in XCTests)
```

## Scoreboard

Debug builds throughout, but **not one machine**: the 2026-09-17 rows were taken on a
Mac mini (Mac16,10), Apple M4, 10 cores, **16 GB**, macOS 26.5.2, and the 2026-09-19
rows on a MacBook Pro (MacBookPro18,3), Apple M1 Pro, **16 GB**, macOS 27.0. Two
machines two macOS versions apart do not subtract, so each row says which one it is
from rather than pretending to a trend.

| §19.1 budget | Measured | Verdict |
|---|---|---|
| Cold launch to interactive < 800 ms | 09-19, M1 Pro: **356 ms** median of 7 under load, **~275 ms** idle, 40 tabs to restore | **PASS, 2.2× headroom** |
| Cold launch to first window | 09-17, M4: **242 ms** · 09-19, M1 Pro: **245 ms** | a lower bound — see *Launch* |
| Luna's own cost per page load | 09-19, M1 Pro: **+6.6 to +7.4 ms** over a bare `WKWebView`, all in `TabController.attach` | no budget; stated |
| New-tab command bar < 100 ms | 09-17, M4: **54.7 ms** first, **8.8 ms** median | **PASS** |
| **40 tabs / 3 Spaces / 6 live < 3.5 GB RSS** | 09-17, M4: **165–310 MB RSS, 785–842 MB footprint** | **PASS, ~4× headroom** |
| Sidebar frame ≤ 8.33 ms (120 fps) | 09-17, M4: **0.05 ms** median, **0.97 ms** p95 | **PASS, 8× headroom** |
| §19.4: no web view for an unselected tab | both days: **0 WebKit processes** with 40 tabs restored | **PASS, on the real app** |
| §19.2: a cold tab holds no `WKWebView` | 09-17, M4: **0 of 5 alive**, 5 WebContent processes gone | **PASS, verified under load** |

**Every budget passes, comfortably, and §19.2's mechanism does what it claims.** Hibernating
five of six live tabs returns 86 % of the footprint and ends five WebContent processes
within ten seconds.

## The headline: 40 tabs, 3 Spaces, 6 live

`Tools/perf/tabs` builds the real thing: three identified `WKWebsiteDataStore`s (one per
Space, as `ProfileStore` does), six real `TabController`s loading six real sites, one of
them in a window and five awake off-screen — which is exactly Luna's shape — and 34 cold
tabs held as `Tab` values carrying real `interactionState` blobs.

Four runs over an hour, same six pages (Wikipedia, Hacker News, MDN, apple.com, GitHub,
The Verge):

| | RSS | phys_footprint | processes |
|---|---|---|---|
| run 1 | 165 MB | 785 MB | 9 |
| run 2 | 249 MB | 842 MB | 9 |
| run 3 | 180 MB | 817 MB | 9 |
| run 4 | 293 MB | 808 MB | 9 |

**The budget is met with roughly four times the headroom it asks for**, and RSS varies by
±40 % run to run while footprint holds within ±4 % — another reason to state the budget in
footprint. The nine processes
are Luna + six WebContent + one Networking + one GPU. Worth noting for §19.3: three
separate data stores produced **one** shared Networking and **one** shared GPU process, not
three — WebKit shares them across stores.

The 34 cold tabs cost **19 KB in total** — the session blobs, and nothing else. §19.4 holds:
a tab the user has not selected has no controller, no web view and no process.

### Caveats, stated rather than buried

- Both numbers are **engine cost**, not whole-app cost: the harness has no sidebar, no
  command bar and no AppKit chrome. Add the *Launch* section's idle figure for the app's
  own half. Even generously, the sum is nowhere near 3.5 GB.
- Six ordinary pages. Six of Figma, Google Docs, YouTube and Slack would be several times
  this. The budget is not in danger, but this is not the worst case.
- `footprint` (what Activity Monitor calls "Memory") is the number that matters and it is
  consistently **3–5× the RSS**, because RSS does not count compressed pages. §19.1 states
  its budget in RSS; see *Corrections to §19*.

## What hibernation actually gets back

Hibernating five of the six live tabs, then sampling:

| after | RSS | footprint | WebKit helper processes |
|---|---|---|---|
| live | 293 MB | 808 MB | 8 |
| +10 s | 136 MB | 115 MB | 3 |
| +30 s | 138 MB | 109 MB | 3 |
| +60 s | 117 MB | 108 MB | 3 |

**§19.2 works.** Five WebContent processes are gone within ten seconds, and **86 % of the
footprint comes back** — 808 MB → 115 MB. The three survivors are the one live tab plus the
shared Networking and GPU services. The check the harness makes every run:

> `tabs still holding a WKWebView: 0` · **`WKWebViews still alive after release: 0 of 5`**

The harness holds a **weak** box on each web view before hibernating, because
`controller.webView == nil` only proves the controller let go, not that the object died.

### How this was nearly reported as a failure

The first three runs said the opposite: *5 of 5 web views still alive, not one WebContent
process exits, phys_footprint 785 MB → 782 MB over two minutes.* It was a convincing,
specific, completely wrong finding — **and the bug was in the measurement**.

Top-level code in a command-line tool has **no autorelease pool that ever drains**. The
load poll —

```swift
pump(seconds: 60) { controllers.contains { $0.webView?.isLoading ?? false } }
```

— reads `controller.webView` from top-level code, which parks every one of those web views
in the process-lifetime pool. The harness was holding them, and the WebContent processes
stayed alive because of the harness, not because of Luna. Wrapping the whole live-tab
section in an explicit `autoreleasepool` changed 5-of-5-alive to 0-of-5 and 782 MB retained
to 108 MB.

Two things caught it, and both are worth keeping:

- **`LunaPerf leak`**, which drives one real `TabController` per site and always had a
  pool, reported every one of the same six sites released in **≤ 5 s**. Two instruments
  disagreeing is the signal.
- A separate probe tore down a plain `WKWebView` three ways — with
  `closeAllMediaPresentations { _ = view }` exactly as `TabController.detach()` writes it,
  with a completion capturing nothing, and without the call at all — and it deallocated
  cleanly every time. So the strong capture of `view` in that completion handler, which
  looks like a leak, is not one, and the comment defending it is correct.

The lesson for anyone extending this harness: **any code path that reads a `WKWebView` must
sit inside an `autoreleasepool`**, or it will invent a leak and blame the browser.

## Launch

Two instruments now, because the old one could only see half of it.

**From outside**, as before: `posix_spawn` of `Luna.app/Contents/MacOS/Luna` to the
first on-screen window owned by that pid, polled at 1 ms through
`CGWindowListCopyWindowInfo`, with a database seeded to 40 tabs across 3 Spaces.

**From inside**, new: `App/LaunchTrace` writes a file the moment the window has the
restored session in it, and the harness polls for that file exactly as it polls for
the window. That is "to interactive", which is the budget §19.1 actually states and
which nothing was measuring — the previous version of this file asked for "one line
in the app, a signpost or a timestamp written at the end of `startSession`", and this
is it. The elapsed times in the tape are taken from the kernel's own record of when
the process was `exec`ed (`kinfo_proc.p_starttime`), so dyld, the Swift runtime and
the ObjC class registry are on the budget too — a stopwatch started in `main()` would
miss all of it.

Tracing is off unless `LUNA_PERF_READY` names a file, and nothing else can turn it
on: a launch measurement that a stray default could switch on is not one to trust.

### 2026-09-19 — Apple M1 Pro, 16 GB, macOS 27.0, Debug build

| | ms |
|---|---|
| to first window, median of 7 | **245** |
| **to interactive, median of 7** | **356** (min 313, max 561) |
| to interactive, on an idle machine | **~275** |

**356 ms against a budget of 800 ms**, with a 40-tab, 3-Space session waiting in the
database — and that was taken at a load average of 8, with a second Luna and a
browser full of tabs running beside it. The same build on an idle machine lands at
275 ms. Either way the budget is met with room.

### The window poll is not reliable. The ready file is.

Four runs out of five once reported "no window within 20 s" for a process whose own
tape said it had been interactive since 316 ms. The window was there; the window
server would not list it. `CGWindowListCopyWindowInfo([.optionOnScreenOnly])` asks
for windows that are *on screen*, and a background app spawned by a harness may have
none — under Stage Manager a window belonging to anything but the frontmost app is
off to the side, and this call cannot see it.

So `launch` no longer requires a window before it will report a run: both ends are
polled in one loop, the ready file is what the run waits for, and a window that is
never reported costs the run its first-window number and nothing else. **If the two
disagree, the tape is right.**

### Where a launch goes

Milestone deltas, in ms since `exec`, from a representative run:

| phase | ms | what happens |
|---|---|---|
| `main` | 12–20 | dyld, the Swift runtime, the ObjC class registry |
| `appkit` | 60–87 | `NSApplication.shared` and `run()` up to `willFinishLaunching` |
| `menu` | 6–9 | `SettingsDefaults.register`, `MainMenu.install`, §3.6's observer |
| `didFinish` | 36–42 | **AppKit's**, between its two launch notifications |
| `tokens` | 3 | `TokenCheck.run()` — Debug only |
| `window` | 47–74 | `BrowserWindowController()`, `showWindow`, `activate` |
| `store` | 10–31 | awaiting the store, which opened on another thread |
| `session` | 4–8 | `BrowserSession.restored` — 3 Spaces, 40 tabs |
| `chrome` | 65–72 | sidebar, top bar, install, wiring, first full layout |
| `ready` | 2–3 | `render()` |

**Over 40 % of a Luna launch is gone before any Luna code runs**, and another 40 %
is AppKit building an `NSWindow` and laying a view tree out once. `main` + `appkit` +
`didFinish` is ~130 ms of dyld and `-[NSApplication finishLaunching]`; the window and
the one forced `layoutSubtreeIfNeeded` behind `chrome` are ~120 ms of AppKit doing
what it does. Luna's own share — the store, the restore, building the chrome objects
— is under 40 ms of it.

Two consequences worth stating plainly:

- **There is no launch problem to fix.** The remaining headroom is in AppKit, not in
  Luna, and the things that would buy it back are not things worth doing: the
  `layoutSubtreeIfNeeded` at the end can be dropped, but AppKit then does the same
  layout on the next display pass and the first frame the user sees arrives at the
  same time. Moving a cost past the finish line is not making it faster.
- **Measure phases, not lines.** `TokenCheck.run()` was read as 40–55 ms of every
  Debug launch for most of an afternoon, because it was the first statement after the
  last milestone. It is 3 ms. The 40 ms in front of it belongs to AppKit, and it has
  its own milestone now so that nobody reads it as ours again.

### What was changed, and what it bought

- `BrowserStore` is opened on a detached task started before the window, rather than
  synchronously on the main actor after it (`AppDelegate.openStore`). It takes 10–20 ms
  of disk work off the main thread. **It did not move the launch total**, measured by
  alternating two builds run-for-run: base 300 ms median, optimised 291 ms, across 16
  interleaved runs — inside the noise. It is still the right place for the work.
- `BrowserStore.seedIfEmpty` asks with a read before it opens a write transaction.
  Every launch called it and every launch but the first had nothing to do, and a
  `write` block that decides to do nothing has still taken SQLite's write lock.

Both are changes to where work happens rather than to how much of it there is, which
is all that was available: see the table above.

### Release is not faster to launch than Debug

Worth knowing before anyone suggests it: a full `-configuration Release` build of the
same commit, measured the same way in the same minute, lands at **358 ms** median
against Debug's **356 ms**. There is nothing wrong with the optimiser — there is
simply almost no Swift of ours on the launch path to optimise. Launch is AppKit,
dyld and one view-tree layout, and `-O` has no opinion about any of them.

`make run` can stay Debug.

### Still true from the previous pass

The same run measures what a restored Luna costs before the user touches anything:
**105 MB RSS / 35 MB phys_footprint, and zero WebKit helper processes.** §19.4 is
real, on the real app: 40 restored tabs spawn no WebContent process at all, because
nothing is selected and nothing selected means no web view.

It is a **warm-file-cache** launch. Emptying the page cache needs `purge`, which needs
root. The disk half of the number is therefore the best case.

## Page load

`Tools/perf/run.sh page` loads the same local HTML document three ways, rotating the
order every round so that no arm always pays for the WebContent and GPU processes the
next one finds warm:

| | median | what it includes |
|---|---|---|
| bare `WKWebView` | 65.9 ms | WebKit's own defaults, nothing of Luna's |
| `WebViewFactory.makeWebView` | 65.5 ms | + the scheme handler, the UA, the preferences, `ContentBlocker.apply` |
| `TabController` | 73.3 ms | + four user scripts, four message handlers, eight KVO observations |

**Luna costs a page load 7.4 ms, and every bit of it is in `TabController.attach`.**
The configuration is free to within the measurement — `−0.4 ms`, which is noise.

A local file on purpose. The question is what *Luna* adds, and against a real site
that answer is buried under several hundred milliseconds of network that varies by
more than the thing being measured. The page is deliberately ordinary: 300 list
items, a stylesheet, a script, an image and a `theme-color`.

Read the 7.4 ms as **per tab wake, not per navigation**. It is the cost of building a
web view and dressing it, which Luna pays when a cold tab is selected (§19.2) and not
when an already-live tab goes to another page. Against the 66 ms a bare cold load
costs — most of it spawning a WebContent process — it is not where a page's time goes.


## Command bar

`Tests/Perf/BudgetTests.testCommandBarPresentation` times
`CommandBarController.present(.newTab:in:)` against a session with 40 open tabs, twenty
times, and reports the first and the median. The first present is the one the user
notices, so it is asserted separately.

**First present 54.7 ms, median 8.8 ms, against a budget of 100 ms.** The first is ~6× the
rest — that is AppKit loading the panel's views and the field editor once — and it is still
comfortably inside budget, which is the number that matters because it is the one the user
feels on the first `⌘T` of a session.

## Sidebar

`Tests/Perf/BudgetTests.testSidebarScrollFrameCost` drives `TabListController` with 40
rows through 120 scroll steps and times layout + a synchronous `display()` per step. A
frame over **8.33 ms** cannot be delivered at 120 Hz.

This is a **ceiling test, not a frame-rate reading**: it sees main-thread work, not the
compositor, and a test host has no ProMotion display. Passing it means 120 fps is possible;
§19.5's Animation Hitches instrument is what confirms it happens.

**Median 0.05 ms per frame, p95 0.97 ms, against a ceiling of 8.33 ms.** Eight times the
headroom. `NSTableView` row recycling with a fixed row height is doing exactly what
`TabListController`'s header claims it does.

Note the opt-in is a **file**, `/tmp/luna-perf-enabled`, not an environment variable.
`xcodebuild test` does not pass its environment to a hosted unit test's host app — verified
with `LUNA_PERF=1` in the environment *and* `TEST_RUNNER_LUNA_PERF=1` on the command line;
the host saw neither and skipped both tests while reporting `** TEST SUCCEEDED **`. A perf
test that silently skips is worse than none, so `run.sh` touches the marker and reads the
numbers back from a file the test writes.

## §19.6 energy

- Nothing in Luna calls `ProcessInfo.beginActivity`, `disableSuddenTermination` or
  `IOPMAssertion`, so App Nap is not prevented. (`grep -r beginActivity .` — no hits.)
- `applicationShouldTerminateAfterLastWindowClosed` returns `true`, so there is no
  window-less state for a timer to run in: closing the last window quits.
- The lifecycle sweep is a single 60 s `Timer` with **30 s tolerance**, so it coalesces
  with other wake-ups instead of demanding one of its own.

## Corrections to §19

- **§19.1 states its memory budget in RSS.** RSS is the wrong unit for a multi-process
  browser: it counts the dyld shared cache once per process and excludes compressed pages,
  and here it is 3–5× smaller than `phys_footprint`. Worse, it *falls* while the memory is
  still charged to us. The budget should be stated in `phys_footprint` — what Activity
  Monitor shows and what the kernel's memory limits use. Both are recorded here meanwhile.
- **§19.2's "~0 by dropping the webview" holds** — measured, 86 % of footprint returned and
  five WebContent processes ended within ten seconds. Worth writing the measured number
  into §19.2 next to the "~39 MB in mainstream browsers" reference point it currently
  compares itself to, so the claim stops being a target and starts being a result.
- **§19.1's "40 tabs, 6 live" is easy.** With 3.5 GB of budget and ~800 MB of reality, the
  interesting number is not 40 tabs — it is what happens at 6 *heavy* live tabs, or at 200
  tabs. Suggest re-stating the budget against a worse case, since as written it will pass
  forever without telling anyone anything.
- **§19.3's "one Networking process per profile" assumption**: measured, three data stores
  share one Networking and one GPU process.

---

# Run log

Everything below is appended by `Tools/perf/run.sh`, newest last.

### 2026-09-17 23:32 — Apple M4, 16 GB, macOS 26.5.2

```
PERF command-bar first 38.0 ms, median 7.7 ms (budget 100 ms)
PERF sidebar frame median 0.02 ms, p95 0.19 ms (budget 8.33 ms)
```

### 2026-09-17 23:35 — Apple M4, 16 GB, macOS 26.5.2

```
TABS 310 MB RSS / 837 MB footprint  (budget 3.5 GB = 3584 MB)
HIBERNATED 61 MB RSS / 111 MB footprint, WebKit processes 8 → 3, tabs still holding a WKWebView: 0 (must be 0), WKWebViews still alive after release: 0 of 5 (must be 0)
LAUNCH median 247 ms  (budget 800 ms)  min 186 max 672
IDLE 81 MB RSS / 31 MB footprint, 0 WebKit helper processes (§19.4 expects 0)
PERF command-bar first 27.7 ms, median 7.8 ms (budget 100 ms)
PERF sidebar frame median 0.02 ms, p95 0.20 ms (budget 8.33 ms)
```

### 2026-09-18 00:05 — Apple M4, 16 GB, macOS 26.5.2

```
TABS 295 MB RSS / 809 MB footprint  (budget 3.5 GB = 3584 MB)
HIBERNATED 111 MB RSS / 112 MB footprint, WebKit processes 8 → 3, tabs still holding a WKWebView: 0 (must be 0), WKWebViews still alive after release: 0 of 5 (must be 0)
LAUNCH median 268 ms  (budget 800 ms)  min 182 max 421
IDLE 69 MB RSS / 28 MB footprint, 0 WebKit helper processes (§19.4 expects 0)
PERF command-bar first 26.3 ms, median 9.6 ms (budget 100 ms)
PERF sidebar frame median 0.02 ms, p95 0.52 ms (budget 8.33 ms)
```

### 2026-09-19 22:38 — Apple M1 Pro, 16 GB, macOS 27.0

```
PAGE bare 66.3 ms, -0.2 ms configuration, +6.8 ms scripts and observers, Luna 73.0 ms (+6.6 ms)
```
