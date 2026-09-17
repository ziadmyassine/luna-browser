# Project "Luna" — an Arc-style browser on WebKit (macOS)

> **Status:** planning only. Nothing is built yet. This file is the single source of truth for scope, architecture decisions, and task breakdown.
> **Owner:** Martin
> **Written:** 2026-09-17
> **Target:** macOS 26+ native app, Swift 6, AppKit shell + SwiftUI surfaces, WKWebView (system WebKit).
> **Bundle ID:** `dk.novapps.luna` · **Internal scheme:** `luna://` · **Licence:** **GPL-3.0-or-later** at publication (D12).
> **All 16 open questions were answered on 2026-09-17 — read §32 first. Where §32 contradicts an older section, §32 wins.**

---

## 0. READ THIS FIRST (instructions for any agent picking up a task)

### 0.1 What we are building
A **native macOS web browser** that uses **Apple's WebKit (WKWebView)** as its engine — *not* Chromium, *not* Electron, *not* a bundled WebKit build — and that copies the **interaction model and visual polish of Arc Browser** (The Browser Company) while being its own product.

The three sentences that define the product:
1. **The chrome disappears.** No horizontal tab strip, no persistent toolbar. A vertical sidebar holds everything; the page gets the rest.
2. **Tabs are disposable, Spaces are permanent.** Tabs auto-archive; the user's structure lives in Spaces, Pinned tabs and Favorites.
3. **Everything is one keystroke away.** A single Command Bar (`⌘T`) does URL entry, search, tab switching, history search, and app commands.

### 0.2 Non-goals (do NOT build these without asking Martin first)
- Cross-platform (Windows/Linux). macOS only. Do not add abstraction layers "for later portability".
- Bundling or patching a custom WebKit build. We ship against the system framework.
- Chromium/Blink fallback rendering for broken sites.
- A custom account system, our own sync servers, or telemetry-by-default. Sync is **iCloud only** (§31) — no logins, no backend of ours.
- A password manager of our own. We write into **Apple's** Passwords / iCloud Keychain instead — see §14, and read §14.1 before promising anything.
- Mac App Store distribution for v1 (sandbox blocks default-browser registration; see §22).
- Monetisation of any kind — no licence keys, no payments, no accounts (D15).
- Telemetry or analytics, even opt-in (D16).
- AI features in v1. §30.4 reserves the layout slot and nothing else.
- General extension support in v1 — only the §14.7 password bridge. See §16.

### 0.3 Ground rules for agents
- **Never invent an API.** Every WebKit API named in this document has been verified to exist. If you need something not listed here, check `WKWebView.h` / `WKWebsiteDataStore.h` in the WebKit source (`github.com/WebKit/WebKit/tree/main/Source/WebKit/UIProcess/API/Cocoa`) *before* designing around it. Private/underscored SPI (`_WK*`) is **banned** unless a task explicitly authorises it, because it breaks on OS updates and blocks notarisation-free distribution debugging.
- **One task = one PR.** Each `- [ ]` leaf item below should be a self-contained PR with its own acceptance criteria met.
- **Do not skip the "Gotcha" boxes.** They are the results of research, not speculation; ignoring them is how this project dies at 60% complete.
- **Design tokens are law.** Everything visual references §8's token table. No raw hex values in view code.
- **Performance budget is law.** See §19. A browser that eats 12 GB with 40 tabs is a failed product regardless of how pretty the sidebar is.
- **Read the other browsers freely; ship Luna's own implementation (§33).** No limit on what you read — they are the fastest available answer to "how does WebKit actually behave here". The constraint is on the output: what lands in Luna must fit Luna's architecture, concurrency model and budgets, not theirs transplanted. Attribute anything verbatim.
- When a task says "match Arc", the acceptance criterion is *felt behaviour*, not pixel-identical copying. Do not clone Arc's exact artwork, icon set, wordmark, or copy strings — build our own visual identity on the same interaction skeleton.

### 0.4 Glossary (use these exact names in code)
| Term | Meaning |
|---|---|
| **Space** | A named, coloured workspace containing its own Pinned tabs + Today tabs. Owns a `WKWebsiteDataStore` when "separate profile" is enabled. |
| **Profile** | The cookie/storage container. 1 profile may back N Spaces. Backed by `WKWebsiteDataStore(forIdentifier:)`. |
| **Pinned tab** | Persistent, never auto-archives, lives in the upper section of a Space's sidebar list. |
| **Today tab** | Ephemeral tab, auto-archives after N hours (default 12). Lower section of sidebar. |
| **Favorite** | App-icon-sized tile pinned above all Spaces; global, survives Space switching. |
| **Archive** | Soft-delete. Tab leaves the sidebar, its URL/title/snapshot go to the Archive list, recoverable. |
| **Peek** | A transient full-window overlay preview of a link, dismissible with `Esc`, promotable to a real tab. |
| **Mini Window** | Our "Little Arc": a small chromeless window used for links opened from other apps. |
| **Command Bar** | The `⌘T` omni-input (URL + search + tab switch + commands). |
| **Boost** | Per-site user CSS/JS injection. |
| **Easel** | Freeform canvas board. (v2 — see §25.) |

---

## 1. Architecture decisions (already made — don't relitigate without a reason)

| # | Decision | Rationale | Rejected alternative |
|---|---|---|---|
| D1 | Swift 6, strict concurrency on | New codebase; avoid retrofitting actors later | Swift 5 mode |
| D2 | **AppKit** owns windows, sidebar, split layout; **SwiftUI** for leaf views (settings, command bar rows, popovers) | SwiftUI's window/focus/drag-drop story is still weak for a browser; AppKit `NSSplitViewController` + custom `NSView` gives us the animation control Arc-grade motion needs | Pure SwiftUI (fails on drag-reorder + window chrome control) |
| D3 | One `WKWebView` per tab, lazily created, hibernated when cold | Only way to get real per-tab state; see §19 for the memory plan | One webview + `interactionState` swapping (loses media/JS state, feels broken) |
| D4 | Persistence in **SQLite via GRDB.swift** | History needs FTS5 + ranked queries; Core Data is wrong for this | Core Data / SwiftData |
| D5 | Per-Space storage isolation via `WKWebsiteDataStore(forIdentifier:)` (macOS 14+) | This is the *only* supported multi-profile mechanism; see §5 | Non-persistent stores (loses logins) |
| D6 | Content blocking via `WKContentRuleList` compiled from EasyList-derived JSON | Native, in-engine, no network interception needed | JS-based blocker (slow, visible flicker) |
| D7 | Extensions via **`WKWebExtension` / `WKWebExtensionContext` / `WKWebExtensionController`** (macOS 15.4+) | Apple's supported path; aligns us with other WebKit browsers | Orion-style custom WebExtensions reimplementation (years of work; Orion is ~70% of the API after 5 years) |
| D8 | Distribution: Developer ID + notarisation + **Sparkle 2** | Sandbox blocks `LSSetDefaultHandlerForURLScheme`, so MAS is impossible for a default browser | Mac App Store |
| D9 | Minimum OS = **macOS 26** | Native Liquid Glass materials do most of the §30.1/§30.2/§30.11 chrome for us instead of hand-stacked `NSVisualEffectView`; `WKWebExtension` (15.4+) is included either way. Narrower audience accepted — early adopters of a new browser skew current. | macOS 15.4 / 14 |
| D10 | No private SPI in shipping code | Stability + upgradability | `_WKWebsiteDataStore`, `_WKDownload` etc. |
| D11 | **Sync over iCloud (CloudKit private database, `CKSyncEngine`)** | No servers, no accounts, no support burden, data stays in the user's own iCloud; matches the Apple-native positioning | Custom sync backend (cost + privacy surface + an account system we said we wouldn't build) |
| D12 | **Open source under GPL-3.0-or-later**, licence file added at publication *(revised 2026-09-17, was: closed source)* | Matches Nook and Ora exactly, which makes reuse of their work legal instead of forbidden (§33), and makes "audit us yourself" the strongest form of the zero-telemetry claim (D16). GPL also forces anyone who forks Luna to stay open. Note that copyright does not stop a fork using the **name** — trademark does, and that is a separate, later decision. | MIT/Apache-2.0 (no reuse of GPL prior art); proprietary (rejected) |
| D13 | **Both layouts ship in v1** — sidebar layout *and* top-bar layout (§30.12) | It is a core part of Martin's reference, not a stretch goal | Sidebar-only v1 |
| D14 | **Blocklists are fetched at runtime, never bundled** | The licence reason disappeared when D12 became GPL — EasyList would now be compatible. The **operational** reason stands and is the better one: blocking improves without shipping an app update, and the binary stays small | Bundling EasyList |
| D15 | **Free. No monetisation.** | No licence keys, no payment processor, no VAT handling, no dunning, no entitlement checks in Sparkle | Paid one-off / subscription |
| D16 | **Zero telemetry.** Opt-in crash reports only, URLs scrubbed | A privacy-positioned browser that phones home has no story to tell. Deletes a Privacy Policy section and an SDK | Opt-in analytics |

> **Gotcha — D9 changed on 2026-09-17 (§32).** It was 15.4; it is now **macOS 26**, and Liquid Glass is the reason. **Verify the exact API surface and availability against the shipping SDK before designing around it** (§0.3) — a guessed API name spreading through the Design layer is exactly the failure §0.3 exists to prevent. If it does not behave as §30 needs, the fallback is hand-built `NSVisualEffectView` stacks, *not* a lower deployment target.

---

## 2. Repo layout (create this in M0)

```
luna/
├── App/                     # NSApplicationDelegate, URL handling, default-browser flow
├── BrowserKit/              # SPM local package — engine layer, no UI
│   ├── Engine/              # WebViewController, delegates, process pool, data stores
│   ├── Model/               # Tab, Space, Profile, Favorite, ArchiveEntry
│   ├── Store/               # GRDB: history, bookmarks, sessions, migrations
│   ├── Blocking/            # WKContentRuleList compilation + list updater
│   └── Extensions/          # WKWebExtension host
├── UI/                      # AppKit shell
│   ├── Window/              # BrowserWindowController, titlebar, traffic-light insets
│   ├── Sidebar/             # Space switcher, tab list, drag/drop, hover-peek
│   ├── CommandBar/          # Omni input + ranked results
│   ├── Split/               # Split view controller (up to 4 panes)
│   └── MiniWindow/          # "Little Arc" equivalent
├── Design/                  # Tokens, materials, motion curves, iconography
├── Features/                # Reader, Find, Downloads, Boosts, Settings, Import
├── Tests/
└── Tools/                   # Blocklist converter, release scripts, notarise.sh
```

---

## 3. Milestones

- [x] **M0 — Skeleton** (§4): app launches, one window, one hardcoded webview, loads a URL, quits cleanly. **DONE 2026-09-17.** Builds warning-free, 2 unit tests pass, `check-no-appkit` guard green, window opens at 1200×800 and renders `example.com`, quits with no crash report. The §31.1 sync spike is **not** done — it needs a Developer ID certificate that does not exist yet, so it moves to the front of M1.
- [ ] **M1 — Usable browser** (§4, §6, §7, §9, §11): tabs, sidebar, command bar, back/forward, session restore. *Dogfoodable.*
- [ ] **M2 — Arc-ness** (§5, §8, §10, §12, §13, §30): Spaces, split view, theming/motion, archive, pinned/favorites, mini window, reference-UI parity.
- [ ] **M3 — Real-world browser** (§14–§18): downloads, find, zoom, media/PiP, permissions, content blocking, history search, import.
- [ ] **M4 — Platform citizen** (§20–§23, §31): default browser, accessibility, settings, crash reporting, Sparkle updates, notarised build, iCloud sync.
- [ ] **M5 — Extensions & polish** (§16, §19): WKWebExtension host, hibernation tuning, perf pass.
- [ ] **M6 — Ship 1.0** (§24): beta, docs, legal, website, DMG.

---

## 4. Core engine layer

- [ ] **4.1 `WebViewFactory` + shared configuration**
  - Build `WKWebViewConfiguration` centrally: `websiteDataStore`, `defaultWebpagePreferences`, `userContentController`, `applicationNameForUserAgent`, `preferences.isElementFullscreenEnabled = true`, `allowsAirPlayForMediaPlayback`.
  - Set `webView.allowsBackForwardNavigationGestures = true`, `webView.allowsMagnification = true`, `webView.isInspectable = true` (macOS 13.3+ — **required** or Web Inspector silently does nothing).
  - Acceptance: a webview created by the factory passes html5test-class smoke pages and shows a Web Inspector when right-clicked.
- [ ] **4.2 Delegate hub** — one `TabController` implementing:
  - `WKNavigationDelegate`: `decidePolicyFor navigationAction/navigationResponse` (download vs display, external scheme handoff, HTTPS upgrade, blocklist check), `didFailProvisionalNavigation` → our error page, `didReceiveServerRedirect`, `didCommit`.
  - `WKUIDelegate`: `createWebViewWith configuration:` → **must** create a real new tab and return its webview, or `target="_blank"` and `window.open` silently do nothing; `runJavaScriptAlert/Confirm/TextInput` → native sheets; `requestMediaCapturePermissionFor` → our permission chip; `contextMenuConfiguration` for link menus.
  - `WKDownloadDelegate` (`WKDownload`, macOS 11.3+): see §15.
  - Acceptance: `window.open`, `target=_blank`, JS alerts, camera prompt, and a PDF link all behave.
- [ ] **4.3 Navigation state observation** — KVO/`publisher` on `url`, `title`, `isLoading`, `estimatedProgress`, `canGoBack/Forward`, `themeColor`, `underPageBackgroundColor`, `serverTrust`, `hasOnlySecureContent`, `fullscreenState`, `cameraCaptureState`, `microphoneCaptureState`.
- [ ] **4.4 `luna://` internal pages** via `WKURLSchemeHandler` (new tab, settings-embedded docs, error pages, archive view).
  > **Gotcha:** a custom scheme handler only fires for resources loaded *within a document loaded from that same scheme*. Internal pages must be navigated to as `luna://…`, not injected into an `about:blank`.
- [ ] **4.5 Error pages** — replace WebKit's default failure with our styled page (offline, DNS, TLS, blocked-by-us), with a Retry button routed through the scheme handler.
- [ ] **4.6 User-Agent policy** — default to system UA + `applicationNameForUserAgent`. Ship a per-site UA override table (Safari UA / Chrome UA) because some sites gate on Chrome. Add a UI toggle in the site menu.
  > **Gotcha (verified in M0):** `applicationNameForUserAgent` **appends to** WebKit's default UA, it does not replace it — and WebKit's default contains **no `Version/` and no `Safari/` token at all**. So a bare `Luna/1.0` ships a UA that compat-sniffing sites reject. Put the Safari tokens first and the product token last, the way Edge and Chrome-on-iOS do: `Version/<os> Safari/605.1.15 Luna/<CFBundleShortVersionString>`. Read the version from `Bundle` so it cannot rot. Confirmed in the wild: Ora sets a *complete* UA string here and consequently ships a doubled `Mozilla/5.0 … AppleWebKit …` prefix; Nook gets it right.
  > **Gotcha:** we inherit **Safari's exact web-compat profile**, including every site that was only ever tested against Chromium. Budget real time for a per-site quirks list. This is the single biggest ongoing cost of choosing WebKit (it's the top complaint about Orion).
- [ ] **4.7 Favicons** — WebKit exposes **no public favicon API**. Implement `FaviconService`: parse `<link rel="icon|apple-touch-icon">` via a small injected script at `documentEnd`, fall back to `/favicon.ico`, fall back to a generated monogram tile from the domain + Space gradient. Cache to disk keyed by eTLD+1, with a memory LRU.
  - Acceptance: 50 mixed sites show correct icons; no icon ever flashes a broken-image glyph.
  > **Corrections from the M1 build:**
  > - **The cache key is host-minus-`www.`, not eTLD+1.** Foundation ships no public-suffix list, and naive last-two-labels hands `a.github.io` whatever `b.github.io` cached. Revisit only if we ever bundle a PSL.
  > - **SVG favicons do not decode in ImageIO**, so they fall through to `/favicon.ico`.
  > - The monogram fallback tier needs the Space gradient, so it belongs to the UI layer, not to `FaviconService`.

---

## 5. Spaces & profiles (storage isolation)

- [ ] **5.1 `ProfileStore`** wrapping `WKWebsiteDataStore(forIdentifier: UUID)`.
  - Persist the UUID ↔ profile-name mapping ourselves (in SQLite). Identifiers are **not** recoverable from WebKit alone beyond `WKWebsiteDataStore.allDataStoreIdentifiers`.
  - Deletion: `WKWebsiteDataStore.remove(forIdentifier:)` — **fails while any live `WKWebView` still uses the store.** Tear down and deallocate every tab in that profile, then remove, then verify against `allDataStoreIdentifiers`.
  - Data lands in `~/Library/WebKit/WebsiteDataStore/<UUID>/`.
- [ ] **5.2 Space model**: name, icon (SF Symbol), gradient pair, profile id, ordered pinned tabs, ordered today tabs, "auto-archive after" override.
- [ ] **5.3 Space switcher UI**: horizontally swipeable strip at the bottom of the sidebar + `⌘1…⌘9` + `⌃⇥`-style cycling. Switching cross-fades the sidebar content and re-tints the whole window (§8).
- [ ] **5.4 Per-Space default search engine + per-Space "open links here" rule** (the foundation for §25's link routing).
- [ ] **5.5 Cookie/session sanity tests**: log into the same site in two Spaces with separate profiles; confirm independent sessions survive relaunch.
  > **Gotcha:** the *default* data store and non-persistent stores have **no identifier**. Decide at Space-creation time; you cannot retroactively adopt the default store into an identified one. Migrating a user from "shared" to "separate" logs them out — warn in the UI.
- [ ] **5.6 Private/incognito window** = `WKWebsiteDataStore.nonPersistent()`, visually distinct tint, excluded from history writes, no crash-restore.

---

## 6. Tab model, lifecycle & session persistence

- [ ] **6.1 `Tab` model**: id, spaceId, kind (`pinned|today|favorite`), url, title, faviconKey, themeColor, createdAt, lastActiveAt, archivedAt, parentTabId (for tree/child grouping), `interactionState: Data?`, snapshot path.
- [ ] **6.2 Session persistence via `interactionState`** — **the blob must be cached outside the web view, at every `didFinish`.** `interactionState` reads back **nil once the WebContent process is dead**, which is precisely the case §19.3 has to recover from. Read it late and there is nothing to restore.
- [ ] **6.2a (original wording)** — capture `webView.interactionState` on background/blur/quit; restore into a fresh webview to bring back full back/forward history and scroll position. Store as `Data` blob in SQLite.
  - Acceptance: quit with 30 tabs across 3 Spaces → relaunch restores order, scroll positions, and back-history for each.
- [ ] **6.3 Auto-archive** — background task archives Today tabs idle > N hours (default 12; user-settable 6h/12h/24h/never). Pinned/Favorites exempt. Archive keeps title/url/favicon/snapshot for 30 days.
- [ ] **6.4 Archive browser** (`⌘⇧A`) with search + restore.
- [ ] **6.5 Tab tree** — links opened from a tab become indented children under it, collapsible. (Arc does this implicitly; make it explicit and better.)
- [ ] **6.6 Drag & drop** — reorder within list, move between sections, move between Spaces (drag onto the Space strip), drag out to a new window, drag a URL in from Finder/other apps, drag a tab's URL *out* to other apps.
- [ ] **6.7 Undo stack** for close/archive/move (`⌘Z` inside the sidebar context).
- [ ] **6.8 Snapshots** — `webView.takeSnapshot(with:)` on blur, downsampled, for the sidebar hover preview and the archive. Cap disk usage (e.g. 200 MB LRU).

---

## 7. Sidebar (the signature surface)

- [ ] **7.1 Layout**: Favorites grid (icon tiles) → Pinned list → divider → Today list → Space strip. Width draggable 180–420 px, persisted.
- [ ] **7.2 Collapse + hover-peek**: `⌘S` collapses to a ~48 px rail (or fully hidden); hovering the left window edge slides the sidebar over the content as a floating panel with a shadow, after a ~0.1 s intent delay, with a ~0.15–0.2 s ease-out reveal. It must **not** trigger while the pointer is merely travelling to the traffic lights.
- [ ] **7.3 Row design**: favicon, title (single line, truncating), close/archive affordance on hover, audio-playing indicator + click-to-mute, loading shimmer, unread/updated dot.
- [ ] **7.4 Selection & keyboard**: full arrow-key navigation, type-ahead, `⌘⌥←/→` to move between tabs, `⌘W` closes (archives) the current tab, `⌘⇧K` archives all Today tabs.
- [ ] **7.5 Folders** inside a Space (drag one tab onto another to create).
- [ ] **7.6 Sidebar-on-right option** (differentiator; Arc doesn't do it well).
- [ ] **7.7 Traffic-light handling**: custom titlebar, `titlebarAppearsTransparent`, `NSWindow.toolbar` removed; traffic lights must be inset into the sidebar and must re-position correctly when the sidebar collapses, on fullscreen enter/exit, and in the Mini Window.
  > **Gotcha:** manual traffic-light repositioning is the #1 source of visual bugs in Arc-style browsers. Write a single `TrafficLightLayoutManager` and unit-test its output for the 6 window states rather than nudging frames in 4 different view controllers.
  > **Gotcha (verified in `NSWindow.h`, M0):** `minSize`/`contentMinSize` and `maxSize`/`contentMaxSize` are **ignored when the content view uses Auto Layout** — the header says so verbatim. Setting `window.minSize` looks right, compiles, and does nothing. Enforce size floors with `greaterThanOrEqualToConstant` constraints on the content view instead. This bites again at §10.1's split-pane min-width clamps and §7.1's 180–420 px sidebar range.

---

## 8. Design system, theming & motion

- [ ] **8.1 Token file** (`Design/Tokens.swift`) — semantic only: `surface/0..3`, `textPrimary/Secondary/Tertiary`, `separator`, `accent`, `dangerous`, `overlayScrim`, `focusRing`. Every token resolves for light **and** dark. **No literal hex outside this file.**
  > **Gotcha (measured in M0, not assumed):** **`.secondaryLabelColor` and `.tertiaryLabelColor` do not meet §21.4 in light mode.** `.secondaryLabelColor` is black at 50 %, which measures **3.95:1** on a white window — under the 4.5:1 floor. Reaching for the system colour for secondary or tertiary text is therefore an accessibility regression, not a shortcut. Luna's `Text.secondary` uses 60 % (5.74:1 light / 6.77:1 dark).
  > Also measured: on macOS 26 `controlBackgroundColor` and `textBackgroundColor` resolve to **exactly** `windowBackgroundColor`, so a system-backed `Surface.raised` would be invisible. It has to be a custom value.
  > `.separatorColor` **is** correct for §8.4's hairline — it resolves to ~9.8 % black / white, which is the spec value. **Correction (M1): the earlier claim that it tracks Increase Contrast was wrong** — see the gotcha below. Its resting value is right; the contrast promotion has to be done by hand.
  > **Gotcha (measured on macOS 26.5, and it changes how all UI code is written):** **Increase Contrast is not an `NSAppearance`.** `NSAppearance(named: .accessibilityHighContrastAqua)` returns the *identical object* (`===`) as `.aqua`, so no dynamic-colour provider can observe it and `NSColor` never gets invalidated. Every token must therefore branch on `NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast` at resolve time, **and every view that draws text or hairlines must redraw on `NSWorkspace.accessibilityDisplayOptionsDidChangeNotification`.** A view that only listens for appearance changes will silently ignore Increase Contrast forever.
- [ ] **8.2 Space gradients** — each Space carries a 2-stop gradient. Ship ~12 curated pairs plus a custom picker. The gradient is used at 3 intensities: full (Space badge, 28 px circle), 12–18 % wash (sidebar background), and a 3–4 px bar/edge glow at the top of the content area.
- [ ] **8.3 Live window tinting from the page** — blend `webView.themeColor` (fallback `underPageBackgroundColor`) into the sidebar/titlebar wash, clamped for contrast (never let a site produce unreadable chrome), animated over ~0.25 s when it changes. This is the single most "Arc-feeling" effect in the whole app; get it right.
- [ ] **8.4 Materials** — on **macOS 26 (D9)** the native Liquid Glass surfaces are the first choice for the §30.1/§30.2/§30.11 chrome. `NSVisualEffectView` with `.sidebar` / `.headerView` materials and `.followsWindowActiveState` is the fallback *and* the Reduce Transparency path, so it gets built either way. 1 px hairlines at ~10 % white / ~8 % black; selection = translucent fill + inner hairline, never a hard blue rect.
  > **Verify before you build (§0.3):** confirm the Liquid Glass API names and availability in the current SDK. One wrong assumption here propagates through every chrome surface in the app.
- [ ] **8.5 Motion spec** — codify and reuse:
  | Interaction | Animation |
  |---|---|
  | Space switch | spring, response 0.30, damping 0.70, content cross-fade 0.18 s |
  | Sidebar collapse/expand | 0.20 s ease-out width + 0.12 s opacity |
  | Hover-peek reveal | 0.10 s delay → 0.15 s ease-out slide |
  | Command Bar in | 0.18 s spring scale 0.96→1.0 + fade, anchored ~20 % from window top |
  | Tab insert/remove | 0.22 s spring height + fade, no list "jump" |
  | Split pane resize | live, no animation; divider snaps at 0.12 s |
  | Theme-colour retint | 0.25 s ease-in-out |
  - **Rule:** nothing animates longer than 0.35 s. Respect `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` — all of the above degrade to instant.
- [ ] **8.6 Typography** — system font throughout; UI 13 pt, sidebar rows 13 pt, Command Bar input 18 pt, monospaced digits for shortcut hints. No custom webfont in chrome.
- [ ] **8.7 Icon set** — SF Symbols only for v1; no hand-drawn set until visual identity is locked.
- [ ] **8.8 Light/dark/auto** + a "dim inactive window" state.
- [ ] **8.9 App icon + wordmark** — must be visually distinct from Arc. Placeholder acceptable until M6.

---

## 9. Command Bar (`⌘T` / `⌘L`)

- [ ] **9.1 Input surface** — floating rounded panel, blurred backdrop scrim, opens over the current tab; `⌘T` = new-tab mode (empty), `⌘L` = edit-current-URL mode (prefilled+selected).
- [ ] **9.2 Result sources**, merged and deduped: open tabs (all Spaces, badged with Space colour) · pinned/favorites · history · bookmarks · archive · search suggestions (engine's suggest endpoint) · app commands ("New Space", "Clear cookies for this site", "Toggle sidebar") · direct URL/IP/`localhost` detection · math/unit quick answers.
- [ ] **9.3 Ranking = frecency + adaptive input history.** Implement explicitly:
  - Score each URL from its **10 most recent visits**: `score = Σ (visitTypeWeight × recencyWeight)`.
  > **Correction (M1):** the original wording said "normalised by sampled visit count". Do **not** normalise. A mean makes one typed visit tie a hundred of them. Firefox divides by the sample and then multiplies back by `visit_count`, which for a ≤10-visit window is the plain Σ with extra arithmetic. The sum is the correct and simpler form.
  - Visit-type weights (Firefox-derived starting point): typed 200, bookmarked 140, link 120, redirect/embed 0.
  - Recency buckets (days): ≤4 → 1.0, ≤14 → 0.7, ≤31 → 0.5, ≤90 → 0.3, else 0.1.
  - **Adaptive history**: remember (typedString → chosenURL). On update `use_count = use_count * 0.9 + 1` (asymptote 10). Adaptive matches rank *above* all frecency results.
  - Acceptance: after a week of dogfooding, the intended result is #1 for ≥90 % of 2-character queries in a manual 30-query test set.
- [ ] **9.4 Inline autofill** of the top URL completion with selected-suffix behaviour; `→` accepts, `Esc` cancels.
- [ ] **9.5 Search engines** — Google/DuckDuckGo/Kagi/Brave/Bing + custom; **bang-style keywords** (`yt cats` → YouTube). Per-Space default.
- [ ] **9.6 Privacy** — suggestions network call must be disableable and must never fire for strings that look like URLs, credentials, or local paths.
- [ ] **9.7 Perf** — results must render within **one frame (16 ms)** of keystroke for local sources; network suggestions merge in asynchronously without reordering under the user's cursor.

---

## 10. Split view

- [ ] **10.1 Up to 4 panes**, horizontal by default, with a vertical option; draggable dividers with min-width clamps; live resize.
- [ ] **10.2 Entry points**: `⌥`+click a link → open in a new pane beside current; drag a sidebar tab onto the content area; command "Split with…"; `⌘⌥→/←` add pane.
- [ ] **10.3 Each pane is a real tab** (appears in the sidebar, keeps its own history/audio state). Selecting a split set in the sidebar restores the whole arrangement.
- [ ] **10.4 Persist split layouts** across relaunch; `⌘⇧←/→` to resize; drag panes to reorder; closing a pane re-flows the rest.
- [ ] **10.5 Focus model** — clearly indicate the focused pane; `⌘L`, find, zoom, and reload act on it.
  > **Gotcha:** N visible panes = N live web processes. Enforce the §19 memory policy here; 4-pane splits should trigger more aggressive hibernation elsewhere.

---

## 11. History, bookmarks & the data layer

- [ ] **11.1 GRDB schema + migrations**: `places(id, url, host, title, lastVisit, visitCount)`, `visits(id, placeId, at, type, fromVisitId)`, `bookmarks(tree)`, `tabs`, `spaces`, `profiles`, `downloads`, `inputHistory(typed, placeId, useCount)`, `siteSettings`, `boosts`.
  > **Corrections from the M1 build — these are better than the original design:**
  > - **`archive` is a VIEW** over `tabs WHERE archivedAt IS NOT NULL`, not a table. An archived tab is still a tab; a copy would be a second source of truth and a second thing to sync (§31).
  > - **`places.frecency` is deliberately absent.** §9.3 scores from the 10 most recent visits, so the score is computed per query. A cached frecency is a stale frecency.
  > - `bookmarks`, `downloads` and `boosts` are not created yet — no consumer exists, and adding a table is a cheap migration.
  > - GRDB pinned at **exactly 7.11.1** (the Swift 6 line: Sendable-audited and ships `SQLITE_ENABLE_FTS5`, so no custom SQLite build). A storage engine should not float.
  > - Every `BrowserStore` method is **`async throws`**, so the actor suspends on GRDB's pool instead of serialising the whole app behind its slowest query.
  > - `recordVisit` **buffers**; the buffer commits after ~1 s, on the next search, or on `flush()`. **The app delegate must `await store.flush()` on quit and on resign-active** or the last second of history is lost.
- [ ] **11.2 FTS5 full-text index** over title + URL + (optional, opt-in) page text captured at `didFinish`. Full-text history search is a genuine differentiator — Arc users ask for it constantly.
- [ ] **11.3 History UI** (`⌘Y`): grouped by day, searchable, multi-select delete, "clear last hour / day / everything", per-site "forget this site" that also purges the matching `WKWebsiteDataStore` records via `removeData(ofTypes:for:completionHandler:)`.
- [ ] **11.4 Bookmarks** — folder tree, but surfaced as *Favorites/Pinned* in the UI; keep an importable/exportable HTML representation.
- [ ] **11.5 Write path must be off the main thread** and batched; never block navigation on a DB write.
- [ ] **11.6 Retention settings** (keep history 30/90/365 days/forever) and an explicit "history is local-only, never uploaded" line in the UI.

---

## 12. Mini Window ("Little Arc" equivalent)

- [ ] **12.1** A small (≈900×640) chromeless window with a 36 px minimal bar: back, URL (13 pt, host-emphasised), share, "Open in main window".
- [ ] **12.2** Used automatically for links opened from **other apps** when we're the default browser; `⌘⌥N` opens one manually.
- [ ] **12.3** Auto-dismiss/archive policy (default 6 h) and "promote to a Space" drag gesture.
- [ ] **12.4** Multiple mini windows stack with slight offset; `Esc` closes.

---

## 13. Peek & link preview

- [ ] **13.1** `⇧`+click (or long-hover intent) on a link opens **Peek**: a centred, rounded, scrim-backed overlay webview over the current tab.
- [ ] **13.2** `Esc` dismisses without ever creating a tab; `↩` promotes it to a real tab in place.
- [ ] **13.3** Peek must reuse a **single pooled webview** to avoid a process spawn per hover.

---

## 14. Apple Passwords, autofill & forms

**Goal:** the user keeps using **Apple's Passwords / iCloud Keychain** — we do not build a password manager and we do not become a second place their secrets live. What we build is the bridge. Read §14.1 before writing any UI copy: part of this is blocked by Apple, and which part decides what we can promise.

- [ ] **14.1 SPIKE (do before any password UI)** — establish what is actually reachable from a Developer ID browser on current macOS, and write the answer into `docs/PASSWORDS.md`:
  - Can we read/write **synchronizable** `kSecClassInternetPassword` items (the ones the Passwords app and iCloud Keychain hold) via `SecItemCopyMatching` / `SecItemAdd` with `kSecAttrSynchronizable`? What exactly does the user see — a per-item keychain ACL prompt with Allow / Always Allow, or a hard denial for Safari-created items?
  - Do items **we** create with `kSecAttrSynchronizable: true` show up in the **Passwords app** and sync to the user's other devices?
  - Acceptance: a throwaway signed build that saves a credential, shows it in the Passwords app, and fills it back on a real login page — or a written "no" with the failure mode.
  > **Hard constraint (verified):** the official **iCloud Passwords browser extension** is **not** an option for us. Its native-messaging helper is allowlisted to specific browsers by **signing identifier and team identifier** since macOS 15.4, and from 15.5 the native messaging host only talks to known browsers. Chrome, Edge and Firefox are on that list; a new browser is not, and there is no published way to apply. Do not design around it, do not imply it in marketing, and do not let this land in onboarding copy.
- [ ] **14.2 Write into Apple's store, not ours** — when the spike passes, every credential Luna saves is written as a **synchronizable Internet password**, so it lands in iCloud Keychain, appears in the **Passwords app**, and syncs to the user's iPhone through Apple rather than through §31. This is the whole feature: Luna has no vault of its own, no master password, and nothing to breach.
- [ ] **14.3 Fill flow** — on a recognised login form, offer matching credentials in a **native popover anchored to the field** (never an injected DOM overlay — a page must not be able to read or spoof it). Match on eTLD+1 with a public-suffix list, never on a bare substring.
- [ ] **14.4 Save / update flow** — after a successful submit, a non-modal "Save password for example.com?" chip with Save / Update / Never for this site. Persist "never" in `siteSettings` (§11.1).
- [ ] **14.5 Password generation** — offer a strong generated password on signup forms, respecting the site's `passwordrules` attribute where present.
- [ ] **14.6 Verification codes** — if §14.1 shows we can read synchronizable TOTP secrets, offer one-tap fill for `one-time-code` fields. If not, at minimum autofill from the clipboard when the user copies a code out of the Passwords app, and don't pretend to more.
- [ ] **14.7 Native-messaging bridge for password extensions** — implement the host side of native messaging in our `WKWebExtensionController` delegate so **1Password, Bitwarden and friends** work through §16. For many users this is the real answer, and it's also the mechanism the iCloud Passwords extension would need if Apple ever allowlists us — build the bridge now, gated behind an explicit per-extension permission.
- [ ] **14.8 Security rules (non-negotiable)** — never persist anything from a `type=password` field without an explicit user action; never fill cross-origin or into an iframe whose origin doesn't match the page; require a recent user gesture before filling; never expose credentials to page JavaScript; and treat a fill into a page reached via a redirect chain as suspicious. Autofill of addresses and payment cards stays **out of scope** — say so in settings rather than half-building it.
- [ ] **14.10 Passkeys need an Apple-gated entitlement — budget it into M4.** WebAuthn in a third-party WKWebView requires `com.apple.developer.web-browser.public-key-credential`, which is request-only. Until it is granted, `PublicKeyCredential` is present in the DOM but dead, so sites offer a passkey flow that silently fails — worse than not offering it. Nook's workaround is to inject a script suppressing `PublicKeyCredential` while waiting; do the same, and **request the entitlement early** because the turnaround is Apple's, not ours. Verify the exact entitlement name against current documentation before filing.
- [ ] **14.9 File a Feedback / DTS request** asking for third-party browsers to be able to participate in Password AutoFill or the iCloud Passwords helper allowlist. Low odds, near-zero cost, and it dates our attempt if the policy ever changes.

## 15. Downloads

- [ ] **15.1 `WKDownloadDelegate`** — two traps found in M1: **`WKDownload.delegate` is `weak`**, so the delegate must be retained somewhere or downloads die silently; and **`decideDestinationUsing` must answer `(url, true)`** — the second value grants the sandbox extension, and `false` fails the write.
- [ ] **15.1a (original wording)** — `decideDestinationUsing:suggestedFilename:` (uniquify into `~/Downloads` or user path), progress via `download.progress`, `didFailWithError:resumeData:` with **resume support**, `didFinish`.
- [ ] **15.2 Route "should this be a download?"** through `decidePolicyFor navigationResponse` → `.download` when `!canShowMIMEType` or `Content-Disposition: attachment`; also handle `navigationAction` → `.download` for `download` attributes.
- [ ] **15.3 Downloads UI**: sidebar popover + a persistent panel; reveal in Finder, retry, open, clear; quarantine flag set correctly (`com.apple.quarantine`) so Gatekeeper still protects the user.
- [ ] **15.4** Warn on executable/dmg/pkg types; block silent auto-downloads from background frames.
- [ ] **15.5** PDF handling: WebKit displays PDFs inline — add a download/print affordance, don't hijack it.

---

## 16. Extensions (`WKWebExtension`) — **v2, except §14.7**

> **Decided 2026-09-17 (§32):** general extension support is **out of v1**. The only extension-adjacent thing we build now is the **native-messaging bridge in §14.7**, so 1Password and Bitwarden work. Everything below waits for M5/v2 — do not start §16.2–§16.6 without explicit go-ahead.

- [ ] **16.1 Host plumbing**: one `WKWebExtensionController` per **profile** (data store), `WKWebExtensionContext` per installed extension, wire the controller into every `WKWebViewConfiguration` of that profile.
- [ ] **16.2 Install from a folder / `.zip` on disk** (developer + power-user path). There is no third-party WebKit extension store; sourcing is the user's problem in v1.
- [ ] **16.3 Permissions UI** — surface requested host permissions, allow per-site grants, and an "extension is reading this page" indicator.
- [ ] **16.4 Toolbar/action surface** — extension action buttons need a home; put them in a compact row at the sidebar bottom or in the site menu, not a fake Chrome toolbar.
- [ ] **16.5 Compatibility reality check**: WebKit's implementation tracks the W3C WebExtensions standard and does **not** cover 100 % of Chrome's MV3 surface. Test against a fixed set: uBlock Origin Lite, Bitwarden, 1Password, Dark Reader, Vimium-class, a translate extension. Document what fails.
- [ ] **16.6** Per-Space extension enable/disable (big differentiator vs Safari).
  > **Resolved:** D9 is now macOS 26, so `WKWebExtension` availability stopped being a constraint. This section is still v2 — see the section header.

---

## 17. Content blocking & privacy

- [ ] **17.1 Rule pipeline**: fetch EasyList/EasyPrivacy → convert to the WebKit content-blocker JSON schema → `WKContentRuleListStore.compileContentRuleList(forIdentifier:encodedContentRuleList:)` → cache the compiled list keyed by a content hash. **Lists download on first run and refresh on a schedule — they are never bundled in the app (D14).** Handle the offline first run without looking broken: blocking simply reports itself as not-yet-ready rather than silently doing nothing.
  > **Gotchas:** compilation is **expensive** (seconds) — do it off the main thread, at install/update time only, never at launch on the hot path. The engine cap is **~150,000 rules**; large combined lists must be split across multiple identifiers or pruned. `if-domain`/`unless-domain` require lowercase, punycoded domains or rules silently never match.
- [ ] **17.2 Default lists**: ads + trackers + annoyances (cookie banners), each toggleable; per-site "disable blocking here" that persists in `siteSettings`.
- [ ] **17.3 Cosmetic filtering** — element-hiding rules via `css-display-none` action type, injected as a rule list (not runtime JS) to avoid flicker.
- [ ] **17.4 Blocked-count badge** per tab + a per-site privacy sheet listing blocked domains.
- [ ] **17.5 ITP is already on** via WebKit — surface it, don't rebuild it. Add a "Clear all site data for this site" one-click action.
- [ ] **17.6 HTTPS-only mode** with an interstitial for downgrades.
- [x] **17.7 Safe Browsing — DECIDED 2026-09-17: option (a), ship without it and say so plainly.** Safe Browsing v4/v5 is non-commercial-only and deprecated for new commercial use; Web Risk is paid per-lookup *and* puts a third party in the URL path, which contradicts D16. Remaining work is copy, not code: an honest paragraph in Settings → Privacy and in the Privacy Policy saying Luna does not check URLs against a malware or phishing list, and noting that macOS still applies XProtect and Gatekeeper to anything downloaded. Revisit only if a free, privacy-preserving list appears.
- [ ] **17.8 Permission prompts** (camera/mic/location/notifications) rendered as our own non-modal chip anchored to the sidebar, with per-site persistence in `siteSettings`.

---

## 18. Reading & page tools

- [ ] **18.1 Find in page** — `webView.find(_:configuration:completionHandler:)` with a custom UI, match count, prev/next, highlight-all. (Do **not** hand-roll JS find; the native API exists.)
- [ ] **18.2 Zoom** — `pageZoom`, `⌘+/-/0`, persisted **per eTLD+1**.
- [ ] **18.3 Reader mode** — inject a Readability-class extractor, render into our own `luna://reader` template with our typography tokens, font-size/width/theme controls.
- [ ] **18.4 PiP & media** — **there is no public per-tab audio API.** `requestMediaPlaybackState()` reports a muted autoplay video as "playing", and `_isPlayingAudio` is SPI, banned by D10. Real audibility comes from a small capture-phase JS listener. Budget for that rather than expecting a property.
- [ ] **18.4a (original wording)** — auto-PiP a playing video when its tab goes background (make it an opt-in setting), global mute-all, per-tab mute, Now Playing / media-key integration via `MPNowPlayingInfoCenter` + `MPRemoteCommandCenter`.
- [ ] **18.8 Web-compat defaults that differ from Safari (found in M0, verify each before relying on it)**
  - `mediaTypesRequiringUserActionForPlayback` must be `[]` to match Safari. Setting `[.audio]` breaks YouTube, because SPA navigations call `play()` outside a user gesture.
  - **Clipboard access and `allowsPictureInPictureMediaPlayback` are on by default in Safari but off for third-party `WKWebView`.** The only known route is KVC onto private preferences (`javaScriptCanAccessClipboard`, `DOMPasteAllowed`). **This collides head-on with D10 (no private SPI in shipping code)** — so it is a decision, not a task: accept a visible web-compat gap, or carve a narrow, documented exception to D10 for preference keys that cannot crash. Escalate to Martin before either.
  - **Do NOT set the private `mediaDevicesEnabled` preference.** It makes the WebContent process eagerly register with `com.apple.audio.AudioComponentRegistrar`, which is denied to third-party WKWebView apps, and the process crashes. `getUserMedia` works through the `WKUIDelegate` permission path (§4.2) without it. A clean example of why D10 exists.
- [ ] **18.5 Print & Save** — `NSPrintOperation` via `webView.printOperation(with:)`, Save as PDF, Save as Web Archive (`createWebArchiveData`), Save Page.
- [ ] **18.6 Screenshot/capture tool** — full-page and region capture via `takeSnapshot` + `WKSnapshotConfiguration`, copy or save.
- [ ] **18.7 Boosts v1** — per-site user CSS and user JS, stored in `boosts`, applied via `WKUserScript` at `documentStart`/`documentEnd` and a per-site style rule; include a "Zap" element picker that generates a hiding rule by clicking an element.
  > **Safety:** user JS runs in the page world with the user's session. Sandbox-warn on import of third-party boosts; never fetch and run remote JS silently.

---

## 19. Performance & memory (non-negotiable budgets)

- [ ] **19.1 Budgets**: cold launch to interactive **< 800 ms**; new-tab command bar **< 100 ms**; 40 tabs across 3 Spaces, 6 live, at **< 3.5 GB** total RSS; sidebar scrolling at 120 fps on ProMotion.
- [ ] **19.2 Hibernation** — a cold tab has **no `WKWebView`** at all: capture `interactionState` + snapshot + title/favicon, tear the view down, release the process. Waking restores via `interactionState`.
  - Policy: keep the active tab + last N used (default 3) + anything playing audio/video + anything with unsaved form input (detect via `beforeunload`-style heuristic) alive; hibernate the rest after 5 min idle or immediately under memory pressure (`DispatchSource.makeMemoryPressureSource`).
  - Reference point: a hibernated tab in mainstream browsers still costs ~39 MB if you keep the renderer warm — our target is ~0 by dropping the webview entirely and paying a wake cost instead.
- [ ] **19.3 Process pool strategy** — share one `WKProcessPool` per profile; WebKit gives each webview its own WebContent process until an internal cap, then shares. Do **not** create a pool per tab (memory explodes) and do not assume you can control the cap.
  > **Recovery policy (M1, measured):** cap rebuilds at **3 per 60 s with a growing delay**. Respawning instantly into a post-wake XPC state is a crash loop, not a recovery. Also call `closeAllMediaPresentations()` when hibernating, or a hibernated tab leaves an orphaned Picture-in-Picture window on screen.
  > **Gotcha (verified bug class):** on macOS, a backgrounded app's WebContent processes get suspended after ~16 minutes, and under memory pressure they can fail to resume, leaving a dead white window. Detect `webViewWebContentProcessDidTerminate(_:)` **and** a heartbeat check on window activation; auto-reload from `interactionState` and show a subtle "restored" toast rather than a blank page.
- [ ] **19.4 Lazy everything** — never create a webview for a tab the user hasn't selected (restored sessions start fully hibernated).
- [ ] **19.5 Instruments pass** per milestone: Allocations, Leaks, Time Profiler, Animation Hitches. Record numbers in `docs/PERF.md` so regressions are visible.
- [ ] **19.6 Energy** — verify we don't prevent App Nap or keep timers running when all windows are closed.

---

## 20. Keyboard & input

- [ ] **20.1 Ship this default map** (all remappable in settings):
  `⌘T` command bar/new tab · `⌘L` edit URL · `⌘S` toggle sidebar · `⌘W` archive tab · `⌘⇧T` reopen last archived · `⌘D` pin/unpin · `⌘⇧K` archive all Today tabs · `⌘1…9` Spaces · `⌥`+click → split · `⇧`+click → Peek · `⌘⇧A` archive view · `⌘Y` history · `⌘F` find · `⌘R`/`⌘⇧R` reload/hard reload · `⌘[`/`⌘]` back/forward · `⌘⌥←/→` prev/next tab · `⌘⇧←/→` resize split · `⌘⌥I` Web Inspector · `⌘,` settings · `⌘N`/`⌘⇧N` window/private window · `⌘⌥N` mini window.
  - **Do not collide with system or common web-app shortcuts** — audit against Gmail/Figma/Notion before finalising.
- [ ] **20.2 Full keyboard-only operation** — every action reachable without a mouse; visible focus ring on all chrome controls.
- [ ] **20.3 Customisable shortcuts UI** with conflict detection.
- [ ] **20.4 Trackpad gestures** — two-finger back/forward (`allowsBackForwardNavigationGestures`), pinch zoom, three-finger swipe between Spaces.

---

## 21. Accessibility

- [ ] **21.1** Full VoiceOver labels/roles on sidebar, command bar, split panes, mini window; correct rotor navigation order.
- [ ] **21.2** Respect Reduce Motion, Increase Contrast, Reduce Transparency (fall back from `NSVisualEffectView` to solid `surface` tokens), Differentiate Without Colour (Spaces must be distinguishable by icon/label, not only gradient).
- [ ] **21.3** Dynamic UI font scaling; verify at largest accessibility sizes that nothing clips.
- [ ] **21.4** Contrast audit: every token pair ≥ 4.5:1 for text, both themes, including over the gradient washes and the live theme-colour tint (clamp the tint if it fails).

---

## 22. System integration

- [ ] **22.1 Default browser flow** — `LSSetDefaultHandlerForURLScheme("http"/"https", bundleID)`. macOS shows its own confirmation sheet; we cannot suppress or reliably read the outcome, so poll `LSCopyDefaultHandlerForURLScheme` afterwards.
  > **Gotcha:** this API is deprecated-with-no-replacement **and is blocked by the App Sandbox**. This is precisely why D8 rules out the Mac App Store. Do not sandbox the main app without re-deciding this.
- [ ] **22.2 `Info.plist`**: `CFBundleURLTypes` for http/https, `CFBundleDocumentTypes` for `.html/.webloc/.pdf`, `NSUserActivityTypes` for Handoff, `LSApplicationCategoryType`.
- [ ] **22.3 Handle `application(_:open:)`** → route to Mini Window or the Space chosen by the routing rules (§25.3).
- [ ] **22.4 Services, Share menu, Shortcuts (App Intents)** — "Open URL in Space X", "Save tab to…", "Archive all tabs".
- [ ] **22.5 Menu bar** — a complete, correct macOS menu (File/Edit/View/History/Bookmarks/Window/Help) even though the UI is chromeless. Every command discoverable here.
  > **Gotcha (proved with a running probe in M0):** **`@main` on a nib-less `NSApplicationDelegate` does not work.** The inherited `main()` is just `exit(NSApplicationMain(...))`, and `NSApplicationMain` only installs a delegate when it loads a **main nib**. With no nib, `NSApp.delegate` stays nil, neither launch callback fires, and the app sits in a dead run loop with no window and no crash. Luna's `AppDelegate` therefore declares its own `static func main()`: `NSApplication.shared` → assign the delegate → `withExtendedLifetime(delegate) { app.run() }`. The `withExtendedLifetime` is load-bearing — `NSApplication.delegate` is a **weak** reference, so a local delegate deallocates immediately without it.
  > **Cosmetic, for when the real Edit menu is built:** AppKit auto-injects Writing Tools, AutoFill, Dictation and Emoji & Symbols into any menu titled "Edit" — and currently injects Dictation twice and Emoji & Symbols three times. Harmless, but don't add them by hand as well.
- [ ] **22.6 Multi-window & multi-display**, fullscreen, Stage Manager, Spaces (the macOS kind) sanity checks. Restore window frames per screen config.
- [ ] **22.7 Continuity** — Handoff of the active tab to/from iPhone/iPad Safari where possible.

---

## 23. Settings, import & onboarding

- [ ] **23.1 Settings window** (SwiftUI, tabbed): General, Spaces & Profiles, Search, Privacy & Blocking, Extensions, Appearance, Shortcuts, Downloads, Advanced (UA overrides, developer flags).
- [ ] **23.2 Import**:
  - **Safari**: `~/Library/Safari/Bookmarks.plist` (binary plist tree), History from `~/Library/Safari/History.db` (SQLite). **Both are protected by TCC** — the user must grant Full Disk Access, or we import from an exported HTML file. Implement the exported-file path first; treat direct reads as a bonus with a clear permission prompt.
  - **Chrome/Edge/Brave**: `~/Library/Application Support/Google/Chrome/Default/Bookmarks` (JSON) + `History` (SQLite; copy the file first — Chrome holds a lock). **Do not attempt to import Chrome passwords** (Keychain-encrypted, requires prompting for the login keychain; out of scope).
  - **Dia** — **build this importer first (§32).** It is Martin's daily browser, so it is both the priority and the source of real dogfooding data. Chromium-family, so expect JSON bookmarks plus a locked History SQLite (copy before reading). Find its actual container path on a running install; do not assume it mirrors Chrome's.
  - **Arc**: JSON sidebar/StorableSidebar.json export if available; otherwise bookmarks HTML.
  - Generic: Netscape bookmarks HTML import/export.
- [ ] **23.3 Onboarding** — 4 screens max: pick theme, import, create first Spaces, set as default browser. Must be skippable and re-runnable.
- [ ] **23.4 Backup/export of our own data** (bookmarks, spaces, boosts, settings) to a single JSON — non-negotiable trust feature for a new browser.

---

## 24. Quality, release & operations

- [ ] **24.1 Testing**: unit tests on frecency, hibernation policy, URL parsing/canonicalisation, blocklist conversion, traffic-light layout. UI tests for launch → command bar → navigate → split → quit → restore. A manual **Top-100-sites compat matrix** re-run each milestone (this is how we catch WebKit-vs-Chrome breakage).
- [ ] **24.2 Crash reporting** — Sentry or a self-hosted alternative; **opt-in**, with scrubbed URLs (never send full URLs or page content).
- [x] **24.3 Telemetry — DECIDED 2026-09-17: there is none.** No analytics, opt-in or otherwise (D16). §24.2 crash reporting stays, opt-in and URL-scrubbed. Settings should say "Luna collects no usage data" and mean it literally. This is a marketing asset and a maintenance saving at the same time.
- [ ] **24.4 Signing & notarisation** — Developer ID Application cert, Hardened Runtime on, `notarytool submit --wait`, staple the ticket, ship a signed DMG. Entitlements: `com.apple.security.network.client`, camera/mic/location usage strings. Keep the entitlement set minimal.
- [ ] **24.5 Sparkle 2 auto-update** — EdDSA-signed appcast over HTTPS, delta updates, "beta channel" toggle.
  > **Gotcha:** Xcode re-signs `Sparkle.framework` but historically not its embedded XPC services/helpers — if notarisation rejects you for "Hardened Runtime disabled in Autoupdate.app", that's the cause. Verify with `codesign -dv --entitlements -` on every nested binary in CI.
- [ ] **24.6 CI** — build + test + sign + notarise on tag; archive dSYMs.
- [ ] **24.7 Legal & docs** — Privacy Policy must state: history and bookmarks are local-only · sync goes to the user's own iCloud and never to us (§31.11) · what search suggestions send and to whom · what crash reports contain · that **no usage data is collected at all** (D16) · and that Luna does **not** check URLs against a malware/phishing list (§17.7). Plus Terms, third-party attributions, and a `SECURITY.md` with a disclosure address.
  - **Licence: GPL-3.0-or-later (D12).** Add `LICENSE` at publication, keep `THIRD_PARTY_NOTICES.md` current from the first borrowed line, and make the corresponding source of every released build available — including Sparkle-delivered updates, which are distribution. Sparkle (MIT) and GRDB (MIT) are GPL-compatible; check any new dependency before adding it. Blocklists are still never bundled (D14), so EasyList never enters the picture.
- [ ] **24.8 Website + changelog + a real support channel.**

---

## 25. Later / v2 backlog (do not start without explicit go-ahead)

- [ ] **25.1 Easel-equivalent** — freeform canvas with live web tiles.
- [ ] **25.2 Notes** — a lightweight per-Space notes surface.
- [ ] **25.3 Link routing rules ("Air Traffic Control")** — pattern → Space/profile/app. e.g. `docs.google.com/spreadsheets/*` always opens in Work. Depends on §5.4.
- [x] **25.4 Sync** — *promoted out of the backlog: see §31. Decided as iCloud/CloudKit, not a custom backend.*
- [ ] **25.5 iOS/iPadOS companion** — the engine layer (§2 `BrowserKit`) should stay UIKit-portable to keep this option open; do not accidentally put AppKit types in the model layer.
- [ ] **25.6 AI surfaces** — page summarise / ask-this-page / auto-title archived tabs. Decide the provider and the privacy story *first*; an always-on "the browser reads your pages" feature needs explicit consent and a Privacy Policy change.
- [ ] **25.7 Tab groups sharing / export a Space as a link.**
- [ ] **25.8 Developer tools of our own** — request log, console mirror, device-size presets on top of `isInspectable`.
- [ ] **25.9 Vertical-video / mini-player mode.**

---

## 26. Known WebKit constraints — the honest list

Keep this table current. Every entry is a thing a Chromium-based project would get for free.

| Constraint | Impact | Our mitigation |
|---|---|---|
| No public **favicon** API | Sidebar identity | Parse + fetch ourselves (§4.7) |
| No **network request interception** / custom protocol handlers for `http(s)` | Can't build request-level blocking, custom caching, or a proxy layer | Use `WKContentRuleList` (§17) + navigation-policy hooks; accept the ceiling |
| No **custom-scheme registration** for web-page-triggered handlers (`registerProtocolHandler`) | `mailto:`-style web app handlers won't work | Handle the common schemes natively; document |
| Storage is **shared across webviews** unless separated by data store | Profiles must be planned up front | `WKWebsiteDataStore(forIdentifier:)` (§5) |
| Data store **removal fails while in use** | Deleting a Space can silently no-op | Tear down all tabs, verify via `allDataStoreIdentifiers` |
| Web process **suspension / non-recovery** in background | Dead white windows | Termination delegate + heartbeat + auto-restore (§19.3) |
| **Content rule limit ~150k**, compilation is slow | Can't ship giant combined lists | Split/prune lists, compile off-thread, cache by hash (§17.1) |
| **WebExtensions ≠ Chrome MV3 parity** | Some extensions won't work | Curated compatibility list + honest docs (§16.5) |
| **iCloud Passwords helper is allowlisted** to known browsers by signing/team ID (macOS 15.4+) | Apple's own extension can never work in Luna | Write synchronizable items straight into iCloud Keychain instead (§14.2); bridge third-party managers (§14.7) |
| Fullscreen API has had **real bugs** across releases | Video sites break | Explicit test matrix per OS update; keep a quirks list |
| **Safari's web-compat profile is ours**, including Chrome-only sites | Ongoing breakage | Per-site UA overrides (§4.6) + a public "report a broken site" path |
| Safe Browsing is **not free for commercial use** | No malware/phishing warnings by default | Decide in §17.7 |

---

## 27. Open questions for Martin — **ALL ANSWERED 2026-09-17**

Every question here was answered on 2026-09-17. The answers and their consequences live in **§32**, and the decisions themselves are folded into §1's table and the relevant sections. This section is kept as a record of what was once uncertain, not as a live list.

| # | Question | Answer |
|---|---|---|
| 1 | The "other browser" you like — name it | **It is a concept, not a shipping browser.** There is no live app to check behaviour against, so §30's written transcription is authoritative and we own every interaction it doesn't specify. |
| 2 | Minimum macOS | **macOS 26+** (D9) |
| 3 | Name, bundle ID, icon direction | **Luna**, `dk.novapps.luna`, new namespace. Icon direction still open (§8.9, M6). |
| 4 | Extensions in v1 or v2? | **v2** — except the §14.7 native-messaging password bridge, which is v1. |
| 5 | Safe Browsing | **Ship without it and say so** (§17.7) |
| 6 | Telemetry | **Zero.** Opt-in crash reports only (D16, §24.3) |
| 7 | Monetisation | **Free. None.** (D15) |
| 8 | Is an iOS companion ever likely? | **Unsure — keep the door open cheaply.** `BrowserKit` stays free of AppKit types; no iOS work is scheduled or promised. |
| 9 | Sync scope | iCloud, with history synced as **typed/bookmarked visits only** (§31.5). The §31.1 spike result comes back to Martin before any sync code is written. |

**Genuinely still open** (none of it blocks M0):
- Icon and wordmark direction (§8.9) — placeholder until M6.
- Whether §31.1's outcome forces the sandbox + helper split. Martin decides on the spike's evidence, not in advance.
- The exact Liquid Glass API surface on the shipping macOS 26 SDK (§8.4). Verify it; do not assume it.

---

## 28. Definition of done (applies to every task)

A task is done when: it builds warning-free under Swift 6 strict concurrency · it has tests where logic exists · it meets its stated acceptance criterion · it respects Reduce Motion / Increase Contrast / Reduce Transparency · it uses design tokens, never literals · it doesn't regress the §19.1 budgets · it works in light **and** dark · it's reachable by keyboard · it's in the menu bar if it's a user-facing command · and any new user-visible data handling is reflected in the Privacy Policy.

---

## 29. Research sources

Arc interaction model & features: [Split View](https://resources.arc.net/hc/en-us/articles/19335393146775-Split-View-View-Multiple-Tabs-at-Once) · [Little Arc](https://resources.arc.net/hc/en-us/articles/19235387524503-Little-Arc-Quick-Lookups-Instant-Triaging) · [Air Traffic Control](https://resources.arc.net/hc/en-us/articles/22932014625431-Air-Traffic-Control-Automate-Your-Link-Routing) · [Keyboard Shortcuts](https://resources.arc.net/hc/en-us/articles/20595231349911-Keyboard-Shortcuts) · [Arc feature overview](https://www.makeuseof.com/features-arc-browser/) · [Arc UI/design breakdown](https://blakecrosley.com/guides/design/arc) · [Boosts 2.0](https://alternativeto.net/news/2023/5/arc-browser-s-boosts-2-0-take-control-of-the-web-and-make-it-look-the-way-you-really-want)

WebKit APIs: [Building Profiles with new WebKit API](https://webkit.org/blog/14423/building-profiles-with-new-webkit-api/) · [WebKit Features in Safari 18.4 (WKWebExtension)](https://webkit.org/blog/16574/webkit-features-in-safari-18-4/) · [WKWebExtension docs](https://developer.apple.com/documentation/webkit/wkwebextension/) · [WKWebsiteDataStore docs](https://developer.apple.com/documentation/webkit/wkwebsitedatastore) · [interactionState](https://developer.apple.com/documentation/webkit/wkwebview/interactionstate) · [underPageBackgroundColor](https://developer.apple.com/documentation/webkit/wkwebview/underpagebackgroundcolor) · [Explore WKWebView additions (WWDC21)](https://wwdcnotes.com/documentation/wwdcnotes/wwdc21-10032-explore-wkwebview-additions/) · [WKURLSchemeHandler](https://developer.apple.com/documentation/webkit/wkurlschemehandler) · [WKWebsiteDataStore.h source](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/UIProcess/API/Cocoa/WKWebsiteDataStore.h)

WebKit limitations: [WebView Usage & Challenges (W3C WebView CG)](https://webview-cg.github.io/usage-and-challenges/) · [WKWebView memory limits](https://developer.apple.com/forums/thread/766309) · [Background renderer suspension issue](https://github.com/andrewyng/openworker/issues/665) · [Hibernated tab cost](https://dev.to/megapixel99/what-a-hibernated-browser-tab-actually-costs-i10)

Content blocking: [WKContentRuleList example](https://github.com/dequin-cl/WKContentRuleExample) · [Blocking Ads and Trackers (rule limits)](https://docs.sudoplatform.com/guides/ad-tracker-blocker/blocking-ads-and-trackers)

Ranking: [Firefox urlbar ranking / frecency](https://firefox-source-docs.mozilla.org/browser/urlbar/ranking.html) · [Ranking browser history suggestions (paper)](https://arxiv.org/pdf/1911.11807)

Prior art on WebKit: [Orion 1.0 (Kagi)](https://blog.kagi.com/orion) · [Orion extension support](https://help.kagi.com/orion/browser-extensions/macos-extensions.html) · [Ora Browser (open-source Arc alternative)](https://www.orabrowser.com/) · [surf](https://github.com/TylerSimmons212/surf) · [chord-browser](https://github.com/Drzaln/chord-browser) · [vane](https://github.com/notnaki/vane)

Platform/distribution: [LSSetDefaultHandlerForURLScheme](https://developer.apple.com/documentation/coreservices/1447760-lssetdefaulthandlerforurlscheme) · [Launch Services from Swift](https://rderik.com/blog/managing-uti-and-url-schemes-via-launch-services-api-from-swift/) · [Sparkle sandboxing](https://sparkle-project.org/documentation/sandboxing/) · [macOS signing/notarisation notes](https://gist.github.com/rsms/929c9c2fec231f0cf843a1a746a416f5)

Passwords: [Apple — Passwords extensions for third-party browsers](https://support.apple.com/guide/passwords/get-extensions-mchlf7ac261e/mac) · [1Password macOS AutoFill](https://www.1password.community/announcements-52/macos-autofill-is-now-available-to-everyone-25254)

Safe Browsing: [Google Safe Browsing v5](https://developers.google.com/safe-browsing/reference/rpc/google.security.safebrowsing.v5) · [Safe Browsing overview](https://developers.google.com/safe-browsing)

---

## 30. Reference UI — what's in `inspiration/`

Transcribed from the reference captures in `inspiration/`. These are **observed traits to match in feel**, not assets to copy. Where this conflicts with §7/§8, this section wins — it's Martin's actual reference.

| File | What it shows | Drives |
|---|---|---|
| `main-tab-bar-and-ui.png` | Floating window, glass sidebar, Essentials tiles, workspace dots, split handle | §30.1–30.11 |
| `non-side-bar-tab-ui.png` | Sidebar-off "top bar" layout with centred URL pill and right action cluster | §30.12–30.14 |
| `downloads-ui.png` | Download-complete popover anchored to the toolbar, with a particle sweep | §30.15–30.16 |
| `transfer-from-other-browsers.png` | Two-pane onboarding import picker | §30.17–30.18 |
| `iphone-mac-sync.png` | New Tab page, Favorites grid, cross-device tabs, iOS companion | §30.19–30.22 |
| `refresh-animation-ui.mov` | Reload/refresh motion | §30.23 |

> **Resolved:** sync is in, over **iCloud** — see §31. The iOS companion stays v2 (§25.5), but the sync layer is designed now so the phone can join later without a migration.

- [ ] **30.1 Floating window treatment** — the whole window is detached and rounded (~18–22 px radius) with the desktop wallpaper visible around it, and the chrome is translucent and tinted by the wallpaper/theme rather than opaque grey. Implies: no standard titlebar, full-window custom shape, heavy `NSVisualEffectView` use, and a shadow that reads on both light and dark desktops.
- [ ] **30.2 Circular glass control buttons** — sidebar-toggle, back, and reload are separate round translucent buttons in a row beside the traffic lights, not a toolbar. Sizes ~34–38 px, hairline border at ~10 % white, hover lifts the fill.
- [ ] **30.3 Domain-only URL pill** — the address field shows just `apple.com`, not the full URL, as a wide rounded pill. Full URL appears on focus/edit (`⌘L`). Right side of the pill holds small inline action icons.
- [ ] **30.4 Inline action slots in the URL pill** — the reference docks two AI icons plus a sliders/settings glyph inside the address pill. **Decided 2026-09-17: no AI in v1 (§32).** Build the pill with those slots reserved and sized, filled only with the settings/site-menu glyph, so adding something later is a fill rather than a relayout. Do not ship an AI affordance that does nothing.
- [ ] **30.5 "Essentials" tile grid** — pinned sites render as large rounded glass **tiles with icon only** (2-up in the screenshot, wrapping to a grid), visually distinct from the text tab rows below. This is our §7.1 Favorites row — build it as tiles, not a compact icon strip.
- [ ] **30.6 Folder rows + explicit "Add Tab" row** — an `Archive` folder row and a `+ Add Tab` row sit between the Essentials grid and the tab list, as first-class list rows with the same metrics as tabs.
- [ ] **30.7 Active-tab treatment** — selected row is a filled translucent pill with a visible hairline border and slightly brighter text; it spans the sidebar width with ~8 px inset. Inactive rows have no background at all.
- [ ] **30.8 Status dots inline in the row** — a small leading dot marks an updated/unread tab (seen on the Discord row). Audio state gets its own trailing indicator (§7.3).
- [ ] **30.9 Bottom utility bar** — profile avatar (circular, bottom-left), workspace/Space **page dots** in a small pill (centre), and a circular archive/trash button (right). The dots double as the Space switcher — adopt this instead of, or alongside, the §5.3 strip.
- [ ] **30.10 Split divider as a grabbable handle** — the reference shows a discrete `◁|▷` handle floating on the divider between panes rather than an invisible hit area. Make the handle appear on hover and support double-click to equalise panes.
- [ ] **30.11 Content pane as a separate card** — the web content sits in its own rounded card inset from the window edge, with a gap between sidebar and content showing the window's tint through it. This is what makes the whole thing read as "floating"; it also means page fullscreen has to animate the card to fill the window.

### From `non-side-bar-tab-ui.png` — the sidebar-off layout

- [ ] **30.12 Top-bar mode is a real second layout, not just a collapsed sidebar — CONFIRMED FOR v1 (D13)** — with the sidebar off, a single translucent bar spans the window: traffic lights → sidebar toggle → back → pinned Essentials as small tiles → **centred** URL pill → a right-hand action cluster. Tabs are not visible at all in this mode; switching happens via the Command Bar. Build it as its own layout controller, with a shared model, and animate the transition between modes.
- [ ] **30.13 Chrome tint follows the page in both layouts** — the reference shows the whole top bar washed pink/lavender on GitHub. Same mechanism as §8.3; make sure the tint pipeline isn't wired only to the sidebar.
- [ ] **30.14 Right action cluster** — extension action icons, `+` (new tab), downloads, and profile/account sit in their own translucent capsule, divided from the pinned tiles by a hairline. This is the natural home for the §16.4 extension buttons — build the capsule once and let both layouts host it.

### From `downloads-ui.png`

- [ ] **30.15 Download-complete popover** — anchored to the downloads button with a visible pointer tail, floating *over* the window edge rather than inside the content area. Row = file-type icon (PDF glyph), middle-truncated filename, confirm/dismiss button. Feeds §15.3; the popover is the primary surface and the full panel is secondary.
- [ ] **30.16 Completion animation** — a particle/sparkle sweep across the filename when a download lands. Time it with the §8.5 budget (≤0.35 s) and kill it entirely under Reduce Motion.

### From `transfer-from-other-browsers.png`

- [ ] **30.17 Import screen layout** — two-pane modal: left is headline + one-line body + `Back`/`Continue` pill buttons (solid primary, muted secondary); right is a gradient wash holding selectable browser rows (app icon, name, trailing radio). The selected row lifts into a brighter card with a filled check. Multi-select.
- [ ] **30.18 Sources to detect and list** — Safari, Chrome, Arc, Dia, Atlas, Helium: i.e. both the Chromium family and the WebKit/Arc family. Detect which are actually installed and list those first; grey the rest.
  > **Copy warning:** the reference promises "bookmarks, history, and **extensions**". We cannot import extensions — §16.2 has no store and §16.5 has no parity guarantee. Word our copy as "bookmarks and history" or we ship a promise we break in the first five minutes.

### From `iphone-mac-sync.png`

- [ ] **30.19 New Tab page** — big centred "Search or type a URL" pill (leading `+`, trailing mic), a Favorites icon grid with labels and a trailing "Add Favorite" slot, and a cross-device tabs button beneath. Currently missing from this document entirely; it is the most-seen screen in the app, so give it its own design pass.
- [ ] **30.20 Voice input** — mic affordance in the New Tab pill and the Command Bar. Needs `SFSpeechRecognizer` + a mic usage string; prefer on-device recognition and say so in the Privacy Policy (§24.7).
- [ ] **30.21 Cross-device tabs surface** — an "open on my other devices" button on the New Tab page, backed by §31.6.
- [ ] **30.22 iOS companion shape** — bottom-anchored URL bar (back · tab switcher · domain · reload · overflow) and an "Added to ★ Favorites" confirmation chip. Reinforces §25.5: keep `BrowserKit` free of AppKit types so the model layer ports as-is.

### From `refresh-animation-ui.mov`

- [ ] **30.23 Reload motion** — watch the clip and transcribe the reload/refresh animation into the §8.5 motion table before building the reload control. Not yet transcribed; it's a video and this document only covers the stills.

---

## 31. iCloud sync (CloudKit)

Everything the user *structures* follows them between Macs — and later, iPhone — through **their own iCloud account**. No Luna account, no Luna server, no password to forget. Local-first: the app is fully usable with iCloud off or unavailable, and sync is an accelerator, never a dependency.

- [ ] **31.1 SPIKE (BLOCKER — do this in M0, before any sync code)** — prove that one signed app can have **both** iCloud entitlements **and** the ability to become the default browser.
  - Build a Developer ID-signed, **non-sandboxed** app with `com.apple.developer.icloud-services` + `com.apple.developer.icloud-container-identifiers` + an embedded provisioning profile; confirm it reaches `cloudd` (no `CKError 6` / "Error connecting to CloudKit daemon") and that `LSSetDefaultHandlerForURLScheme` still works.
  - If those turn out to be mutually exclusive, pick from: (a) sandbox the app and set the default-browser handler from a **non-sandboxed helper/login item**; (b) keep the app unsandboxed and sync via an iCloud Drive ubiquity container instead of CloudKit; (c) drop iCloud sync. Record the outcome in `docs/SYNC.md`.
  - Acceptance: a written answer with a working signed build, before anyone designs a record schema.
  - **Decided 2026-09-17: do not pre-pick a fallback.** Run the spike, write `docs/SYNC.md`, and **stop for Martin's call** before any sync code. All three options above stay on the table until there is evidence.
  > **Why this is first:** §22.1 already establishes that the App Sandbox blocks default-browser registration, and App Sandbox is the configuration Apple documents CloudKit against. The whole sync design rests on which of those constraints bends. Do not build §31.2+ until this is answered.
- [ ] **31.2 Container + schema** — one CloudKit container, private database, custom record zones per data class (`spaces`, `tabs`, `favorites`, `bookmarks`, `boosts`, `settings`, optionally `history`). Zones are the unit of atomic change and of "reset this data type", so split them along the lines the settings UI exposes.
- [ ] **31.3 `CKSyncEngine` integration** (macOS 14+) — let the engine own scheduling, retries, change tokens and subscriptions. **Persist `stateSerialization` across launches** or the engine re-syncs from the wrong token; store it alongside the GRDB database (§11.1).
- [ ] **31.4 Conflict resolution** — `CKSyncEngine` does **not** resolve `CKError.serverRecordChanged` for you. Implement a three-way merge on `failedRecordSaves` and reschedule the save. Per-type rules: tab order = last-writer-wins on a per-Space ordering key; Space rename = last-writer-wins; favorites/bookmarks = union with tombstones; boosts = last-writer-wins per site; deletions = tombstones with a 30-day grace so an offline Mac can't resurrect them.
- [ ] **31.5 Decide and document exactly what syncs**
  - **Syncs:** Spaces (name, colour, order), pinned tabs, Today-tab list, Favorites, bookmarks, boosts, per-site settings, zoom levels, keyboard remaps, general settings.
  - **Never syncs:** cookies, logins, and website storage. A `WKWebsiteDataStore` is local, opaque and not portable — we cannot and should not ship it anywhere. Say this plainly in the UI so nobody expects to stay logged in across Macs.
  - **DECIDED 2026-09-17: option (b).** Only **typed and bookmarked visits** sync — enough for the Command Bar to rank sensibly on a second Mac without shipping every page the user has ever opened to iCloud, even encrypted (§31.8). Link, redirect and embed visits stay local forever.
- [ ] **31.6 Open tabs across devices** — publish a lightweight per-device record (device name, Space, open tab list, updated-at) and render it behind the §30.21 button. Fixed cap per device, refreshed on foreground and on tab-set change, throttled — this is a presence feed, not a live mirror.
- [ ] **31.7 Account & availability states** — handle no iCloud account, signed out mid-session, iCloud Drive disabled, storage full, network offline, and account switch (wipe local sync state and re-seed on identity change). Every one of these degrades to a working local-only browser with a quiet status line in settings, never a modal.
- [ ] **31.8 Sensitive fields** — put URLs and titles in `encryptedValues` on the `CKRecord` so they're end-to-end encrypted rather than merely server-side encrypted. Note in docs that Advanced Data Protection strengthens this further but that we don't require it.
- [ ] **31.9 Schema versioning** — every record carries a schema version; readers ignore unknown fields and never destructively rewrite a record written by a newer client. Write the forward-compatibility rule down before the first release, because the first user with two versions installed will find it.
- [ ] **31.10 Sync settings UI** — master toggle, per-data-type toggles matching the §31.2 zones, "last synced" timestamp, "sync now", and a destructive "remove all Luna data from iCloud" that deletes the zones.
- [ ] **31.11 Legal & privacy** — Privacy Policy must state what goes to iCloud, that it lands in the user's own account rather than ours, that we never see it, and what leaves the device unencrypted (nothing, per §31.8). Ties into §24.7.
- [ ] **31.12 Testing** — two Macs on one account: create/rename/reorder/delete in both, offline edits on both then reconnect, conflicting renames, account switch, storage-full simulation, and a cold restore onto a wiped machine. Automate what's automatable; the rest goes in a written release checklist.

---

## 32. Decision log — 2026-09-17

Sixteen questions, answered in one sitting. **Where this log contradicts an older section, this log wins**, and the section gets corrected when someone next touches it.

### Product shape

| Decision | Consequence |
|---|---|
| **Name is Luna**, bundle `dk.novapps.luna`, internal scheme `luna://` | "ARCWK" is dead everywhere — doc, code, scheme, repo. |
| **Free forever, no monetisation** (D15) | No licensing code, no store integration, no VAT or refund policy, no entitlement checks in Sparkle. |
| **Zero telemetry**, opt-in scrubbed crash reports only (D16) | §24.3 becomes a paragraph of copy instead of a feature. One less SDK, one less Privacy Policy section, one fewer thing to defend. |
| **Open source, GPL-3.0-or-later** (D12) *(revised same day — this row supersedes the original "closed source" answer)* | `LICENSE` lands at publication. Unlocks legal reuse of Nook and Ora (§33) and obliges us to publish source for every released build. |
| **No AI in v1** | §30.4 reserves the layout slot and ships nothing behind it. §25.6 stays in the backlog with its privacy story unwritten. |
| **No Safe Browsing** (§17.7) | Must be stated honestly in Settings and in the Privacy Policy rather than quietly omitted. |

### Platform & scope

| Decision | Consequence |
|---|---|
| **macOS 26+** (D9) | Native Liquid Glass carries the §30 chrome. Verify the API surface before building on it (§8.4). Smaller audience, knowingly accepted. |
| **Both layouts in v1** (D13) | §30.12's top-bar layout is a real layout controller with its own traffic-light states and tint wiring. Budget for it in M2 and expect §7.7's edge cases to double. |
| **Extensions v2; password bridge v1** | Build §14.7 native messaging so 1Password and Bitwarden work. §16.2–§16.6 need explicit go-ahead. |
| **iOS: door open, nothing scheduled** | `BrowserKit` imports no AppKit. Enforce with a build check, not good intentions. |
| **Blocklists fetched at runtime** (D14) | First run needs a network fetch; the offline case must degrade honestly, not silently. |
| **History sync = typed + bookmarked only** (§31.5) | Link visits never leave the Mac. |
| **§31.1 fallback: Martin decides on evidence** | Run the spike, write `docs/SYNC.md`, stop. No pre-committed plan B. |
| **Dia importer first** (§23.2) | Martin's daily browser, so it is both the priority importer and where dogfooding data comes from. |
| **Cadence: one milestone at a time, autonomous within it** | Return at milestone boundaries and at any blocker, with something runnable and the spike results written down. |

---

## 33. Reference implementations (local only — never in this repo)

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
> **The constraint is on the output, not the input.** What lands in Luna has to fit Luna: Swift 6 strict concurrency (D1), the AppKit/SwiftUI split (D2), the §8 token system, the §19 budgets, and our own Tab/Space/Profile model. Nook's ~3,000-line `BrowserManager` and ~4,000-line `Tab.swift` solve their architecture's problems; transplanting them imports a design §0.3 and §19 exist to prevent. Arriving at the same solution because it is the correct one is fine and expected — that is convergence, not copying.
>
> **Verbatim reuse is legal (D12) and occasionally right.** When it is — a gnarly well-tested algorithm, a non-obvious API call sequence — take it, add a header naming the source repo, file path, commit and licence, add an entry to `THIRD_PARTY_NOTICES.md`, and note it in the milestone report. No approval round-trip; this must never stall a milestone.

### What they answer well

Confirming an approach is possible at all (Ora's keychain autofill, for §14.1) · naming the API that solves something WebKit documents badly · the edge case you would otherwise hit in week three · on-disk paths and data formats (Dia's layout, for §23.2) · and, for Zen, how an interaction should feel.

### Immediate leads (evidence, not answers — verify each yourself)

- **§14.1 password spike** — Ora ships iCloud Keychain autofill and Nook ships native messaging with Bitwarden biometric unlock. That is strong evidence both §14.2 and §14.7 are achievable from a Developer ID app. It is *not* proof of what Apple permits us specifically; still build the throwaway signed build and write `docs/PASSWORDS.md`.
- **§23.2 Dia importer** — Nook has an `ImportManager/Dia.swift`, so Dia's on-disk layout is known to be readable. Get the actual paths from the running install on Martin's Mac rather than from their source.
- **§17.1 blocking pipeline** — both Swift browsers already do fetch → convert → compile → cache against the ~150k rule cap, which confirms the approach scales at our size. Write ours from the WebKit documentation.
- **§30 interaction detail** — Zen's spaces, Glance and compact-mode behaviour are the closest shipping analogue to §13 and §7.2. Watch them run; read §30 for what we actually build.
