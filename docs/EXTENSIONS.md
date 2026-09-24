# Extensions — how the other browsers do it, and what Luna should build

**TODO.md ★ P4 / §16's research, before any code.** Read this before starting
§16.1, and before writing any copy that promises an extension works.

Researched 2026-09-24 from source (Search, Nook, Ora, Zen), from the macOS 26.5
SDK headers, and from Kagi's published docs for Orion. §6's spike then ran
uBOL, Dark Reader and Bitwarden in a WebKit harness on the same SDK; its
answers are written under each question there.

---

## 1. The short answer

| Question | Answer |
|---|---|
| Can a third-party WebKit browser run Chrome extensions? | **Yes.** `WKWebExtension` (macOS 15.4+, no additions in 26) loads Chrome-format MV2/MV3 from a folder or ZIP. Search ships it today with 1Password, Bitwarden, uBOL, Tampermonkey and Vimium working. |
| Does "loads with 0 errors" mean "works"? | **No.** WebKit silently drops permissions it does not support, and one missing API is enough to break an extension (Kagi's own wording). The spike found a worker that never starts while `loadBackgroundContent` succeeds and `errors` stays empty (§4). |
| What is missing in WebKit? | `bookmarks`, `history`, `downloads`, `identity`, `management`, `proxy`, `notifications`, `sidePanel`, `offscreen`, `webRequestBlocking`. Blocking is `declarativeNetRequest` only. |
| What does one extension cost? | Ora measured uBOL idle: host 6.5 → 64 MB, **+3 WebKit processes, permanently**. A controller with no extensions: ~1 MB, no processes. Luna's spike: uBOL + Dark Reader + Bitwarden idle, **+~3 processes and +165–230 MB**; each further Space running them, +4 processes and 80–300 MB. |
| Can we install from the Chrome Web Store? | **Yes.** Download the CRX3, verify its signature, strip the header, hand WebKit the ZIP. Search does all of it (`Crx.swift`, MIT). |
| Does Orion's approach apply? | **No.** Orion wrote its own WebExtensions layer inside forked WebKit — six years, "about 70 %" coverage, still labelled experimental. Apple's API starts us near there for free. |
| Is it a small job? | **No.** Search: ~1,400 lines of host + ~3,100 lines of shims. Nook: ~7,400 lines, and switched extensions off "for security and stability reasons". |

**Build it**, on Apple's API, with Search as the working reference and Nook as
the list of mistakes. Ship it labelled experimental, with a published
compatibility list (§16.5).

---

## 2. What each browser does

### Search (driceroland/Search) — MIT, the one that works

Small SwiftPM app, 206 commits in five days (2026-09-20 → 24), Swift 5 mode.
The only browser found that ships `WKWebExtension` and makes real extensions
work. MIT is GPL-compatible, so code can come across with its notice (§33).

- **One controller for the app**, `WKWebExtensionController.Configuration.default()`. Per-space extensions are on its roadmap as "needs one controller per space", deferred.
- **Stable identity.** `uniqueIdentifier` = the Web Store id; `baseURL` = `chrome-extension://<id>/`, registered as a custom scheme — otherwise WebKit picks a fresh origin each launch and `localStorage`/IndexedDB look empty.
- **Everything granted at install**, because the install prompt is the consent. Re-granted from its own `installed.json` on every launch; WebKit does not persist grants (`WKWebExtensionContext.h` says the app must).
- **Real tab adapters**, 20-odd `WKWebExtensionTab` methods; `webView(for:)` returns the built view so sleeping tabs stay asleep.
- **Hosts the action popup itself** in its own `NSPopover`, because "messages from WebKit's popup never reach the extension's worker, and the popup waits on a spinner for ever".
- **Refuses `promptForPermissionToAccess` silently** — WebKit asks it Safari-style with nobody having touched anything; Chrome never asks there.
- Native messaging reads the Chrome/Chromium/Edge/Brave/Arc host manifests and checks `allowed_origins`.

### Nook — GPL-3.0, the cautionary one

~7,400 lines. Works for some extensions; its README now says extensions were
disabled in a recent release.

- **One app-wide controller** for every profile, and profile switching writes to `controller.configuration` — which returns a copy, so it does nothing (their own comment at `ExtensionManager.swift:161` says so).
- **No real permission model.** Grants every requested permission on every popup open, and grants every extension access to every URL on every navigation.
- **Random extension ids**, so it deduplicates by name + version. Rewrites `manifest.json` on disk at every launch. Hard-codes Bitwarden and Proton.
- **Bitwarden biometric handler** hands the Keychain key to any extension that asks for `com.8bit.bitwarden`.
- **One fake window** for every window; `didUpdateAction` not implemented, so badges are polled.
- CRX installs with **no signature check**.

Worth taking: set everything on the configuration *before* creating the
controller; derive tab configurations from a base that already holds it; wake
the background worker before `performAction`; leave the popup's
`navigationDelegate` alone.

### Ora — GPL-3.0, researched and declined

Never shipped. Its 2026-08-05 research doc says "Don't build it", on cost (the
uBOL numbers in §1), the suspension collision (§4), and the lack of a catalog.
Its review of PR #137 rejected the PR for: tabs announced as closed when
suspended, `tabs.query({})` returning 0 because `openWindowsFor`/`focusedWindowFor`
were not implemented, two delegate methods that do not exist (the `@objc`
protocol is all-optional, so they compile and are never called), and a
page-reachable install path that granted `<all_urls>` without a prompt.

Two of Ora's reasons do not apply to Luna: we have no catalog problem once CRX
install works, and D8 already makes Luna unsandboxed.

### Orion (Kagi) — own implementation, not a model

Own WebExtensions layer in its WebKit fork since 2019; no statement found that
it has moved to `WKWebExtension`. One-click install from the Chrome Web Store and
Firefox Add-ons, MV2 and MV3, ~70 % API coverage, native messaging (1Password
works only after 1Password added Orion to its allowlist). Labels extensions
experimental, gives users background/popup consoles, and asks bug reports to
compare against Chrome. The Linux beta ships without extensions.

Take the honesty, not the architecture.

### Zen — interaction only

No permanent extensions button: the list folds into the site-data panel next to
the URL, pinned buttons sit in the URL bar and spill into a compact grid past
55 % of its width. Extensions are global — no per-workspace behaviour, which
leaves §16.6 as Luna's to invent.

---

## 3. Decisions for Luna

1. **One controller per Space.** Schema v7 gave every Space its own jar, history
   and downloads; extensions follow. Each gets its own configuration identifier
   and `defaultWebsiteDataStore` = the Space's store, set before the controller
   exists. This is also how §16.6 (per-Space enable) works at all — one
   controller cannot load a context for some web views and not others.
   Cost: an extension enabled in three Spaces runs three workers. Default a new
   install to the current Space only.
2. **Every Space gets a controller from launch**, extensions or not (~1 MB, no
   processes). The controller must be on the configuration when the web view is
   made and cannot be added later, so attaching lazily means rebuilding tabs.
3. **Stable identity.** Web Store id for store installs, a stored id for local
   ones; fixed `chrome-extension://<id>/` base URL.
4. **Luna persists grants and denials itself**, and re-applies them at load.
   Install prompt lists every permission and every host pattern (cmux's review
   caught `<all_urls>` missing from theirs).
5. **Real windows and tabs.** One adapter per `BrowserWindow`, one per tab with
   identity equality; implement `openWindowsFor`/`focusedWindowFor`.
6. **Hibernated tabs stay open to extensions.** `webView(for:)` returns `nil`;
   never `didCloseTab` on hibernate (D3, §19).
7. **Install from folder, ZIP and Chrome Web Store** (CRX3 verified), all off the
   main actor, ZIP size and paths checked *before* extracting. Nothing a page
   can trigger without the user pressing Luna's own button.
8. **Buttons go in the top bar's action capsule** (§30.14 built it for this) and
   the sidebar's equivalent — every one a real control under `CLAUDE.md`'s
   button rules and in `ButtonFeedbackTests`.
9. **No shims in the first version.** No `externally_connectable` rewrites, no
   manifest patching, no per-extension special cases. Add them one at a time
   against a named extension in §16.5's list.
10. **Content blocking stays native.** §17's `WKContentRuleList` is the ad
    blocker; uBOL is a compatibility test, not a feature.
11. **Background content gets its own store per Space, wiped of service-worker
    registrations at launch, and a Chrome user agent.** Both are §4 traps the
    spike hit: without the first, workers are dead on every launch after the
    first; without the second, Bitwarden's worker throws or, with Luna's
    Safari-token UA, it takes its Safari path and spins waiting on a native
    app that is not there. Web Store installs are Chrome builds, so Chrome is
    also what they were tested against. Web tabs keep Luna's own UA.

---

## 4. WebKit traps, with who found them

| Trap | Found by | For Luna |
|---|---|---|
| A worker gets the UA of the last page loaded; when it differs, WebKit stops running workers and never restarts extension ones. | Search | **Does not reproduce** (§6 Q4): a Chrome-UA tab left later tabs' extensions working, so per-view `customUserAgent` and §4.6 are safe. The UA problem that does exist is the background view's own, below. |
| The background view's UA has no `Chrome/` or `Safari/` token unless the host sets one. Bitwarden's browser detection throws (`this.device` is null) and its worker fails. Luna's own UA is no fix: its `Safari/` token sends extensions down Safari-mode paths that expect Safari's native app (§6). | Luna spike | Present extension pages as Chrome: `configuration.webViewConfiguration.applicationNameForUserAgent = "Chrome/141.0.0.0 Safari/537.36"` before `WKWebExtensionController(configuration:)`, giving `Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36`. Appending is the only route: `WKWebViewConfiguration` has no `customUserAgent`, and `context.webViewConfiguration` is a read-only copy. Track the major version from `WebViewFactory.chromeUserAgent`. Web tabs' UA measured unchanged. |
| The background worker registers in `Configuration.webViewConfiguration.websiteDataStore` — `.default()` unless set, not the controller's `defaultWebsiteDataStore` — and the registration outlives the app. Next launch WebKit reuses it, never starts the worker, and says nothing: `loadBackgroundContent` succeeds at once, `context.errors` is empty. Dead 16/16 with a stale registration, alive 14/14 without. | Luna spike | Give background content its own persistent store per Space via `webViewConfiguration.websiteDataStore`; before `controller.load` at launch, `removeData(ofTypes: [WKWebsiteDataTypeServiceWorkerRegistrations], modifiedSince: .distantPast)` on that store only — the Space's web store holds sites' own workers. Extension storage lives under `WebExtensions/<controller id>/` and survives. `dataRecords(ofTypes:)` does not list `webkit-extension://` origins, so it has to be the store-wide removal. Held 7/7. Probably a WebKit bug; file one. |
| Loading all contexts at once fails some workers, and WebKit never retries. | Search | Load one at a time, after the first window shows. |
| A failed worker stays failed. | Search | Watch `errorsDidUpdateNotification`, unload and reload, at most once a minute. |
| `controller.configuration` returns a copy. | Nook | Configure before init; never mutate after. |
| Extension pages load only in a view built from that extension's configuration. | Search | Navigating a tab across web ↔ extension page means replacing its web view. |
| A worker's WebSocket deadlocks (worker runs on the web process's main thread). | Search | Hit by 1Password. Search proxies it through `URLSession`. |
| Several `runtime.onMessage` listeners: the first return value wins. | Search | Shim only if §16.5 shows a break. |
| `.wasm` served without `application/wasm`. | Search | Breaks streaming compile; Bitwarden on Intel. |
| MV3 workers idle out after ~5 min; popup then hangs. | Nook | Wake the background before showing the popup. |
| `declarativeNetRequest` may accept rules and block nothing. | one dev.to report | **Does not reproduce** (§6 Q2). |
| `loadBackgroundContent` never called back for Bitwarden. | Ora | Time out at 8 s and treat as failed (Search does). |

---

## 5. Native messaging (§14.7)

Two optional delegate methods; ~300 lines as the TODO says. Read host manifests
from Luna's own folder and the Chrome, Chromium, Edge, Brave and Arc ones; check
`allowed_origins`; pass the origin as argv; 4-byte length + JSON. Search's
`ExtensionNative.swift` is the reference; Nook's skips `allowed_origins` and
should not be.

Bitwarden as Chrome needs no native host for basic operation: 0 native
messages over 5 runs. Only its Safari mode asks for one (§6).

1Password will also need to add Luna to its trusted-browser list — Orion waited
on that for years. That is an email to 1Password, not code.

---

## 6. The spike (do this first — about 2 days)

A throwaway branch, one Space, extensions loaded unpacked from disk. Answer:

Answered 2026-09-24 on macOS 26.5, Mac mini M4, with the harness in
`Tools/perf/Sources/LunaExtensionSpike`. Memory is physical footprint.

1. Memory and process count for uBOL, Bitwarden and Dark Reader, idle and with 10 tabs, against §19's 3.5 GB budget.

   No extensions: 56–58 MB footprint, 4 processes (two controllers, two blank
   tabs). All three idle: about +3 processes and +165–230 MB; one run doubled.
   With 10 real pages: 1.6–1.8 GB over 18–20 processes, most of it the pages.
   Inside the budget.

2. Does uBOL's `declarativeNetRequest` block anything?

   Yes. The doubleclick and googlesyndication fetches were blocked every run
   and the control loaded; `hasContentModificationRules` is true. Decision 10
   stands: §17's blocker is still Luna's own.

3. Does WebKit's own `action.popupPopover` deliver messages to the worker, or does Luna need Search's self-hosted popup?

   It delivers: uBOL's popup shows real per-site state. Dark Reader's failures
   were the stale-registration trap (§4), not the popup. Bitwarden's presents
   once its pages are Chrome (below). No self-hosted popup yet.

4. Does a custom UA on one tab kill the Space's workers?

   No. A Chrome-UA tab left later tabs' extensions working; per-view
   `customUserAgent` is safe.

5. Do granted match patterns give access, or does WebKit still ask per URL (Nook says the latter, Search's code implies the former)?

   Granting the requested permissions and match patterns `.grantedExplicitly`
   before load gives access (`hasAccess` true, content injected), and WebKit
   made no prompt of any kind. Search's model holds; Nook's per-URL grant on
   every navigation is unnecessary.

6. Two Spaces, same extension: two workers, isolated storage?

   Two copies: the second Space costs +4 processes and 80–300 MB, and blocking
   works there too.

7. Which identity should extension pages present?

   Chrome. Under Luna's Safari-token UA, Bitwarden's vault-timeout loop sends a
   "sleep" native message to Bitwarden's Safari app; unanswered, the
   extension's WebContent process spins at 100 % CPU and the popup never
   presents. As Chrome it reports `ChromeExtension`, the popup presents, login
   reaches the master-password screen, CPU ~0 %. uBOL and Dark Reader do not
   branch on Safari and behave the same either way.

   | Identity | Runs | Result |
   |---|---|---|
   | Safari, native stub answering | 3 | Works; 5 "sleep" messages per 20 s |
   | Safari, no stub | 2 | Popup never presents; 100 % CPU |
   | Chrome, with or without stub | 5 | Works; 0 native messages |

Still open:

- **Bitwarden autofill injection fails** — the next real blocker.
  `chrome.scripting.ExecutionWorld` is undefined in WebKit, so
  `chrome.scripting.ExecutionWorld.ISOLATED` throws in
  `triggerAutofillScriptInjection`. Same under either identity.
- Smaller: notification clicks are unsupported; `chrome.offscreen` is
  undefined.
- Why two early runs survived a stale registration.
- Whether the registration trap is a WebKit bug or behaviour the host is
  expected to handle.

---

## 7. Build order and size

| Step | TODO | Estimate |
|---|---|---|
| Spike | §6 above | 2 days |
| Host: per-Space controllers, tab/window adapters, stable ids, staggered load, worker recovery | §16.1 | 4–5 days |
| Install: folder, ZIP, CRX3 + Web Store button | §16.2 | 3 days |
| Permission prompts and persistence | §16.3 | 2–3 days |
| Action buttons, badges, popup, options page, context menus | §16.4 | 3–4 days |
| Native messaging | §14.7 | 2–3 days |
| Compatibility list against the six named extensions | §16.5 | 2 days, then ongoing |
| Per-Space enable UI | §16.6 | 1 day (the controllers already exist) |

About four weeks to a version that runs the §16.5 list, before any shims.

---

## Sources

- Search: github.com/driceroland/Search — `Sources/Search/Extensions.swift`, `ExtensionPopup.swift`, `ExtensionShims.swift`, `ExtensionNative.swift`, `ExtensionSocket.swift`, `Crx.swift`, `ROADMAP.md`.
- Nook: `Nook/Managers/ExtensionManager/*` in the §33 clone; README on the disabled release.
- Ora: `docs/research/browser-extensions.md` and `pr-137-extensions-review.md` in the local the-ora clone.
- Orion: help.kagi.com/orion/browser-extensions/macos-extensions.html, …/1password.html, …/troubleshooting-extension-issues.html.
- WebKit: `WKWebExtension*.h` in `MacOSX26.5.sdk`; webkit.org/blog/16574 (Safari 18.4), webkit.org/blog/16993 (Safari 26).
- cmux PR #14139 (CRX3 install review); dev.to/megapixel99 (DNR report, unconfirmed).
