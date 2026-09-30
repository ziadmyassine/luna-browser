# Research

What was found out before building, kept so it is not found out twice.

## §26 Known WebKit constraints — the honest list

Keep this table current. Every entry is a thing a Chromium-based project would get for free.

| Constraint | Impact | Our mitigation |
|---|---|---|
| No public **favicon** API | Sidebar identity | Parse + fetch ourselves (§4.7) |
| No **network request interception** / custom protocol handlers for `http(s)` | Can't build request-level blocking, custom caching, or a proxy layer | Use `WKContentRuleList` (§17) + navigation-policy hooks; accept the ceiling |
| No **custom-scheme registration** for web-page-triggered handlers (`registerProtocolHandler`) | `mailto:`-style web app handlers won't work | Handle the common schemes natively; document |
| Storage is **shared across webviews** unless separated by data store | Per-Space isolation must be planned up front | One `WKWebsiteDataStore(forIdentifier:)` per Space, unconditionally (§5) |
| Data store **removal fails while in use** | Deleting a Space can silently no-op | Tear down all tabs, verify via `allDataStoreIdentifiers` |
| Web process **suspension / non-recovery** in background | Dead white windows | Termination delegate + heartbeat + auto-restore (§19.3) |
| **Content rule limit is exactly 150,000**, compilation is slow | Can't ship giant combined lists | Split/prune lists, compile off-thread, cache by hash — all three lists measured at 186,404 rules / 14.8 s first run (§17.1) |
| **WebExtensions ≠ Chrome MV3 parity** | Some extensions won't work | Curated compatibility list + honest docs (§16.5) |
| A **custom scheme handler must be synchronous**, or own its cancellation set | An async handler can be told to `stop` mid-flight and then crashes on the next callback | Luna's handler does all its work inline — both delegate methods are `WK_SWIFT_UI_ACTOR`, so `stop` cannot interleave, and `stop` is a documented no-op (§4.5) |
| A **missed `didFinish` wedges a tab forever**, and raises nothing | A scheme handler that forgets to finish looks like an infinite load with no error to catch | Finish on every path; the internal-page tests assert it |
| `WKContentRuleList` has **no public blocked-load callback** | No exact per-tab blocked count (the real notification is SPI, D10) | Heuristic: a blocked sub-resource fires `error` and leaves no Resource Timing entry, a 404 leaves one (§17.4) |
| `preferredHTTPSNavigationPolicy` **cannot drive an interstitial** | Both modes end an http-only navigation at `about:blank` via `didFinish`, with no delegate error at all | Upgrade and cancel in `decidePolicyFor` ourselves (§17.6) |
| `url-filter` is **not a regex** | No alternation, no `{n,m}`, no `\d` — the published AdGuard `^` mapping does not compile | Luna's own converter, plus RFC 3492 punycode since Foundation has no IDNA (§17.1) |
| `NSGlassEffectView.tintColor` **ignores hue on `.regular`** | Red, blue, yellow and white at the same alpha render byte-identically; only alpha is read | `Surface.glassTint`'s light/dark flip buys nothing on any chrome plane — decide whether it is worth keeping (`SETTINGS-SPEC.md` §7.2) |
| `NSGlassEffectView` **cannot be captured offscreen** | `cacheDisplay` returns fully transparent, so no automated visual regression test of glass | Measure from real screen captures |
| **Key-equivalent search stops at the first match** and swallows the event *even when that item is disabled* | You cannot win a shortcut by disabling the earlier claimant | Claim it on the key window's responder chain instead (§23.1's `⌘1…⌘9`) |
| **WebKit renders page updates near 60 fps on a 120 Hz display** | Page animations run at half the rate of Luna's own chrome — measured 2026-09-24 on a ProMotion MacBook: 60.8 fps in a visible tab, 120.5 for Luna's animation clock | Safari's default too ("Prefer Page Rendering Updates near 60fps"). Lifting it needs WebKit SPI and costs battery; not done, Martin decides |
| **A page in a window Stage Manager shows in its strip keeps animating** | Measured 2026-09-24: an x.com post page at 22–27 % CPU (plus 8–10 % in WebKit's GPU process) while Luna was in the strip, restyling about 60 times a second. Luna's own process was 4–5 %, all of it relaying the page's frames | The strip draws the window live, so WebKit treats the page as visible and does not throttle it. Safari does the same. Hiding the web view while the window is not in front would stop it, but freezes the preview and pauses video; not done, Martin decides |
| **No notification when the default browser changes** | A "Luna is your default browser" line goes stale silently | Refresh on the completion handler *and* on `didBecomeActiveNotification` |
| `FileManager.isWritableFile(atPath:)` **is not a writability check** | Reads POSIX mode bits only; answers true for TCC-protected `~/Desktop` and `~/Documents`, then the write fails | Create and delete a dot-file — the only check that agrees with what the download does |
| **iCloud Passwords helper is allowlisted** to known browsers by signing/team ID (macOS 15.4+) | Apple's own extension can never work in Luna | Write synchronizable items straight into iCloud Keychain instead (§14.2); bridge third-party managers (§14.7) |
| Fullscreen API has had **real bugs** across releases | Video sites break | Explicit test matrix per OS update; keep a quirks list |
| **Safari's web-compat profile is ours**, including Chrome-only sites | Ongoing breakage | Per-site UA overrides (§4.6) + a public "report a broken site" path |
| Safe Browsing is **not free for commercial use** | No malware/phishing warnings by default | Decide in §17.7 |

## §29 Research sources

Arc interaction model & features: [Split View](https://resources.arc.net/hc/en-us/articles/19335393146775-Split-View-View-Multiple-Tabs-at-Once) · [Little Arc](https://resources.arc.net/hc/en-us/articles/19235387524503-Little-Arc-Quick-Lookups-Instant-Triaging) · [Air Traffic Control](https://resources.arc.net/hc/en-us/articles/22932014625431-Air-Traffic-Control-Automate-Your-Link-Routing) · [Keyboard Shortcuts](https://resources.arc.net/hc/en-us/articles/20595231349911-Keyboard-Shortcuts) · [Arc feature overview](https://www.makeuseof.com/features-arc-browser/) · [Arc Luna/UI/design breakdown](https://blakecrosley.com/guides/design/arc) · [Boosts 2.0](https://alternativeto.net/news/2023/5/arc-browser-s-boosts-2-0-take-control-of-the-web-and-make-it-look-the-way-you-really-want)

WebKit APIs: [Building Profiles with new WebKit API](https://webkit.org/blog/14423/building-profiles-with-new-webkit-api/) · [WebKit Features in Safari 18.4 (WKWebExtension)](https://webkit.org/blog/16574/webkit-features-in-safari-18-4/) · [WKWebExtension docs](https://developer.apple.com/documentation/webkit/wkwebextension/) · [WKWebsiteDataStore docs](https://developer.apple.com/documentation/webkit/wkwebsitedatastore) · [interactionState](https://developer.apple.com/documentation/webkit/wkwebview/interactionstate) · [underPageBackgroundColor](https://developer.apple.com/documentation/webkit/wkwebview/underpagebackgroundcolor) · [Explore WKWebView additions (WWDC21)](https://wwdcnotes.com/documentation/wwdcnotes/wwdc21-10032-explore-wkwebview-additions/) · [WKURLSchemeHandler](https://developer.apple.com/documentation/webkit/wkurlschemehandler) · [WKWebsiteDataStore.h source](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/UIProcess/API/Cocoa/WKWebsiteDataStore.h)

WebKit limitations: [WebView Usage & Challenges (W3C WebView CG)](https://webview-cg.github.io/usage-and-challenges/) · [WKWebView memory limits](https://developer.apple.com/forums/thread/766309) · [Background renderer suspension issue](https://github.com/andrewyng/openworker/issues/665) · [Hibernated tab cost](https://dev.to/megapixel99/what-a-hibernated-browser-tab-actually-costs-i10)

Content blocking: [WKContentRuleList example](https://github.com/dequin-cl/WKContentRuleExample) · [Blocking Ads and Trackers (rule limits)](https://docs.sudoplatform.com/guides/ad-tracker-blocker/blocking-ads-and-trackers)

Ranking: [Firefox urlbar ranking / frecency](https://firefox-source-docs.mozilla.org/browser/urlbar/ranking.html) · [Ranking browser history suggestions (paper)](https://arxiv.org/pdf/1911.11807)

Prior art on WebKit: [Orion 1.0 (Kagi)](https://blog.kagi.com/orion) · [Orion extension support](https://help.kagi.com/orion/browser-extensions/macos-extensions.html) · [Ora Browser (open-source Arc alternative)](https://www.orabrowser.com/) · [surf](https://github.com/TylerSimmons212/surf) · [chord-browser](https://github.com/Drzaln/chord-browser) · [vane](https://github.com/notnaki/vane)

Platform/distribution: [LSSetDefaultHandlerForURLScheme](https://developer.apple.com/documentation/coreservices/1447760-lssetdefaulthandlerforurlscheme) · [Launch Services from Swift](https://rderik.com/blog/managing-uti-and-url-schemes-via-launch-services-api-from-swift/) · [Sparkle sandboxing](https://sparkle-project.org/documentation/sandboxing/) · [macOS signing/notarisation notes](https://gist.github.com/rsms/929c9c2fec231f0cf843a1a746a416f5)

Passwords: [Apple — Passwords extensions for third-party browsers](https://support.apple.com/guide/passwords/get-extensions-mchlf7ac261e/mac) · [1Password macOS AutoFill](https://www.1password.community/announcements-52/macos-autofill-is-now-available-to-everyone-25254)

Safe Browsing: [Google Safe Browsing v5](https://developers.google.com/safe-browsing/reference/rpc/google.security.safebrowsing.v5) · [Safe Browsing overview](https://developers.google.com/safe-browsing)

## §30 Reference UI

Transcribed from the reference captures in `inspiration/`. These are **observed traits to match in feel**, not assets to copy. Where this conflicts with §7/§8, this section wins — it's Martin's actual reference.

| File | What it shows | Drives |
|---|---|---|
| `main-tab-bar-and-ui.png` | Floating window, glass sidebar, Essentials tiles, workspace dots, split handle | §30.1–30.11 |
| `non-side-bar-tab-ui.png` | Sidebar-off "top bar" layout with centred URL pill and right action cluster | §30.12–30.14 |
| `downloads-ui.png` | Download-complete popover anchored to the toolbar, with a particle sweep — both withdrawn, see §30.15 | §30.15–30.16 |
| `transfer-from-other-browsers.png` | Two-pane onboarding import picker | §30.17–30.18 |
| `iphone-mac-sync.png` | New Tab page, Favorites grid, cross-device tabs, iOS companion | §30.19–30.22 |
| `refresh-animation-ui.mov` | Reload/refresh motion | §30.23 |

> **Resolved:** sync is in, over **iCloud** — see §31. The iOS companion stays v2 (§25.5), but the sync layer is designed now so the phone can join later without a migration.

#### From `non-side-bar-tab-ui.png` — the sidebar-off layout

#### From `downloads-ui.png`

#### From `transfer-from-other-browsers.png`

#### From `iphone-mac-sync.png`

- [x] ~~**30.19 New Tab page**~~ — **cut.** It shipped as a centred "Search or type a URL" pill over a Favorites grid, and every route into it already opened §9.1's Command Bar: `⌘T`, §3.4's New Tab row, §4's `+`, and the pill itself, which handed off rather than taking a second line of input. What was left was a page whose only job was to be somewhere to stand while the bar was open. `luna://newtab` no longer routes, a tab with no address is `about:blank`, an empty Space opens no tab, and §3.3a's two wells are what the column says instead. Schema `v9` rewrites the tabs that were standing on it, and `v10` does it again — an older instance left open across the upgrade wrote its copy of a row back afterwards.
  > The gap that killed it: the "Add Favorite" slot had nowhere to go — it opened the Command Bar, which makes a **Today** tab — so the grid's one affordance of its own was already broken, and §3.3a now says the same thing in the sidebar where the tiles actually are.
#### From `refresh-animation-ui.mov`

- [~] **30.23 Reload motion — DEFERRED 2026-09-17 by Martin.** Transcribed and built; `Luna/Features/Reload/`
  exists, is tested, and is intentionally **not wired into the app**. The prismatic arc
  (white → amber → mint → lavender, sampled from the clip) is recorded in `docs/UI-SPEC.md` §7. Do not
  reconnect it without asking. Original note follows.
  > **Checked 2026-09-24: partly built.** `Luna/Features/Reload/` is built and not wired in. Its "is tested" claim is wrong: no test covers `ReloadBloom`.
#### Built beyond the original list (checked 2026-09-24)

## §33 Reference implementations

Three open-source browsers are cloned at `~/Desktop/Projects/other browsers/` on Martin's machine, with a feature→file map in `BROWSER-INVENTORY.md`. They exist on that machine only. They must never be committed here, vendored, or referenced by a path that assumes they exist.

| Repo | Stack | Licence | Why it is useful |
|---|---|---|---|
| `ora-browser/` — the-ora/browser | Swift 5.9 + SwiftUI + WebKit, macOS 15+ | **GPL-3.0** | Closest to our shape. Ships a working **iCloud Keychain autofill** service and a filter-list fetch → compile → cache pipeline that matches D14. |
| `nook/` — nook-browser/nook | Swift 6 + SwiftUI + WKWebView, macOS 15.5+ | **GPL-3.0** | Largest surface: a `WKWebExtension` host with **native messaging and Bitwarden biometrics**, Peek, split view, site routing, and importers for **Arc, Dia and Safari**. |
| `zen-desktop/` — zen-browser/desktop | Firefox 156 fork (JS/mjs + patches) | **MPL-2.0** | Different engine, so no WebKit answers — but the best available reference for *interaction* design on spaces, Glance, compact mode, boosts and folders. |

> **Read them as much as you want. Write Luna's own code.**
>
> There is no restriction on reading, searching or quoting these repos while you work. They are the fastest available answer to "how does WebKit actually behave here", which Apple's documentation frequently does not give. Use them hard — that is why they are on the machine.
>
> **The constraint is on the output, not the input.** What lands in Luna has to fit Luna: Swift 6 strict concurrency (D1), the AppKit/SwiftUI split (D2), the §8 token system, the §19 budgets, and our own Tab/Space model. Nook's ~3,000-line `BrowserManager` and ~4,000-line `Tab.swift` solve their architecture's problems; transplanting them imports a design §0.3 and §19 exist to prevent. Arriving at the same solution because it is the correct one is fine and expected — that is convergence, not copying.
>
> **Verbatim reuse is legal (D12) and occasionally right.** When it is — a gnarly well-tested algorithm, a non-obvious API call sequence — take it, add a header naming the source repo, file path, commit and licence, add an entry to `THIRD_PARTY_NOTICES.md`, and note it in the milestone report. No approval round-trip; this must never stall a milestone.

#### What they answer well

Confirming an approach is possible at all (Ora's keychain autofill, for §14.1) · naming the API that solves something WebKit documents badly · the edge case you would otherwise hit in week three · on-disk paths and data formats (Dia's layout, for §23.2) · and, for Zen, how an interaction should feel.

#### Immediate leads (evidence, not answers — verify each yourself)

- **§14.1 password spike** — Ora ships iCloud Keychain autofill and Nook ships native messaging with Bitwarden biometric unlock. That is strong evidence both §14.2 and §14.7 are achievable from a Developer ID app. It is *not* proof of what Apple permits us specifically; still build the throwaway signed build and write `docs/PASSWORDS.md`.
- **§23.2 Dia importer** — done that way: the paths in §23.2 were read off the running install, not off Nook's source. Ora's own importer supplied the concepts (copy-with-sidecars, the 1601 epoch and its guards, `JSONSerialization` over `Decodable`, loose bookmarks-bar URLs are Favorites, keyset paging); its `ImportAccessService` was dropped whole, since entitlements and security-scoped bookmarks are dead weight for an unsandboxed app (D8).
- **§17.1 blocking pipeline** — both Swift browsers already do fetch → convert → compile → cache against the rule cap, which confirms the approach scales at our size. Ours is written from the WebKit documentation and the measurements in §17.1.
- **§30 interaction detail** — Zen's spaces, Glance and compact-mode behaviour are the closest shipping analogue to §13 and §7.2. Watch them run; read §30 for what we actually build.
