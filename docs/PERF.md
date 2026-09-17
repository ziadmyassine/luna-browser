# Luna performance — measured, not assumed

§19.1's budgets are stated as law. Before 2026-09-17 nobody had measured a single one of
them. This file is the record: what was measured, how, on what, and what the number was —
including where the number is bad or where the measurement cannot reach.

Re-run everything with:

```sh
Tools/perf/run.sh            # all of it, appends a dated block below
Tools/perf/run.sh tabs       # the 40-tab memory budget only
Tools/perf/run.sh launch     # cold launch + the idle cost of a restored session
Tools/perf/run.sh ui         # command bar + sidebar frame cost (the opt-in XCTests)
```

## Scoreboard — 2026-09-17

Mac mini (Mac16,10), Apple M4, 10 cores, **16 GB**, macOS 26.5.2. Debug build.

| §19.1 budget | Measured | Verdict |
|---|---|---|
| Cold launch to interactive < 800 ms | **242 ms** median of 5, with 40 tabs to restore | **PASS, 3.3× headroom** |
| New-tab command bar < 100 ms | **54.7 ms** first, **8.8 ms** median | **PASS** |
| **40 tabs / 3 Spaces / 6 live < 3.5 GB RSS** | **165–310 MB RSS, 785–842 MB footprint** | **PASS, ~4× headroom** |
| Sidebar frame ≤ 8.33 ms (120 fps) | **0.05 ms** median, **0.97 ms** p95 | **PASS, 8× headroom** |
| §19.4: no web view for an unselected tab | **0 WebKit processes** with 40 tabs restored | **PASS, on the real app** |
| §19.2: a cold tab holds no `WKWebView` | **0 of 5 alive**, 5 WebContent processes gone | **PASS, verified under load** |

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

Measured from outside: `posix_spawn` of `Luna.app/Contents/MacOS/Luna` to the first
on-screen window owned by that pid, polled at 1 ms through `CGWindowListCopyWindowInfo`,
five runs, with a database seeded to 40 tabs across 3 Spaces.

| run | 1 | 2 | 3 | 4 | 5 | median |
|---|---|---|---|---|---|---|
| ms to first window | 243 | 213 | 240 | 242 | 307 | **242** |

**242 ms against a budget of 800 ms**, with a 40-tab, 3-Space session waiting in the
database. Comfortable.

The same run measures what a restored Luna costs before the user touches anything:

**81 MB RSS / 28 MB phys_footprint, and zero WebKit helper processes.** §19.4 is real, on
the real app: 40 restored tabs spawn no WebContent process at all, because nothing is
selected and nothing selected means no web view. That is also the number to add to the
engine figures above for a whole-app total — about **810 MB footprint** for 40 tabs with 6
live, against a 3.5 GB budget.

Two things to know about the number:

- It is **spawn → first frame**, which is a *lower bound* on "to interactive":
  `AppDelegate` deliberately shows the window before touching SQLite, so the session
  restore lands after this point. Closing that gap needs one line in the app — a signpost
  or a timestamp written at the end of `startSession` — which is a file this agent does not
  own. The harness reads `LUNA_PERF_READY` if it ever exists.
- It is a **warm-file-cache** launch. Emptying the page cache needs `purge`, which needs
  root. The disk half of the number is therefore the best case.

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
