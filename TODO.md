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
- Chromium/Blink fallback rendering for broken sites. **Also: no second engine at all** — not as a separate build, not per-tab. Researched 2026-09-21 and closed; `docs/ENGINES.md` has the evidence and the conditions that would justify reopening it. Short version: Gecko has had no desktop embedding API since 2011, and a bundled Chromium costs +322 MB, permanent App Store exclusion, no Widevine (so no Netflix/Spotify), our own codec licensing, and a two-week CVE treadmill — while CEF **cannot run Chrome extensions** in the only mode we could embed, which was the main reason to want it.
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
| **Space** | A named, coloured workspace containing its own Pinned tabs + Today tabs, its own history, archive and downloads. **Owns exactly one `WKWebsiteDataStore` — unconditionally, since schema v7.** There is no setting and no way to share one. |
| **Pinned tab** | Persistent, never auto-archives, lives in the upper section of a Space's sidebar list. |
| **Today tab** | Ephemeral tab, auto-archives after N hours (default 12). Lower section of sidebar. |
| **Favorite** | App-icon-sized tile, **per Space** (cap 12, overflow demoted to pinned). Was specced per-Profile; schema v7 deleted the Profile, so per-Space is now both the code and the design (`BrowserStore+Favorites.swift`). |
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
| | | **Worth re-testing (2026-09-20).** Ora ships sandboxed (`com.apple.security.app-sandbox: true`) *and* as a browser with a default-browser manager. The newer `NSWorkspace.setDefaultApplication(at:toOpenURLsWithScheme:)` — which §3.1 already calls — may not carry the old restriction. Unverified; it decides whether MAS reopens. | |
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
│   ├── Model/               # Tab, Space, Favorite, ArchiveEntry, TabGroup
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
- [ ] **M3 — Real-world browser** (§14, §15, §17, §18 — **not** §16, which is v2 and belongs to M5): downloads, find, zoom, media/PiP, permissions, content blocking, history search, import.
- [ ] **M4 — Platform citizen** (§20–§23, §31): default browser, accessibility, settings, crash reporting, Sparkle updates, notarised build, iCloud sync.
- [ ] **M5 — Extensions & polish** (§16, §19): WKWebExtension host, hibernation tuning, perf pass.
- [ ] **M6 — Ship 1.0** (§24): beta, docs, legal, website, DMG.

---

## 4. Core engine layer

- [x] **4.1 `WebViewFactory` + shared configuration**
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
- [x] **4.5 Error pages** — replace WebKit's default failure with our styled page (offline, DNS, TLS, blocked-by-us), with a Retry button routed through the scheme handler.
  > **Redesigned 2026-09-21, and the fault was the type scale.** The pages were built entirely out of
  > the tokens the CSS bridge happened to export — `urlPill` at 13 pt and `sectionLabel` at 12 — so
  > every line on a thousand-point page was set for a 268 pt column, and the whole thing read as a
  > sidebar that had got loose in the window. `TypeScale.pageTitle`/`pageBody` exist for this.
  > Also: **six marks, not one.** Every kind wore the same exclamation-in-a-circle, which says
  > "something went wrong" six times and distinguishes nothing; `.generic` keeps it, because that is
  > honestly all that page knows. The card stands on §5's shadow, the mark sits in a §3.3 well and
  > the address that failed sits in a §3.2 pill — the shapes this window already has.
  > **A page cannot be Liquid Glass and this is not a gap to close.** The material composites what is
  > behind the *window* and a `WKWebView`'s layer is out of process, so a `backdrop-filter` here
  > would blur `--luna-surface-base`, which is flat. What carries across is the plane, the hairline,
  > the corner and the shadow — which is exactly the chrome's Reduce Transparency fallback, and a
  > page is a permanent Reduce Transparency.
  > **Correction, built 2026-09-17:** not every page gets **Retry**. For blocked-by-us and the HTTPS downgrade a retry re-fails by definition, so those two carry **Continue Anyway** instead — `luna://proceed?url=…`, which sets a one-shot `bypassedURL` cleared on the next `didCommit` (and, for the downgrade, persists via `allowInsecure(host:)`). Any blocker must let that one URL through.
- [ ] **4.6 User-Agent policy** — default to system UA + `applicationNameForUserAgent`. Ship a per-site UA override table (Safari UA / Chrome UA) because some sites gate on Chrome. Add a UI toggle in the site menu.
  > **Gotcha (verified in M0):** `applicationNameForUserAgent` **appends to** WebKit's default UA, it does not replace it — and WebKit's default contains **no `Version/` and no `Safari/` token at all**. So a bare `Luna/1.0` ships a UA that compat-sniffing sites reject. Put the Safari tokens first and the product token last, the way Edge and Chrome-on-iOS do: `Version/<os> Safari/605.1.15 Luna/<CFBundleShortVersionString>`. Read the version from `Bundle` so it cannot rot. Confirmed in the wild: Ora sets a *complete* UA string here and consequently ships a doubled `Mozilla/5.0 … AppleWebKit …` prefix; Nook gets it right.
  > **Gotcha:** we inherit **Safari's exact web-compat profile**, including every site that was only ever tested against Chromium. Budget real time for a per-site quirks list. This is the single biggest ongoing cost of choosing WebKit (it's the top complaint about Orion).
  > **This section is the answer to "some sites need Chrome" (2026-09-21).** Most such walls are string-matching the UA, not a real engine gap, so the override table fixes them. For the genuine gaps — WebUSB/WebHID/WebSerial device tools, Widevine-only streams — the honest fallback is a one-key **"Open in Chrome"** handoff (`NSWorkspace.open(urls:withApplicationAt:)`, a few hours' work, not currently a task). Those sites are mostly login-free, so losing the session costs nothing. See `docs/ENGINES.md` §5 for why embedding an engine is the wrong answer to both.
- [x] **4.7 Favicons** — WebKit exposes **no public favicon API**. Implement `FaviconService`: parse `<link rel="icon|apple-touch-icon">` via a small injected script at `documentEnd`, fall back to `/favicon.ico`, fall back to a generated monogram tile from the domain + Space gradient. Cache to disk keyed by eTLD+1, with a memory LRU.
  - Acceptance: 50 mixed sites show correct icons; no icon ever flashes a broken-image glyph.
  > **Corrections from the M1 build:**
  > - **The cache key is host-minus-`www.`, not eTLD+1.** Foundation ships no public-suffix list, and naive last-two-labels hands `a.github.io` whatever `b.github.io` cached. Revisit only if we ever bundle a PSL.
  > - **SVG favicons do not decode in ImageIO**, so they fall through to `/favicon.ico`.
  > - The monogram fallback tier needs the Space gradient, so it belongs to the UI layer, not to `FaviconService`.

---

## 5. Spaces (storage isolation)

> **Full contract: `docs/SPACES-SPEC.md`** (2026-09-18). Arc is installed on this
> machine, so its model was read off its own `StorableSidebar.json` rather than
> from documentation; Zen, Floorp, Ora, Nook, Refrax, Crest, Firefox containers
> and Chromium profiles were read from source. The spec supersedes the lines
> below where they disagree, and §11 of it lists every correction.
>
> **Dia is not a second target.** Its `User Data` holds plain Chromium profiles
> and tab groups, with no space or sidebar keys at all — the same company shipped
> Arc with Spaces and its successor without them. What the owner uses in Dia
> today is **folders**, so §4 of the spec designs the sidebar as a node tree now
> and ships folders later (S6): retrofitting a tree onto a flat list with real
> user data is the expensive version of that work.


- [x] **5.1 `ProfileStore`** wrapping `WKWebsiteDataStore(forIdentifier: UUID)`.
  - Persist the UUID ↔ profile-name mapping ourselves (in SQLite). Identifiers are **not** recoverable from WebKit alone beyond `WKWebsiteDataStore.allDataStoreIdentifiers`.
  - Deletion: `WKWebsiteDataStore.remove(forIdentifier:)` — **fails while any live `WKWebView` still uses the store.** Tear down and deallocate every tab in that profile, then remove, then verify against `allDataStoreIdentifiers`.
  - Data lands in `~/Library/WebKit/WebsiteDataStore/<UUID>/`.
- [ ] **5.2 Space model**: name, icon (SF Symbol), gradient pair, `dataStoreIdentifier`, ordered pinned tabs, ordered today tabs, "auto-archive after" override.
- [x] **5.10 Move Space switching to `⌃1…⌃9`; reserve `⌘1…⌘9` for sidebar items.** Shipped code binds Spaces to `⌘1…⌘9` (`MainMenu.setSpaces`) and Luna has **no "go to tab N" at all**, so the most valuable shortcut namespace in the app is spent on Spaces. Arc puts Spaces on `⌃1…⌃9` and ⌘-number on sidebar items; Dia uses `Ctrl+1–9`; Vivaldi uses `⌘⇧<n>`. Three products, three modifiers, none of them plain ⌘-number — which means "go to tab N" in Safari, Chrome, Firefox, Edge and Arc. Add `⌘⌥←/→` for prev/next Space and a two-finger sidebar swipe. Breaking change to a shipped binding; cheaper now than ever again.
- [ ] **5.11 Design for the 94%.** The Browser Company published the number when Arc went into maintenance: **"Only 5.52% of DAUs use more than one Space regularly."** Their own diagnosis was that Arc "was simply too different, with too many new things to learn, for too little reward" — and Spaces came back anyway, because the 5.52% would not let go. Low reach, extreme attachment. **Out of the box Luna shows one unnamed Space, no switcher, no chrome tint and no onboarding step; the Space UI appears when a second Space is created.** Spaces is something Luna grows into, never something it opens with.
- [ ] **5.12 Auto-archive must be disableable (§12.3).** Arc's default is **12 h** idle for unpinned tabs, reset on view, per-Profile timing, synced, with pinned and media-playing tabs exempt — and **"Auto Archive can't be disabled."** That last decision cost them a one-time explainer banner for new members and a defensive help article. Ship 12 h as the default with Off / 6 h / 12 h / 24 h / 7 d / 30 d, never archiving a tab playing media or holding unsaved input. **Correction 2026-09-22: §19.2 does NOT already have both exemptions for this sweep.** `HibernationPolicy` has them; `AutoArchive.idleTabs` exempts only pinned/essential/archived/active/internal-pages, so a tab playing audio can currently be auto-archived. Also missing from `AutoArchive.choices`: the 7 d and 30 d options (ships 6/12/24/never).
- [x] **5.13 Favorites: cap 12, allow zero, load lazily.** Arc's caps, including the lazy load it had to retrofit — *"We used to keep your Favorites loaded at all times, but now we only load them if they've been used recently."* A permanently-resident global tier is a memory problem.
- [x] **5.14 Gradient legibility and a route back to neutral (§8.2).** Derive sidebar and label foregrounds from the chosen gradient's **luminance**, not a fixed token; one click back to neutral; keep Light/Dark **global** and label it as global; honour Reduce Motion on the cross-fade and Reduce Transparency on the gradient. Zen shipped the contrast bug (light gradient → unreadable titles) and has an open issue for being unable to unset a gradient; Arc needed a help article for "How Do I Restore the Default Theme" and shipped a dark-mode contrast fix; Dia's refresh went to neutral tab groups by default.
- [x] **5.6 Space lifecycle — the gaps `docs/SPACES-SPEC.md` §10 scopes.** *(Done 2026-09-22. Every premise this item was written on is now false: `renameSpace`/`reorderSpace`/`setIcon`/`setGradient` all exist and their Settings rows are wired; deletion offers archive-or-adopt and is undoable. The "many-Spaces-to-one-Profile is modelled and unreachable" complaint and the missing `delete(profileID:)` describe a capability schema v7 **deliberately removed** — one jar per Space, no sharing.)*
  > **Reordering is the biggest hole in the entire prior art — nobody implements it.** Nook persists an index with no reorder function, Ora has no order field at all, Refrax sorts by `position` but never reorders. Copy Nook's one good idea: on load, compare the persisted order against `0..<n` and renumber if it differs. That self-heal makes `reorderSpace` trivial and immunises `delete(spaceID:)` against the gaps every delete leaves.
  > **Store deletion is a retry loop, not a call.** Crest and DuckDuckGo arrived at the same shape independently: release the web views → check `allDataStoreIdentifiers` → `remove(forIdentifier:)` → on failure fall back to `removeData(ofTypes:modifiedSince:)` so the *data* goes even if the directory survives → back off `[125ms, 250ms, 500ms, 1s, 2s, 4s]` → persist the id to a pending-removal set in `UserDefaults` (**not** GRDB — it must survive a database wipe). Plus an orphan sweep at launch, because WebKit is the registry.
- [ ] **5.7 "Last tab" must be evaluated over the window, never over the visible Space.** zen#9272: Zen evaluated it per-Space, so closing the one tab in Space B quit the browser while Space A had five open — and it took the window-close path, so nothing restored. One user lost ~500 tabs. Floorp's equivalent (floorp#2152) is **still open**, the maintainer conceding the design is hard. Luna is safe today only because `closeTab` archives and never closes a window; decide this in the close handler before adding any window-close rule.
- [x] **5.8 Make the Profile boundary visible (spec §9).** *(OBSOLETE 2026-09-22 — solved by elimination, not by labelling. Schema v7/v8 gave every Space its own jar, history, archive and downloads, so the two-identical-rows collision this item describes cannot occur. The Command Bar deliberately carries no Space badge and says so in `CommandBarResultsView.swift:233`; rationale pinned by `CommandBarJarIdentityTests`. Original text kept below for provenance.)*
  > ~~ The most-cited confusion in both ecosystems, predicted by Mozilla in 2016 and still live: two identical "Switch to tab" rows for the same site in two Profiles, no way to tell which account. §9.2's Space-colour badge is not enough — the Space colour does not say whose cookies you are about to use. Profile identity belongs on the Command Bar, history, archive and downloads.~~
- [ ] **5.9 Key `siteSettings` on `(profileID, host)`, not host alone.** Firefox shipped per-container permission isolation and left it **off by default**, so camera access granted in Work leaks to Personal; Chrome's is genuinely per-profile. Luna claims real isolation, so it has to be real here too.
- [x] **5.3 Space switcher UI**: horizontally swipeable strip at the bottom of the sidebar + `⌘1…⌘9` + `⌃⇥`-style cycling. Switching cross-fades the sidebar content and re-tints the whole window (§8).
- [ ] **5.4 Per-Space default search engine + per-Space "open links here" rule** (the foundation for §25's link routing).
- [ ] **5.5 Cookie/session sanity tests**: log into the same site in two Spaces with separate profiles; confirm independent sessions survive relaunch.
  > **Correction (2026-09-18):** the default-store warning is stale. **Luna never uses the default store** — `ProfileStore.dataStore(for:)` always calls `WKWebsiteDataStore(forIdentifier:)`, so the real migration is identified → identified. Two things follow. (a) `fetchData(of:)` / `restoreData(_:)` exist in the macOS 26 SDK (verified in the header on this machine) and **might** copy a session between stores — the header does not say cross-store restore is supported, so **spike it before promising it in the UI** (§15.1 precedent). (b) Reassigning a Profile must **rebuild every web view in that Space**, or already-loaded tabs keep writing to the old store — exactly Nook's shipped bug, and zen#15023.
  > **The all-zero UUID throws an Objective-C exception Swift cannot catch** ("Throws exception if identifier is 0", `WKWebsiteDataStore.h`). `dataStoreIdentifier` is a `NOT NULL UNIQUE` blob with no value check and nothing validates it on read. Guard it at the GRDB read boundary; none of the five researched codebases does.
- [ ] **5.16 Rename `ProfileStore` → `SpaceJarStore`** *(found 2026-09-22)*. The type is live and its **API already migrated** (`dataStore(for space: Space)`, cache keyed by `space.id`, used on five paths from `BrowserSession.swift:190`). Only the filename and header comment are stale — they still describe "one store per Profile" and a `profiles.dataStoreIdentifier` column that no longer exists. Pure rename, ~8 call sites, no behaviour change.
- [ ] **5.15 Private/incognito window** = `WKWebsiteDataStore.nonPersistent()`, visually distinct tint, excluded from history writes, no crash-restore.

---

## 6. Tab model, lifecycle & session persistence

- [x] **6.1 `Tab` model**: id, spaceId, kind (`pinned|today|favorite`), url, title, faviconKey, themeColor, createdAt, lastActiveAt, archivedAt, parentTabId (for tree/child grouping), `interactionState: Data?`, snapshot path.
- [x] **6.2 Session persistence via `interactionState`** — **the blob must be cached outside the web view, at every `didFinish`.** `interactionState` reads back **nil once the WebContent process is dead**, which is precisely the case §19.3 has to recover from. Read it late and there is nothing to restore.
- [x] **6.2a (original wording)** — capture `webView.interactionState` on background/blur/quit; restore into a fresh webview to bring back full back/forward history and scroll position. Store as `Data` blob in SQLite.
  - Acceptance: quit with 30 tabs across 3 Spaces → relaunch restores order, scroll positions, and back-history for each.
- [x] **6.3 Auto-archive** — background task archives Today tabs idle > N hours (default 12; user-settable 6h/12h/24h/never). Pinned/Favorites exempt. Archive keeps title/url/favicon/snapshot for 30 days.
- [x] **6.4 Archive browser** (`⌘Y`) with search + restore.
- [ ] **6.5 Tab tree** — links opened from a tab become indented children under it, collapsible. (Arc does this implicitly; make it explicit and better.)
- [ ] **6.6 Drag & drop** — reorder within list, move between sections, move between Spaces (drag onto the Space strip), drag out to a new window, drag a URL in from Finder/other apps, drag a tab's URL *out* to other apps.
- [x] **6.7 Undo stack** for close/archive/move (`⌘Z` inside the sidebar context).
- [ ] **6.8 ⚠️ Half-built, costing CPU and disk (found 2026-09-22): `TabLifecycle.snapshot(for:)` has ZERO callers.** Snapshots are captured on every tab blur and before every hibernate, downsampled, PNG-encoded and LRU'd to 200 MB — and nothing displays them. Either wire the consumer or stop capturing. Original item: **6.8 Snapshots** — `webView.takeSnapshot(with:)` on blur, downsampled, for the sidebar hover preview and the archive. Cap disk usage (e.g. 200 MB LRU).

---

## 7. Sidebar (the signature surface)

- [x] **7.1 Layout**: Favorites grid (icon tiles) → Pinned list → divider → Today list → Space strip. Width draggable **250–420 px (default 280)**, persisted — the 250 floor is derived arithmetically from the two 52 pt rows, see `Design/Metrics.swift:108-145` and `docs/UI-SPEC.md:34`. *(The old "180–420" was never achievable.)*
- [x] **7.2 Collapse + hover-peek**: `⌘S` collapses to a ~48 px rail (or fully hidden); hovering the left window edge slides the sidebar over the content as a floating panel with a shadow, after a ~0.1 s intent delay, with a ~0.15–0.2 s ease-out reveal. It must **not** trigger while the pointer is merely travelling to the traffic lights.
- [x] **7.3 Row design**: favicon, title (single line, truncating), close/archive affordance on hover, audio-playing indicator + click-to-mute, loading shimmer, unread/updated dot.
- [x] **7.4 Selection & keyboard**: full arrow-key navigation, type-ahead, `⌘⌥←/→` to move between tabs, `⌘W` closes (archives) the current tab, `⌘⇧K` archives all Today tabs.
- [ ] **7.5 Folders** inside a Space (drag one tab onto another to create).
- [x] **7.6 Sidebar-on-right option** (differentiator; Arc doesn't do it well).
- [x] **7.7 Traffic-light handling**: custom titlebar, `titlebarAppearsTransparent`, `NSWindow.toolbar` removed; traffic lights must be inset into the sidebar and must re-position correctly when the sidebar collapses, on fullscreen enter/exit, and in the Mini Window.
  > **Gotcha:** manual traffic-light repositioning is the #1 source of visual bugs in Arc-style browsers. Write a single `TrafficLightLayoutManager` and unit-test its output for the 6 window states rather than nudging frames in 4 different view controllers.
  > **Gotcha (verified in `NSWindow.h`, M0):** `minSize`/`contentMinSize` and `maxSize`/`contentMaxSize` are **ignored when the content view uses Auto Layout** — the header says so verbatim. Setting `window.minSize` looks right, compiles, and does nothing. Enforce size floors with `greaterThanOrEqualToConstant` constraints on the content view instead. This bites again at §10.1's split-pane min-width clamps and §7.1's 250–420 px sidebar range.

---

## 8. Design system, theming & motion

- [x] **8.1 Token file** (`Design/Tokens.swift`) — semantic only: `surface/0..3`, `textPrimary/Secondary/Tertiary`, `separator`, `accent`, `dangerous`, `overlayScrim`, `focusRing`. Every token resolves for light **and** dark. **No literal hex outside `Design/`'s token files, and every hex entry point is `private`.**
  > **Amended 2026-09-18.** "This file" was literally false once the twelve Space gradients shipped. They are `GradientPair`/`RGBA` values that cross the SQLite boundary and become *user data* the moment someone picks one, so they are not `NSColor` and cannot be chrome tokens — and `Tokens.swift` was 380 lines against SwiftLint's 400 limit, so they did not fit either. They live in `Design/SpacePalette.swift`, whose header says so.
  > The rule is kept by the mechanism it always relied on rather than by the filename: each file's hex initialiser is `private`, and `SpacePalette`'s can only produce a `GradientPair`, so nothing there can spell a chrome colour even by accident.
  > **Gotcha (measured in M0, not assumed):** **`.secondaryLabelColor` and `.tertiaryLabelColor` do not meet §21.4 in light mode.** `.secondaryLabelColor` is black at 50 %, which measures **3.95:1** on a white window — under the 4.5:1 floor. Reaching for the system colour for secondary or tertiary text is therefore an accessibility regression, not a shortcut. Luna's `Text.secondary` uses 60 % (5.74:1 light / 6.77:1 dark).
  > Also measured: on macOS 26 `controlBackgroundColor` and `textBackgroundColor` resolve to **exactly** `windowBackgroundColor`, so a system-backed `Surface.raised` would be invisible. It has to be a custom value.
  > `.separatorColor` **is** correct for §8.4's hairline — it resolves to ~9.8 % black / white, which is the spec value. **Correction (M1): the earlier claim that it tracks Increase Contrast was wrong** — see the gotcha below. Its resting value is right; the contrast promotion has to be done by hand.
  > **Gotcha (measured on macOS 26.5, and it changes how all UI code is written):** **Increase Contrast is not an `NSAppearance`.** `NSAppearance(named: .accessibilityHighContrastAqua)` returns the *identical object* (`===`) as `.aqua`, so no dynamic-colour provider can observe it and `NSColor` never gets invalidated. Every token must therefore branch on `NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast` at resolve time, **and every view that draws text or hairlines must redraw on `NSWorkspace.accessibilityDisplayOptionsDidChangeNotification`.** A view that only listens for appearance changes will silently ignore Increase Contrast forever.
- [x] **8.2 Space gradients** — **still unbuilt as of M1: every new Space gets the same default pair.** The twelve curated gradients have no home in `Design/` yet, which is the one visible gap in Spaces.
- [ ] **8.2a (original wording)** — each Space carries a 2-stop gradient. Ship ~12 curated pairs plus a custom picker. The gradient is used at 3 intensities: full (Space badge, 28 px circle), 12–18 % wash (sidebar background), and a 3–4 px bar/edge glow at the top of the content area.
- [ ] **8.3 Live window tinting from the page** — blend `webView.themeColor` (fallback `underPageBackgroundColor`) into the sidebar/titlebar wash, clamped for contrast (never let a site produce unreadable chrome), animated over ~0.25 s when it changes. This is the single most "Arc-feeling" effect in the whole app; get it right.
- [x] **8.4 Materials** — on **macOS 26 (D9)** the native Liquid Glass surfaces are the first choice for the §30.1/§30.2/§30.11 chrome. `NSVisualEffectView` with `.sidebar` / `.headerView` materials and `.followsWindowActiveState` is the fallback *and* the Reduce Transparency path, so it gets built either way. 1 px hairlines at ~10 % white / ~8 % black; selection = translucent fill + inner hairline, never a hard blue rect.
  > **Verify before you build (§0.3):** confirm the Liquid Glass API names and availability in the current SDK. One wrong assumption here propagates through every chrome surface in the app.
- [x] **8.5 Motion spec** — codify and reuse:
  | Interaction | Animation |
  |---|---|
  | Space switch | spring, response 0.30, damping 0.70, content cross-fade 0.18 s |
  | Sidebar collapse/expand | 0.20 s ease-out width + 0.12 s opacity |
  | Hover-peek reveal | 0.10 s delay → 0.15 s ease-out slide |
  | Command Bar in | 0.18 s spring scale 0.96→1.0 + fade, anchored ~20 % from window top |
  | Tab insert/remove | 0.22 s spring height + fade, no list "jump" |
  | Split pane resize | live, no animation; divider snaps at 0.12 s |
  | Theme-colour retint | 0.25 s ease-in-out |
  | Control button press | fill one step up + 5 % swell, 0.16 s spring, damping 0.62 |
  - **Rule:** nothing animates longer than 0.35 s. Respect `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` — all of the above degrade to instant.
  > **Added (M1): press.** The table had hover and nothing for the other half of a click. Every chrome button now answers both — `Surface.hover` under the pointer, `Surface.selected` under a press, plus a 5 % swell that springs back on release, which is the macOS 26 Liquid Glass press Martin captured for the reference. A button with no material of its own hands the swell to the surface that has one. Under Reduce Motion the swell lands without the spring and the fill still cross-fades; the press is never invisible.
  > **Extended (M1): §3.5's Space dots.** They were the one control left with no answer at all — a dot took a click and said nothing until the Space had already changed. The wash needs something to sit on, so each dot carries a chip the size of its own slot (`spaceDotChip` = `spaceDotPitch`, 14 pt: a 6 pt hover target is no target), and the press goes to the **pill**, which is the glass the dots stand on. Measured on screen: hover changes exactly 14 × 14 pt and nothing else, a press changes the whole pill.
- [x] **8.6 Typography** — system font throughout; UI 13 pt, sidebar rows 13 pt, Command Bar input 18 pt, monospaced digits for shortcut hints. No custom webfont in chrome.
- [x] **8.7 Icon set** — SF Symbols only for v1; no hand-drawn set until visual identity is locked.
- [ ] **8.8 Light/dark/auto** + a "dim inactive window" state.
- [x] **8.9 App icon + wordmark** — must be visually distinct from Arc. Placeholder acceptable until M6.

---

## 9. Command Bar (`⌘T` / `⌘L`)

- [x] **9.1 Input surface** — floating rounded panel, blurred backdrop scrim, opens over the current tab; `⌘T` = new-tab mode (empty), `⌘L` = edit-current-URL mode (prefilled+selected).
- [ ] **9.2 Result sources**, merged and deduped: open tabs (all Spaces, badged with Space colour) · pinned/favorites · history · bookmarks · archive · search suggestions (engine's suggest endpoint) · app commands ("New Space", "Clear cookies for this site", "Toggle sidebar") · direct URL/IP/`localhost` detection · math/unit quick answers.
  > **Correction (M1): an archive row is a place, not a session.** The bar's archive rows sit in the same list as history's, wearing the same favicon and the same title, so choosing one and landing half way down the page you were on last week is a session resuming behind a gesture that never asked for it. `unarchiveTab(_:resumingSession:)` — the bar passes `false` and the tab comes back at the top of its page, same tab, same Space, same name. `⌘⇧T` and §11.3's list both mean "reopen the tab I closed" and still pass `true`, which is what `interactionState` is for.
- [x] **9.3 Ranking = frecency + adaptive input history.** Implement explicitly:
  - Score each URL from its **10 most recent visits**: `score = Σ (visitTypeWeight × recencyWeight)`.
  > **Correction (M1):** the original wording said "normalised by sampled visit count". Do **not** normalise. A mean makes one typed visit tie a hundred of them. Firefox divides by the sample and then multiplies back by `visit_count`, which for a ≤10-visit window is the plain Σ with extra arithmetic. The sum is the correct and simpler form.
  - Visit-type weights (Firefox-derived starting point): typed 200, bookmarked 140, link 120, redirect/embed 0.
  - Recency buckets (days): ≤4 → 1.0, ≤14 → 0.7, ≤31 → 0.5, ≤90 → 0.3, else 0.1.
  - **Adaptive history**: remember (typedString → chosenURL). On update `use_count = use_count * 0.9 + 1`. Adaptive matches rank *above* all frecency results.
  > **Clarification (M1):** 10 is the **fixed point** of `x = 0.9x + 1`, not a clamp — the formula is self-limiting and converges to 10 from below without reaching it. Do not add a `min(_, 10)`; it looks correct and hides the fact that no clamp is needed.
  > **Correction (M1):** §9.2 lists "open tabs", "pinned/favorites" and "bookmarks" as three sources. In Luna's model an Essential or pinned tab **is** a `Tab` with a `kind`, and §11.1 no longer creates a `bookmarks` table. It is one source, not three.
  - Acceptance: after a week of dogfooding, the intended result is #1 for ≥90 % of 2-character queries in a manual 30-query test set.
- [x] **9.4 Inline autofill** of the top URL completion with selected-suffix behaviour; `→` accepts, `Esc` cancels.
- [ ] **9.5 Search engines** — Google/DuckDuckGo/Kagi/Brave/Bing + custom; **bang-style keywords** (`yt cats` → YouTube). Per-Space default.
- [ ] **9.6 ⚠️ LIVE BUG (found 2026-09-22): the guard does not cover credentials or local paths.** `user:pass@example.com` fails `CommandBarURL.direct` (`explicitScheme` rejects `user:`) and `/Users/me/secret.txt` has an empty host — both fall through to `SearchSuggestions.request` and **leave the Mac**. Fix is one guard by `CommandBarController.swift:298` (`@` before the first `/`, or a leading `/` or `~`). Original item: **9.6 Privacy** — suggestions network call must be disableable and must never fire for strings that look like URLs, credentials, or local paths.
- [x] **9.7 Perf** — results must render within **one frame (16 ms)** of keystroke for local sources; network suggestions merge in asynchronously without reordering under the user's cursor.
  > **Correction (M1):** this reads as though only network suggestions are asynchronous. **The local store query is asynchronous too, and it is the harder case because it always runs.** It needs the same no-reorder rule: once the user has pressed ↓/↑, late results may only be *appended*. The in-memory sources (tabs, Spaces, adaptive table) are what must resolve synchronously inside the frame; the adaptive table is therefore loaded into memory up front, precisely because adaptive rows rank #1 and cannot arrive a frame late.
  > **Also (M1): the list does not change while the bar is opening.** Replacing it rebuilds eight row views and re-draws them under live glass, on the thread running the bar's own 0.18 s animation — so the history query landing mid-morph was a visible freeze. It only ever showed up when the bar opened on an *address*: `⌘T` on a new tab asks SQLite a question whose answer it already shows, so nothing is rebuilt. Asynchronous results that land inside that window are held and applied the moment it closes. §9.7's 16 ms budget is about a *keystroke*, and nothing is typed in those 0.18 s.
  > **And (M1, second pass): the bar waits for the store before it opens at all.** Deferring the rows moved the re-rank from the middle of the morph to the end of it — the same eight rows, reordered the instant the bar settled. Measured, from the click: 65 ms to the panel's first composite (20 of it the commit, 15 `makeFirstResponder`), then the store's answer about 9 ms later, because the query cannot even *start* until the main thread lets go. So the bar is drawn at the pill's own size first, held there until the query lands or 100 ms pass, and only then opens — and what lands during the 0.18 s after that is applied **append-only**, so a row the bar opened with never moves. The redundant second query the adaptive table used to trigger on every first open is gone with it: an empty query has no adaptive rows to add.
  > **Also:** §9.4's "`Esc` cancels" and §9.1's "`Esc` dismisses" collide. Precedence is two-stage — the first `Esc` cancels an inline completion, the second dismisses the panel.

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
- [x] **11.5 Write path must be off the main thread** and batched; never block navigation on a DB write.
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

- [x] **14.1 SPIKE (do before any password UI)** — establish what is actually reachable from a Developer ID browser on current macOS, and write the answer into `docs/PASSWORDS.md`:
  - Can we read/write **synchronizable** `kSecClassInternetPassword` items (the ones the Passwords app and iCloud Keychain hold) via `SecItemCopyMatching` / `SecItemAdd` with `kSecAttrSynchronizable`? What exactly does the user see — a per-item keychain ACL prompt with Allow / Always Allow, or a hard denial for Safari-created items?
  - Do items **we** create with `kSecAttrSynchronizable: true` show up in the **Passwords app** and sync to the user's other devices?
  - Acceptance: a throwaway signed build that saves a credential, shows it in the Passwords app, and fills it back on a real login page — or a written "no" with the failure mode.
  > **Done 2026-09-19 — `docs/PASSWORDS.md` has the write-up.** The answer is a *no* on the iCloud half, with the failure mode: ad-hoc signed, `kSecAttrSynchronizable` **and** `kSecUseDataProtectionKeychain` both return `-34018 errSecMissingEntitlement`; local internet passwords add, read, update and delete cleanly. Safari's own items turn out to be unreachable at *any* signature — they sit in Apple's keychain access groups, so it is neither an ACL prompt nor a denial, just `errSecItemNotFound`.
  > **Hard constraint (verified):** the official **iCloud Passwords browser extension** is **not** an option for us. Its native-messaging helper is allowlisted to specific browsers by **signing identifier and team identifier** since macOS 15.4, and from 15.5 the native messaging host only talks to known browsers. Chrome, Edge and Firefox are on that list; a new browser is not, and there is no published way to apply. Do not design around it, do not imply it in marketing, and do not let this land in onboarding copy.
- [x] **14.2 Write into Apple's store, not ours** — when the spike passes, every credential Luna saves is written as a **synchronizable Internet password**, so it lands in iCloud Keychain, appears in the **Passwords app**, and syncs to the user's iPhone through Apple rather than through §31. This is the whole feature: Luna has no vault of its own, no master password, and nothing to breach.
  > **Built.** `CredentialStore` attempts the synchronizable write first every time and falls back to local **only** on `-34018`, latching the result in `Capability`; any other failure is surfaced rather than silently downgraded. The iCloud half switches itself on when M4 signing lands, and `migrateLocalItemsToSynced()` carries across whatever was saved before then.
  > **Fixed 2026-09-20 — Luna was reading other applications' credentials.** Queries were scoped with `kSecAttrService`, which the Keychain **silently ignores** on an internet password, so `baseQuery` matched on hostname alone. The picker offered a `github.com` item written by `git-credential-osxkeychain` a year earlier, whose secret is an access token; `save` and `delete` shared the query, and `migrateLocalItemsToSynced()` would have swept every internet password in the keychain and deleted the originals on the first launch after signing. Now scoped by `kSecAttrCreator` **and** `kSecAttrSecurityDomain` — the second because the first is not part of the uniqueness constraint, so saves collided with another app's row. Pinned by `Tests/Passwords/CredentialOwnershipTests.swift`.
  > **Test on the day M4 signing lands:** whether the Passwords app still recognises Luna's items as ordinary website passwords now they carry a security domain. If not, the discriminator can move; nothing else depends on that attribute.
- [x] **14.3 Fill flow** — on a recognised login form, offer matching credentials in a **native popover anchored to the field** (never an injected DOM overlay — a page must not be able to read or spoof it). Match on eTLD+1 with a public-suffix list, never on a bare substring.
  > **Built.** `CredentialPopover` — an `NSPanel` child window anchored to the field rect the page reports, so the page can neither read it nor spoof it. Matching is `PublicSuffix`, implementing the PSL algorithm including wildcards and exceptions.
  > **Fixed 2026-09-20:** hosts with no registrable domain — `localhost`, dotless intranet names, IP literals — returned nil and every password path bailed on the guard, so the whole feature was **silently dead on `http://localhost:8080/`**, which is the first place anyone building a login form tries it. They are now their own exact site key, matched whole and never widened.
  > **The picker carries what Safari's does**, because Safari's own panel is unreachable (`docs/PASSWORDS.md` §5b, measured): site favicon, account and site on two lines, a fingerprint saying what the click costs, and `All saved passwords…` — deliberately not Safari's "Other Passwords for this site", which Luna cannot fetch.
- [x] **14.4 Save / update flow** — after a successful submit, a non-modal "Save password for example.com?" chip with Save / Update / Never for this site. Persist "never" in `siteSettings` (§11.1).
  > **Built.** `SavePasswordChip`: non-modal, hover-pauses its own dismissal, Save / Update / Never for this site. "Never" persists as a `savePasswords` column in `siteSettings`, beside §3.2's two. "Not now" is not remembered — ignoring the chip once must not mean never being asked again.
- [x] **14.5 Password generation** — offer a strong generated password on signup forms, respecting the site's `passwordrules` attribute where present.
  > **Built.** `PasswordGenerator`: `SecRandomCopyBytes` with rejection sampling, and a parser for Apple's `passwordrules` grammar covering bracketed literals containing commas, `max-consecutive`, and unknown directives ignored rather than fatal. Candidates are redrawn rather than patched, so no position is predictable.
- [ ] **14.6 Verification codes** — if §14.1 shows we can read synchronizable TOTP secrets, offer one-tap fill for `one-time-code` fields. If not, at minimum autofill from the clipboard when the user copies a code out of the Passwords app, and don't pretend to more.
  > **Blocked by §14.1's answer.** Luna cannot read anything Apple's apps saved, so synchronizable TOTP secrets are out — not deferred, unreachable. The form detector does report `hasOneTimeCode`, so the field is recognised; the clipboard fallback this item allows as a minimum is **not** built.
- [ ] **14.7 Native-messaging bridge for password extensions** — implement the host side of native messaging in our `WKWebExtensionController` delegate so **1Password, Bitwarden and friends** work through §16. For many users this is the real answer, and it's also the mechanism the iCloud Passwords extension would need if Apple ever allowlists us — build the bridge now, gated behind an explicit per-extension permission.
  > **Blocked on §16, not on Apple.** The host side belongs in the `WKWebExtensionController` delegate, and Luna loads no extensions at all (D-32 puts them in v2). The bridge would have nothing to bridge to. This is the honest gap for users whose passwords live in 1Password or Bitwarden.
  > **Smaller than it sounds.** Checked against `MacOSX26.5.sdk`: this is two optional methods on `WKWebExtensionControllerDelegate` — `sendMessage:toApplicationWithIdentifier:replyHandler:` and `connectUsingMessagePort:` — roughly 300 lines of stdio framing and process lifetime once §16.1 exists. It is not a second project.
- [x] **14.8 Security rules (non-negotiable)** — never persist anything from a `type=password` field without an explicit user action; never fill cross-origin or into an iframe whose origin doesn't match the page; require a recent user gesture before filling; never expose credentials to page JavaScript; and treat a fill into a page reached via a redirect chain as suspicious. Autofill of addresses and payment cards stays **out of scope** — say so in settings rather than half-building it.
  > **All enforced**, with the rule-to-code table in `docs/PASSWORDS.md` §6. One asymmetry is deliberate and worth knowing: credential *matching* is eTLD+1, frame *trust* is a strict scheme/host/port origin — a same-site frame check would let `evil.example.com` inside `bank.example.com` take the password.
  > **One rule added beyond the list:** Touch ID in front of every fill (`PasswordAuthorization`, on by default). It runs **before** the Keychain read, so a cancelled prompt means the secret was never fetched; the origin and form are re-checked on the far side of the prompt, which can sit open for as long as the user likes.
- [x] **14.10 Passkeys need an Apple-gated entitlement — budget it into M4.** WebAuthn in a third-party WKWebView requires `com.apple.developer.web-browser.public-key-credential`, which is request-only. Until it is granted, `PublicKeyCredential` is present in the DOM but dead, so sites offer a passkey flow that silently fails — worse than not offering it. Nook's workaround is to inject a script suppressing `PublicKeyCredential` while waiting; do the same, and **request the entitlement early** because the turnaround is Apple's, not ours. Verify the exact entitlement name against current documentation before filing.
  > **Suppression built; the request itself is still to file.** Entitlement name verified against Apple's current documentation as `com.apple.developer.web-browser.public-key-credential`, and it is apply-only — it is how Chrome and Firefox reach Apple Passwords' passkeys. `PasskeySupport` reads it off the **running process** (`SecTaskCopyValueForEntitlement`), not a build flag, and injects the suppression script until it is present, so sites fall back to passwords rather than offering a button that hangs.
  > **What the request needs, read off Apple's form (2026-09-20):** the **Account Holder of an organisation** account — an individual membership does not qualify; the bundle ID registered in Certificates, Identifiers & Profiles; and **a link Apple can download the browser from**. That last one is the blocker: the repo is public but has no releases, so there is nothing to evaluate. Developer ID signing and notarisation need no grant, so the order is *sign → notarise → publish a release → then file*. Answer **Yes** to "supports WebAuthn" — WebKit does, and Luna hides it only until this is granted.
  > **Whose account: decided 2026-09-22 — the Organization one, see §24.4.** An individual membership cannot be granted this entitlement at all, which is what makes the account-type choice a passkeys decision rather than an admin one.
  > **Do not file `com.apple.developer.web-browser` alongside it.** An earlier draft of `docs/PASSWORDS.md` said to; that entitlement is **iOS and iPadOS only**. macOS default-browser registration needs no entitlement, only §22.2's `CFBundleURLTypes`.
- [ ] **14.9 File a Feedback / DTS request** asking for third-party browsers to be able to participate in Password AutoFill or the iCloud Passwords helper allowlist. Low odds, near-zero cost, and it dates our attempt if the policy ever changes.
  > Still to do, and cheap. Separate form from §14.10's — that one is `developer.apple.com/contact/request/macos-browsers-passkeys/` and covers passkeys only. §14.9 is Feedback, and the ask is Password AutoFill for third-party browsers, which `docs/PASSWORDS.md` §5b now has measurements to cite.

## 15. Downloads

- [x] **15.1 `WKDownloadDelegate`** — one real trap: **`WKDownload.delegate` is `weak`**, so it must be retained somewhere or downloads die silently with no error.
  > **Retracted (verified against `MacOSX26.5.sdk` by probe):** an earlier note here claimed `decideDestinationUsing` must answer `(url, true)`, the second value granting a sandbox extension. **That is stale and does not compile on macOS 26.5.** The SDK's `WKDownloadDelegate` has exactly one required method and it completes with a single `NSURL * _Nullable`. Use the `async -> URL?` form. Left in place as a warning: a plausible-sounding API detail repeated from memory survives review easily.
- [x] **15.1a (original wording)** — `decideDestinationUsing:suggestedFilename:` (uniquify into `~/Downloads` or user path), progress via `download.progress`, `didFailWithError:resumeData:` with **resume support**, `didFinish`.
- [x] **15.2 Route "should this be a download?"** through `decidePolicyFor navigationResponse` → `.download` when `!canShowMIMEType` or `Content-Disposition: attachment`; also handle `navigationAction` → `.download` for `download` attributes.
- [x] **15.3 Downloads UI**: sidebar popover + a persistent panel; reveal in Finder, retry, open, clear; quarantine flag set correctly (`com.apple.quarantine`) so Gatekeeper still protects the user.
- [x] **15.4** Warn on executable/dmg/pkg types; block silent auto-downloads from background frames.
- [ ] **15.5** PDF handling: WebKit displays PDFs inline — add a download/print affordance, don't hijack it.

---

## 16. Extensions (`WKWebExtension`) — **v2, except §14.7**

> **Decided 2026-09-17 (§32):** general extension support is **out of v1**. The only extension-adjacent thing we build now is the **native-messaging bridge in §14.7**, so 1Password and Bitwarden work. Everything below waits for M5/v2 — do not start §16.2–§16.6 without explicit go-ahead.
> **Confirmed 2026-09-21:** this section is the *only* route to Chrome extensions, and it is a good one. Embedding Chromium is not an alternative — CEF supports extensions only in Chrome-style windows showing Chrome's own toolbar, so a browser hosted in our own `NSView` (Alloy style) has `chrome://extensions` blocked and `LoadExtension` deleted at M128. `WKWebExtension` loads Chrome-format MV2/MV3 from a directory or ZIP, and a `.crx` is a ZIP with a 16-byte header — no Apple gatekeeping, it is our own controller. Benchmark for §16.5: Kagi's Orion spent six years on its own WebKit shim and publishes *"about 70%"* API coverage; Apple's implementation starts there and improves each OS release. See `docs/ENGINES.md` §5.

- [ ] **16.1 Host plumbing**: one `WKWebExtensionController` per **profile** (data store), `WKWebExtensionContext` per installed extension, wire the controller into every `WKWebViewConfiguration` of that profile.
- [ ] **16.2 Install from a folder / `.zip` on disk** (developer + power-user path). There is no third-party WebKit extension store; sourcing is the user's problem in v1.
- [ ] **16.3 Permissions UI** — surface requested host permissions, allow per-site grants, and an "extension is reading this page" indicator.
- [ ] **16.4 Toolbar/action surface** — extension action buttons need a home; put them in a compact row at the sidebar bottom or in the site menu, not a fake Chrome toolbar.
- [ ] **16.5 Compatibility reality check**: WebKit's implementation tracks the W3C WebExtensions standard and does **not** cover 100 % of Chrome's MV3 surface. Test against a fixed set: uBlock Origin Lite, Bitwarden, 1Password, Dark Reader, Vimium-class, a translate extension. Document what fails.
- [ ] **16.6** Per-Space extension enable/disable (big differentiator vs Safari).
  > **Resolved:** D9 is now macOS 26, so `WKWebExtension` availability stopped being a constraint. This section is still v2 — see the section header.

---

## 17. Content blocking & privacy

- [x] **17.1 Rule pipeline**: fetch EasyList/EasyPrivacy → convert to the WebKit content-blocker JSON schema → `WKContentRuleListStore.compileContentRuleList(forIdentifier:encodedContentRuleList:)` → cache the compiled list keyed by a content hash. **Lists download on first run and refresh on a schedule — they are never bundled in the app (D14).** Handle the offline first run without looking broken: blocking simply reports itself as not-yet-ready rather than silently doing nothing.
  > **Measured 2026-09-17** (macOS 26, Xcode 26.6, the real lists). EasyList 81,873 lines → **81,268 rules, 2.89 s** to compile; EasyPrivacy 1.94 s; Fanboy-Annoyance 2.01 s. First run end to end, all three (download + convert + compile): **14.8 s → 186,404 rules**. An unchanged refresh is **0.27 s with no recompile**, and looking all three compiled lists up at relaunch is **0.021 s**. So the shape above is right: compile off the hot path, look up at launch for free. A compile does not block the main thread outright but stalls it up to **353 ms at a time**, which is precisely why it must never run at launch.
  > **The cap is exactly 150,000 rules**, bisected — 150,001 fails with "Too many rules in JSON array." Each category fits one identifier today; the chunker splits and repeats every exception per chunk, because exceptions cannot reach across lists.
  > **Corrections to what this section used to claim.** A bad domain does **not** silently never match — WebKit hard-fails the entire list ("Domains must be lower case ASCII. Use punycode…"), and Foundation has no IDNA, so Luna carries its own RFC 3492 punycode. The genuine silent failures are different and worse: a bare `if-domain` matches that host **only**, while EasyList's `domain=` means host *and* subdomains — every entry needs a `*` prefix; and an unknown trigger key compiles and is then ignored. Further, for §26: `url-filter` is **not** regex — no alternation, no `{n,m}`, no `\d`, so the standard AdGuard `^` → `([^…]|$)` mapping fails; a trigger may not carry both `if-domain` and `unless-domain`; `resource-type` rejects ABP's `xmlhttprequest`/`object`/`subdocument` (use `fetch`, `other`, and `document` + `load-context: ["child-frame"]`); the useful compile diagnostic is `error.userInfo["NSHelpAnchor"]`, not `localizedDescription`; and `lookUpContentRuleList` **throws** code 7 for a missing identifier rather than returning nil.
- [x] **17.2 Default lists**: ads + trackers + annoyances (cookie banners), each toggleable; per-site "disable blocking here" that persists in `siteSettings`.
  > **Built 2026-09-20 — YouTube's in-player ads, and the one documented exception to D6.** The "Block ads" toggle was on and the pre-roll still played, which is §17.1's own failure mode: a switch that means nothing. Measured against the live site before anything was written: every media segment on a watch page arrives from a session-specific `rr2---sn-q4fzene7.googlevideo.com` host and is appended into **one** `MediaSource` behind a single `blob:` URL on a single `<video>` — the ad's bytes and the video's bytes are the same host and the same element, so no `url-filter` can separate them. And the ad *schedule* is not a request at all: `adPlacements`, `adSlots` and `playerAds` sit inside the same JSON object as `streamingData`. There is nothing to `block`. So `ContentBlockerYouTube.swift` takes the only seam left — a `documentStart` `WKUserScript` that deletes the schedule before the player reads it, plus a 23-rule `css-display-none` list for the static ads, which stays on the native path.
  > **`documentStart` is load-bearing, not a preference.** `JSON.parse` and `Response.prototype.text` replaced *after* YouTube's bundle has run are **never called** — measured at `parses: 0` and `rewrites: 0` against a response that demonstrably carried `adPlacements`. The bundle caches its own references on the way up. A late hook does not degrade; it does nothing.
  > **The SPA endpoint has moved.** It is `/youtubei/v1/get_watch` today, not `/youtubei/v1/player`, and the body is read through `Response.prototype.text` and parsed by YouTube itself — so every transport is hooked rather than the one that happens to be current.
  > **Result, A/B against three monetised videos in a real `WKWebView` built from `WebViewFactory.makeConfiguration()`:** `ad-showing` in **30/50, 31/50 and 7/50** samples without the script, **0/50 in all three** with it, and the content video playing from t=0 instead of t=9. `#player-ads` goes `block` → `none`; `#secondary` is untouched. 17 tests, and the script is *run* in a `JSContext` rather than string-matched.
- [x] **17.3 Cosmetic filtering** — element-hiding rules via `css-display-none` action type, injected as a rule list (not runtime JS) to avoid flicker.
- [ ] **17.4 Blocked-count badge** per tab + a per-site privacy sheet listing blocked domains.
  > **Measured caveat:** WebKit exposes **no public blocked-load callback** — `WKContentRuleList` carries only `identifier`, and the real notification is SPI (D10). Luna counts by a heuristic instead: a blocked sub-resource fires `error` and leaves **no** Resource Timing entry, while a 404 leaves one, and that difference is the count. Marked `ponytail:` in the code; a §26 row of its own.
- [ ] **17.5 ITP is already on** via WebKit — surface it, don't rebuild it. Add a "Clear all site data for this site" one-click action.
- [x] **17.6 HTTPS-only mode** with an interstitial for downgrades.
  > **Measured caveat:** `preferredHTTPSNavigationPolicy` cannot drive an interstitial. Both `.errorOnFailure` and `.userMediatedFallbackToHTTP` end an http-only navigation at `about:blank` via `didFinish`, with **no delegate error at all** — nothing to catch, nothing to show. Luna does its own upgrade-and-cancel in `decidePolicyFor` instead.
- [x] **17.7 Safe Browsing — DECIDED 2026-09-17: option (a), ship without it and say so plainly.** Safe Browsing v4/v5 is non-commercial-only and deprecated for new commercial use; Web Risk is paid per-lookup *and* puts a third party in the URL path, which contradicts D16. Remaining work is copy, not code: an honest paragraph in Settings → Privacy and in the Privacy Policy saying Luna does not check URLs against a malware or phishing list, and noting that macOS still applies XProtect and Gatekeeper to anything downloaded. Revisit only if a free, privacy-preserving list appears.
- [ ] **17.8 Permission prompts** (camera/mic/location/notifications) rendered as our own non-modal chip anchored to the sidebar, with per-site persistence in `siteSettings`.

---

## 18. Reading & page tools

- [ ] **18.1 Find in page** — `webView.find(_:configuration:completionHandler:)` with a custom UI, match count, prev/next, highlight-all. (Do **not** hand-roll JS find; the native API exists.)
- [ ] **18.2 Zoom** — `pageZoom`, `⌘+/-/0`, persisted **per eTLD+1**.
- [ ] **18.3 Reader mode** — inject a Readability-class extractor, render into our own `luna://reader` template with our typography tokens, font-size/width/theme controls.
- [ ] **18.4 PiP & media** — **there is no public per-tab audio API, and no public per-tab mute either.** `WKWebView` exposes only `setAllMediaPlaybackSuspended`, so §7.3's click-to-mute cannot be per-tab without either suspending all playback or injecting script. Decide which before promising it in the UI. `requestMediaPlaybackState()` reports a muted autoplay video as "playing", and `_isPlayingAudio` is SPI, banned by D10. Real audibility comes from a small capture-phase JS listener. Budget for that rather than expecting a property.
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

- [x] **19.1 Budgets — MEASURED 2026-09-17, all four PASS** (Mac mini M4, 16 GB, macOS 26.5.2, **debug** build; `Tools/perf`, full method in `docs/PERF.md`): cold launch to interactive **< 800 ms → 242 ms** median of 5, against a DB seeded with 40 tabs / 3 Spaces · new-tab command bar **< 100 ms → 27–55 ms first, ~8 ms median** · 40 tabs across 3 Spaces, 6 live, **< 3.5 GB → 785–842 MB footprint** · sidebar 120 fps (8.33 ms/frame) **→ 0.02–0.05 ms median, 0.2–0.97 ms p95**.
  > **Correction — the unit was wrong.** This section said **RSS**. RSS swung ±40 % between identical runs while `phys_footprint` held ±4 %, and RSS falls while the memory is still charged to us. **State the budget in `phys_footprint`.**
  > **These budgets are now too easy to be interesting.** 40 tabs / 6 live passes with ~4× headroom and always will. The budgets worth writing next are **6 *heavy* live tabs** (Figma, YouTube) and **200 tabs** — both unmeasured.
  > **A false failure nearly shipped.** Three runs reported "5 of 5 web views alive, no process exits, footprint never drops". Cause: **top-level code in a CLI has no autorelease pool that drains**, so the poll's own `controller.webView` read parked every view. A second, always-pooled instrument disagreed and caught it. Lesson and both instruments are in `docs/PERF.md`.
- [x] **19.2 Hibernation** — a cold tab has **no `WKWebView`** at all: capture `interactionState` + snapshot + title/favicon, tear the view down, release the process. Waking restores via `interactionState`.
  - Policy: keep the active tab + last N used (default 3) + anything playing audio/video + anything with unsaved form input (detect via `beforeunload`-style heuristic) alive; hibernate the rest after 5 min idle or immediately under memory pressure (`DispatchSource.makeMemoryPressureSource`).
  - Reference point: a hibernated tab in mainstream browsers still costs ~39 MB if you keep the renderer warm — our target is ~0 by dropping the webview entirely and paying a wake cost instead.
  > **"~0" now has a number (measured 2026-09-17).** Hibernating 5 of 6 live tabs ends **5 WebContent processes within 10 s** and returns **86 % of footprint** (808 → 111 MB); weak references confirm **0 of 5 web views survive**. §19.4 verified on the real app too: 40 restored tabs spawn **0 WebKit processes**, idle at 81 MB RSS / 31 MB footprint.
  > **The audio exemption is narrower than it reads.** "Playing audio" means any frame with `!paused && !muted && volume > 0`, from our own injected script — WebKit's `requestMediaPlaybackState()` calls a muted autoplay video "playing" and `_isPlayingAudio` is SPI (D10). So **a muted or silent video is not protected and will hibernate** (§18.4).
- [ ] **19.3 ⚠️ Written but never wired (found 2026-09-22): `checkProcessHealth()` and `resetProcessCrashBudget()` both have zero callers.** The recovery half works; the heartbeat that would catch the "suspended, never resumes, dead white window" case this item names is not connected to window activation or `NSWorkspace.didWakeNotification`. Original item: **19.3 Process pool strategy** — share one `WKProcessPool` per profile; WebKit gives each webview its own WebContent process until an internal cap, then shares. Do **not** create a pool per tab (memory explodes) and do not assume you can control the cap.
  > **Correction (measured):** the assumption that each profile gets its own auxiliary processes is **wrong**. Three data stores share **one** Networking process and **one** GPU process — only WebContent is per-view. Profile isolation is a storage boundary, not a process-count multiplier.
  > **Recovery policy (M1, measured):** cap rebuilds at **3 per 60 s with a growing delay**. Respawning instantly into a post-wake XPC state is a crash loop, not a recovery. Also call `closeAllMediaPresentations()` when hibernating, or a hibernated tab leaves an orphaned Picture-in-Picture window on screen.
  > **Gotcha (verified bug class):** on macOS, a backgrounded app's WebContent processes get suspended after ~16 minutes, and under memory pressure they can fail to resume, leaving a dead white window. Detect `webViewWebContentProcessDidTerminate(_:)` **and** a heartbeat check on window activation; auto-reload from `interactionState` and show a subtle "restored" toast rather than a blank page.
- [x] **19.4 Lazy everything** — never create a webview for a tab the user hasn't selected (restored sessions start fully hibernated).
- [ ] **19.5 Instruments pass** per milestone: Allocations, Leaks, Time Profiler, Animation Hitches. Record numbers in `docs/PERF.md` so regressions are visible.
- [ ] **19.7 A second instance kills the app.** Seen live 2026-09-18: launching Luna while another instance (or the XCTest host) holds `luna.sqlite` puts up a raw `SQLite error 5: database is locked — while executing ⁠`SELECT * FROM sqlite_master LIMIT 1`⁠` dialog and then a dead window with no chrome. Two things wrong: Luna is not single-instance, and a failed `BrowserStore` open is surfaced as a developer-facing SQL string via `NSApp.presentError`. Needs `LSMultipleInstancesProhibited` (or an explicit hand-off) plus a human error page.
- [x] **19.6 Energy** — verify we don't prevent App Nap or keep timers running when all windows are closed.

---

## 20. Keyboard & input

- [ ] **20.1 Ship this default map** (all remappable in settings):
  `⌘T` command bar/new tab · `⌘L` edit URL · `⌘S` toggle sidebar · `⌘W` archive tab · `⌘⇧T` reopen last archived · `⌘D` pin/unpin · `⌘⇧K` archive all Today tabs · `⌃1…⌃9` Spaces (**not** `⌘1…9` — see §5.10) · `⌥`+click → split · `⇧`+click → Peek · `⌘Y` archive view · `⌘Y` history · `⌘F` find · `⌘R`/`⌘⇧R` reload/hard reload · `⌘[`/`⌘]` back/forward · `⌘⌥←/→` prev/next tab · `⌘⇧←/→` resize split · `⌘⌥I` Web Inspector · `⌘,` settings · `⌘N`/`⌘⇧N` window/private window · `⌘⌥N` mini window.
  - **Do not collide with system or common web-app shortcuts** — audit against Gmail/Figma/Notion before finalising.
- [ ] **20.2 Full keyboard-only operation** — every action reachable without a mouse; visible focus ring on all chrome controls.
- [x] **20.3 Customisable shortcuts UI** with conflict detection.
- [ ] **20.4 Trackpad gestures** — two-finger back/forward (`allowsBackForwardNavigationGestures`), pinch zoom, three-finger swipe between Spaces.

---

## 21. Accessibility

- [ ] **21.1** Full VoiceOver labels/roles on sidebar, command bar, split panes, mini window; correct rotor navigation order.
- [ ] **21.2** Respect Reduce Motion, Increase Contrast, Reduce Transparency (fall back from `NSVisualEffectView` to solid `surface` tokens), Differentiate Without Colour (Spaces must be distinguishable by icon/label, not only gradient).
- [ ] **21.3** Dynamic UI font scaling; verify at largest accessibility sizes that nothing clips.
- [x] **21.4** Contrast audit: every token pair ≥ 4.5:1 for text, both themes, including over the gradient washes and the live theme-colour tint (clamp the tint if it fails).

---

## 22. System integration

- [x] **22.1 Default browser flow** — `LSSetDefaultHandlerForURLScheme("http"/"https", bundleID)`. macOS shows its own confirmation sheet; we cannot suppress or reliably read the outcome, so poll `LSCopyDefaultHandlerForURLScheme` afterwards.
  > **Gotcha:** this API is deprecated-with-no-replacement **and is blocked by the App Sandbox**. This is precisely why D8 rules out the Mac App Store. Do not sandbox the main app without re-deciding this.
- [ ] **22.2 `Info.plist`**: ~~`CFBundleURLTypes` for http/https~~, `CFBundleDocumentTypes` for `.html/.webloc/.pdf`, `NSUserActivityTypes` for Handoff, `LSApplicationCategoryType`.
  > **`CFBundleURLTypes` done 2026-09-20; the rest still open.** Its absence was not cosmetic: LaunchServices never listed Luna as a browser, so `NSWorkspace.urlsForApplications(toOpen:)` for an `https` URL returned Safari, Dia and Chrome and not Luna — §3.1's "Set as Default" button could not have worked, and discarded the resulting error in silence. Verified before and after. One missing key also blocked §12.2's links-from-other-apps and the first criterion of §14.10's entitlement request.
- [ ] **22.3 Handle `application(_:open:)`** → route to Mini Window or the Space chosen by the routing rules (§25.3).
- [ ] **22.4 Services, Share menu, Shortcuts (App Intents)** — "Open URL in Space X", "Save tab to…", "Archive all tabs".
- [x] **22.5 Menu bar** — a complete, correct macOS menu (File/Edit/View/History/Bookmarks/Window/Help) even though the UI is chromeless. Every command discoverable here.
  > **Gotcha (proved with a running probe in M0):** **`@main` on a nib-less `NSApplicationDelegate` does not work.** The inherited `main()` is just `exit(NSApplicationMain(...))`, and `NSApplicationMain` only installs a delegate when it loads a **main nib**. With no nib, `NSApp.delegate` stays nil, neither launch callback fires, and the app sits in a dead run loop with no window and no crash. Luna's `AppDelegate` therefore declares its own `static func main()`: `NSApplication.shared` → assign the delegate → `withExtendedLifetime(delegate) { app.run() }`. The `withExtendedLifetime` is load-bearing — `NSApplication.delegate` is a **weak** reference, so a local delegate deallocates immediately without it.
  > **Cosmetic, for when the real Edit menu is built:** AppKit auto-injects Writing Tools, AutoFill, Dictation and Emoji & Symbols into any menu titled "Edit" — and currently injects Dictation twice and Emoji & Symbols three times. Harmless, but don't add them by hand as well.
- [ ] **22.6 Multi-window & multi-display**, fullscreen, Stage Manager, Spaces (the macOS kind) sanity checks. Restore window frames per screen config.
- [ ] **22.7 Continuity** — Handoff of the active tab to/from iPhone/iPad Safari where possible.

---

## 23. Settings, import & onboarding

- [x] **23.1 Settings window — BUILT 2026-09-18.** AppKit, **not** SwiftUI and **not** tabbed: a separate `NSWindow` with a glass section list and an opaque detail pane, because only a native window can host `NSGlassEffectView`. All ten sections ship (General, Appearance, Privacy, Passwords, Search, Downloads, Shortcuts, Spaces, Extensions, Advanced); the unbuilt ones are dimmed with a one-line reason rather than hidden. Full contract in `docs/SETTINGS-SPEC.md`.
  > **The search field filters controls, not sections** — the thing Firefox and Chrome have and Safari does not, and the single biggest win in a nine-section window.
  > **Rows that ship dimmed, each a missing *reader* rather than a missing switch:** on-launch and confirm-on-close (nothing consults either key — `startSession` restores unconditionally and there is no `windowShouldClose`), ask-where-to-save and clear-download-list (`DownloadManager.items` is in-memory only, so the list already clears on quit and the other options are unimplementable), Develop menu (`MainMenu` has none), ~~rename/reorder a Space and the profile popup~~ *(both shipped — see §5.6)*, ~~delete-profile-data~~ *(obsolete: no Profile since v7; per-Space jar deletion is `discardJar(of:)`)*, sidebar position, shortcut rebinding, and search suggestions.
  > **The section list is the browser's sidebar (2026-09-21).** Same views, same tokens, same springs: §3.4's `RowPillView` glass pills moved between rows, `rowHeight`/`rowPillHeight`/`rowGap` for the pitch, `rowFaviconInset`/`rowTitleInset` for the two columns, and no tile behind a glyph. The flat wash, the 24 pt icon tiles and the 34 pt pitch are gone; §1's height floor is 480 because ten rows at the sidebar's pitch need it. `docs/SETTINGS-SPEC.md` §2.1.
  > **Known gap:** "Restore all settings to defaults" deliberately does **not** reset the three blocking toggles. `ContentBlocker` caches them in memory and must re-apply compiled rule lists to live web views, so wiping the key would desync the engine from the UI until relaunch. Needs a `ContentBlocker.resetToDefaults()`.
- [ ] **23.2 Import**:
  - **Safari**: `~/Library/Safari/Bookmarks.plist` (binary plist tree), History from `~/Library/Safari/History.db` (SQLite). **Both are protected by TCC — confirmed 2026-09-17 that this applies even though Luna is unsandboxed (D8):** a plain `ls ~/Library/Safari` returns `Operation not permitted`. So the exported-HTML path is the real one and Full Disk Access is the only alternative, not a shortcut we can skip.
  - **Chromium family**: `Bookmarks` (JSON) + `History` (SQLite). **The layouts genuinely differ** — Dia and Arc nest under `User Data/`; Chrome, Edge, Vivaldi and Opera do not; Brave is under `BraveSoftware/Brave-Browser`. **Enumerate profiles from `Local State → profile.info_cache`; never assume `Default`** — on Martin's Mac `last_used` is `Profile 1`. A profile with `History` and **no `Bookmarks` file at all** is normal, not an error. **Do not attempt to import passwords** (Keychain-encrypted; out of scope, and §14.1 owns that ground).
  - **Reading a live SQLite file**: copy it **and its `-wal` / `-shm` / `-journal` sidecars**, then open the copy. Measured: opening Dia's live `History` with `mode=ro` returns `database is locked (5)`; the copy returns every row. Dia uses a **rollback journal**, not WAL, so copy whichever sidecars exist rather than assuming. `immutable=1` is not a substitute.
  - **Dia — built first (§32), verified on the running install** (v1.48.0, `company.thebrowser.dia`): `~/Library/Application Support/Dia/User Data/{Default,Profile 1}/`, a stock Chromium profile root. Profiles are named "Work" and "Main". `date_added` in `Bookmarks` is microseconds-since-1601 **written as a JSON string**, which is what breaks a naive `Decodable` — hence `JSONSerialization`. Rows with `hidden=1` are excluded from both the read and the progress count.
  - **Arc — its sidebar is the whole of what it saves, and it is not in `Bookmarks`.** The line above used to read "there is no `StorableSidebar.json` on this Mac, so Arc is simply another Chromium source"; that was wrong, or stopped being true, and it cost the Arc import everything but its history. Re-measured 2026-09-22: `~/Library/Application Support/Arc/StorableSidebar.json` is **753 KB of plain JSON holding 118 saved tabs across four Arc Spaces**, and `User Data/Default` contains **no `Bookmarks` file at all** — so an Arc import reported `bookmarks + 0` and 21 visits and looked like it had worked. The file interleaves item ids with item objects in one array; a saved tab is an object carrying `data.tab.savedURL`, and folders, easels and split views are not. Dates are **seconds since 2001**, not Chromium's microseconds since 1601 — Arc is a Swift app writing `Date` through `Codable`. Read as Chromium's, every bookmark arrives dated in the year 25000. `SidebarImport.swift`.
  - **Dia's `Bookmarks` is empty and its favourites are elsewhere.** Verified 2026-09-22: `User Data/Default/Bookmarks` is a stock tree with three empty roots, so `bookmarks + 0` was *correct* there and still delivered nothing. The 8 real favourites are in `~/Library/Application Support/Dia/StorableProfileContainers.json`, one file for the whole app, with `id.profileID` holding the profile's **directory name** — which is what makes filtering possible, and required: importing `Work` must not hand over `Personal`'s favourites. The same file carries the open window (`container.window`); those are working state and stay out, the rule the HTML export already keeps for today's tabs. `StorableAutoArchive.json` holds 1,890 auto-archived tabs and is not read — that is closed-tab history, not bookmarks.
  - **Arc and Dia keep their shape; every other source is flattened.** Arc's sidebar is Spaces holding folders holding saved tabs, which is §3.4b's shape already, and Dia's favourites are a profile's one-click row, which is §3.3's grid scoped the way Luna scopes it. So an Arc Space becomes a Luna Space (named `Arc — School`, because `resolveTargetSpace` reuses a Space of the same name and Arc's `Personal` would otherwise land inside Luna's own seeded `Personal`); an Arc folder becomes a §3.4b folder; a pin that was loose in Arc's pinned tier goes in a folder named after the browser, because that tier holds folders and nothing else; and the profile's favourites row becomes tiles in **every** Space imported from that profile, which is what Arc itself shows. A Chromium `Bookmarks` tree and a Netscape export have neither Spaces nor a one-click row, so §3.4b's one-import-one-folder rule still governs them. `ProfileReader.keepsItsOwnStructure` is the switch; `BrowserImporter+Sidebar.swift` is the second writer. Naming a Space outright (§30.17's "into this Space") flattens a sidebar too — the caller has already said where everything goes.
  - **One level of folder, and the path is the name.** A Luna folder holds tabs, not other folders, so Arc's `IA ▸ Physics` becomes `IA / Physics`. Both names survive and two `Physics` folders under different parents cannot collide.
  - **History cannot be split between a source's Spaces.** A browser's `History` is one file per profile and says nothing about which of its Spaces a visit happened in, so an import puts every visit in the first Space it made — the one the source lists first. Putting the same 70,000 visits in each would be worse.
  - **Measured after the change (2026-09-22):** Arc → 97 bookmarks across two Spaces (`Arc — School` with `IA / Physics`, `IA / Business`, `IA / Chemistry`, `Extended Essay / Non-Newtonian Fluids` and an `Arc` folder of four loose pins, plus 8 tiles; `Arc — Personal` with `Bored`, `Pirate`, `Cool Websites`, four loose pins and the same 8 tiles). Dia → 8 tiles in `Dia — Personal`, and 0 for `Profile 2`, which has no favourites of its own.
  - The Atlas and Helium entries remain unverified guesses that degrade to "not installed".
  - Generic: Netscape bookmarks HTML **import and export** — the export also serves §23.4 and is the only place the folder tree survives today (see below).
  > **Idempotency, two mechanisms.** Bookmarks deduplicate against the **target Space by URL, read live from `BrowserStore`** rather than from the ledger, so a second run is a no-op even if the ledger is lost or the same site arrives from two browsers. **One key, the URL** — this used to say folder-path + URL as well, "so a site bookmarked in two folders stays two", and that key was ANDed with the URL one and could never fire. It is also the wrong answer here: with no folder column the two copies are two identical rows in one Space. History uses a **per-`<source>/<profile>` watermark** (max source timestamp) in `import-ledger.json`, which doubles as resume-after-cancel. **Dry run is the same code path with the writes skipped** — it creates no Space and no Profile.
  > **Open gap:** §11.1's `bookmarks` table does not exist, so bookmarks land as `Tab` rows (bar URLs → `.essential`, the rest → `.pinned`) and **the folder tree is dropped on write**; it survives only in the HTML export. The readers already carry `folderPath`, so a `bookmarks(tree)` migration closes this without touching them.
  > **Placement, fixed 2026-09-21.** Three things the tier decision got wrong, all of them silent: Favorites are capped at twelve per **Space** (per Profile when this was written; v7 deleted the Profile) and a bookmarks bar is routinely longer — over the cap the rows looked right until `v2`'s migration next ran and demoted whichever twelve it liked, so the cap is applied on the way in and the rest are pinned rather than dropped; `profileID` was never set, which makes an imported Favorite invisible to `favorites(onProfile:)` and leaves it for that same migration to backfill; and an import that **reused** a Space — the second run from one browser, or a first run whose name already matched — wrote into a Space the live session was already showing, where `adoptSpacesWrittenElsewhere` was only looking for new ones. History still lands in `places`/`visits` alone and shows up only as Command Bar suggestions.
- [ ] **23.3 Onboarding** — 4 screens max: pick theme, import, create first Spaces, set as default browser. Must be skippable and re-runnable.
- [ ] **23.5 Import is unreachable after first run** *(found 2026-09-22)*. `BrowserImporter` is constructed in exactly one place outside tests — `OnboardingWindowController.swift:37` — and onboarding cannot re-run (`OnboardingState.hasRun` is never cleared by anything). A user who skips first run, or installs Chrome afterwards, can never reach any of §23.2's eleven readers. Same for `exportBookmarksHTML` (§23.4): round-trip tested, called only by tests. **Cheapest fix in the tracker: one File ▸ Import menu item + one Settings row.**
- [ ] **23.4 Backup/export of our own data** (bookmarks, spaces, boosts, settings) to a single JSON — non-negotiable trust feature for a new browser.

---

## 24. Quality, release & operations

- [ ] **24.1 Testing**: unit tests on frecency, hibernation policy, URL parsing/canonicalisation, blocklist conversion, traffic-light layout. UI tests for launch → command bar → navigate → split → quit → restore. A manual **Top-100-sites compat matrix** re-run each milestone (this is how we catch WebKit-vs-Chrome breakage).
- [ ] **24.2 Crash reporting** — Sentry or a self-hosted alternative; **opt-in**, with scrubbed URLs (never send full URLs or page content).
- [x] **24.3 Telemetry — DECIDED 2026-09-17: there is none.** No analytics, opt-in or otherwise (D16). §24.2 crash reporting stays, opt-in and URL-scrubbed. Settings should say "Luna collects no usage data" and mean it literally. This is a marketing asset and a maintenance saving at the same time.
- [ ] **24.4 Signing & notarisation** — Developer ID Application cert, Hardened Runtime on, `notarytool submit --wait`, staple the ticket, ship a signed DMG. Entitlements: `com.apple.security.network.client`, camera/mic/location usage strings. Keep the entitlement set minimal.
  > **DECIDED 2026-09-22 — sign under the Organization account.** Both Martin and Ziad hold Apple Developer accounts; one is an **Organization**, and that is the one Luna ships under. The other person is added as a **member of that team**, not used as a second signing identity. This is not a preference — §14.10's passkey entitlement is only grantable to the **Account Holder of an organisation**, and an individual membership does not qualify, so signing under an individual cert would permanently kill passkeys in Luna.
  > **The Team ID is effectively permanent.** It is baked into the Gatekeeper identity users see, the Sparkle update chain (§24.5), and the CloudKit container (§31). Changing it later means existing users cannot auto-update and synced data does not migrate — they reinstall by hand and start a new container. Decide once, before the first public release.
  > **Order of operations** (from §14.10, read off Apple's form 2026-09-20): **sign → notarise → publish a downloadable release → then file the entitlement.** The filing needs a link Apple can download the browser from, and the repo has no releases yet, so the entitlement cannot be requested until §24.4 and §24.6's release half are done. This is why §24.4 gates §24.5, §24.6, §31 *and* §14.10.
  > **CI needs a key, not a person.** Notarisation from `.github/workflows/ci.yml` wants an App Store Connect API key in repo secrets rather than an individual's app-specific password, so the release job does not break when whoever signed it changes machines.
- [ ] **24.5 Sparkle 2 auto-update** — EdDSA-signed appcast over HTTPS, delta updates, "beta channel" toggle.
  > **Gotcha:** Xcode re-signs `Sparkle.framework` but historically not its embedded XPC services/helpers — if notarisation rejects you for "Hardened Runtime disabled in Autoupdate.app", that's the cause. Verify with `codesign -dv --entitlements -` on every nested binary in CI.
- [ ] **24.6 CI** — build + test + sign + notarise on tag; archive dSYMs.
- [ ] **24.7 Legal & docs** — Privacy Policy must state: history and bookmarks are local-only · sync goes to the user's own iCloud and never to us (§31.11) · what search suggestions send and to whom · what crash reports contain · that **no usage data is collected at all** (D16) · and that Luna does **not** check URLs against a malware/phishing list (§17.7). Plus Terms, third-party attributions, and a `SECURITY.md` with a disclosure address.
  - **Licence: GPL-3.0-or-later (D12).** Add `LICENSE` at publication, keep `THIRD_PARTY_NOTICES.md` current from the first borrowed line, and make the corresponding source of every released build available — including Sparkle-delivered updates, which are distribution. Sparkle (MIT) and GRDB (MIT) are GPL-compatible; check any new dependency before adding it. Blocklists are still never bundled (D14), so EasyList never enters the picture.
- [ ] **24.8 Website + changelog + a real support channel.**

---

- [ ] **24.9 `Tools/perf` no longer compiles** *(found 2026-09-22)*. `Tools/perf/Sources/LunaPerf/main.swift:74` constructs `Profile(name:)`; the `Profile` type was deleted from BrowserKit in schema v7. The harness is a separate SPM package and is **not** in `.github/workflows/ci.yml`, which is why nothing caught it. Either port it to per-Space jars or drop it — but §19.1/§19.5 cite it as the way to re-run the budgets, so a dead harness silently retires the performance ledger.

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
| **No notification when the default browser changes** | A "Luna is your default browser" line goes stale silently | Refresh on the completion handler *and* on `didBecomeActiveNotification` |
| `FileManager.isWritableFile(atPath:)` **is not a writability check** | Reads POSIX mode bits only; answers true for TCC-protected `~/Desktop` and `~/Documents`, then the write fails | Create and delete a dot-file — the only check that agrees with what the download does |
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
| `downloads-ui.png` | Download-complete popover anchored to the toolbar, with a particle sweep — both withdrawn, see §30.15 | §30.15–30.16 |
| `transfer-from-other-browsers.png` | Two-pane onboarding import picker | §30.17–30.18 |
| `iphone-mac-sync.png` | New Tab page, Favorites grid, cross-device tabs, iOS companion | §30.19–30.22 |
| `refresh-animation-ui.mov` | Reload/refresh motion | §30.23 |

> **Resolved:** sync is in, over **iCloud** — see §31. The iOS companion stays v2 (§25.5), but the sync layer is designed now so the phone can join later without a migration.

- [x] **30.1 Floating window treatment** — the whole window is detached and rounded (~18–22 px radius) with the desktop wallpaper visible around it, and the chrome is translucent and tinted by the wallpaper/theme rather than opaque grey. Implies: no standard titlebar, full-window custom shape, heavy `NSVisualEffectView` use, and a shadow that reads on both light and dark desktops.
- [x] **30.2 Circular glass control buttons** — sidebar-toggle, back, and reload are separate round translucent buttons in a row beside the traffic lights, not a toolbar. Sizes ~34–38 px, hairline border at ~10 % white, hover lifts the fill.
- [x] **30.3 Domain-only URL pill** — the address field shows just `apple.com`, not the full URL, as a wide rounded pill. Full URL appears on focus/edit (`⌘L`). Right side of the pill holds small inline action icons.
- [ ] **30.4 Inline action slots in the URL pill** — the reference docks two AI icons plus a sliders/settings glyph inside the address pill. **Decided 2026-09-17: no AI in v1 (§32).** Build the pill with those slots reserved and sized, filled only with the settings/site-menu glyph, so adding something later is a fill rather than a relayout. Do not ship an AI affordance that does nothing.
- [x] **30.5 "Essentials" tile grid** — pinned sites render as large rounded glass **tiles with icon only** (2-up in the screenshot, wrapping to a grid), visually distinct from the text tab rows below. This is our §7.1 Favorites row — build it as tiles, not a compact icon strip.
- [ ] **30.6 Folder rows + explicit "Add Tab" row** — an `Archive` folder row and a `+ Add Tab` row sit between the Essentials grid and the tab list, as first-class list rows with the same metrics as tabs.
- [x] **30.7 Active-tab treatment** — selected row is a filled translucent pill with a visible hairline border and slightly brighter text; it spans the sidebar width with ~8 px inset. Inactive rows have no background at all.
- [x] **30.8 Status dots inline in the row** — a small leading dot marks an updated/unread tab (seen on the Discord row). Audio state gets its own trailing indicator (§7.3).
- [x] **30.9 Bottom utility bar** — profile avatar (circular, bottom-left), workspace/Space **page dots** in a small pill (centre), and a circular archive/trash button (right). The dots double as the Space switcher — adopt this instead of, or alongside, the §5.3 strip.
- [ ] **30.10 Split divider as a grabbable handle** — the reference shows a discrete `◁|▷` handle floating on the divider between panes rather than an invisible hit area. Make the handle appear on hover and support double-click to equalise panes.
- [ ] **30.11 Content pane as a separate card** — the web content sits in its own rounded card inset from the window edge, with a gap between sidebar and content showing the window's tint through it. This is what makes the whole thing read as "floating"; it also means page fullscreen has to animate the card to fill the window.

### From `non-side-bar-tab-ui.png` — the sidebar-off layout

- [x] **30.12 Top-bar mode is a real second layout, not just a collapsed sidebar — CONFIRMED FOR v1 (D13)** — with the sidebar off, a single translucent bar spans the window: traffic lights → sidebar toggle → back → pinned Essentials as small tiles → **centred** URL pill → a right-hand action cluster. Tabs are not visible at all in this mode; switching happens via the Command Bar. Build it as its own layout controller, with a shared model, and animate the transition between modes.
- [ ] **30.13 Chrome tint follows the page in both layouts** — the reference shows the whole top bar washed pink/lavender on GitHub. Same mechanism as §8.3; make sure the tint pipeline isn't wired only to the sidebar.
- [x] **30.14 Right action cluster** — extension action icons, `+` (new tab), downloads, and profile/account sit in their own translucent capsule, divided from the pinned tiles by a hairline. This is the natural home for the §16.4 extension buttons — build the capsule once and let both layouts host it.

### From `downloads-ui.png`

- [x] **30.15 Download-complete popover** — ~~anchored to the downloads button with a visible pointer tail, floating *over* the window edge rather than inside the content area. Row = file-type icon (PDF glyph), middle-truncated filename, confirm/dismiss button. Feeds §15.3; the popover is the primary surface and the full panel is secondary.~~
  > **Built, then withdrawn 2026-09-21.** A body above the window's top edge with its tail pointing down only aims at §4's capsule; in the sidebar layout it appeared in the opposite corner of the screen from the button it described, and in the top bar it repeated the list underneath it. Downloads announce themselves on the button the file was thrown at, in both layouts — `UI-SPEC.md` §5 and §5.0.
- [x] **30.16 Completion animation** — ~~a particle/sparkle sweep across the filename when a download lands. Time it with the §8.5 budget (≤0.35 s) and kill it entirely under Reduce Motion.~~
  > **Built, then withdrawn 2026-09-21** with the popover whose filename it swept. The motion §5 has now is at the *other* end of the download: §5.0 throws the file's own icon at the Downloads button as it starts, which is the event that had nothing.

### From `transfer-from-other-browsers.png`

- [x] **30.17 Import screen layout** — two-pane modal: left is headline + one-line body + `Back`/`Continue` pill buttons (solid primary, muted secondary); right is a gradient wash holding selectable browser rows (app icon, name, trailing radio). The selected row lifts into a brighter card with a filled check. Multi-select.
  > **Built** as §30.17's first run, three pages in `Features/Onboarding/` — welcome, transfer, done — over the restored browser rather than in front of it. `UI-SPEC.md` §5.3 has the surface; the disk image the user opens before it is `Tools/make-dmg.sh`.
- [x] **30.18 Sources to detect and list** — Safari, Chrome, Arc, Dia, Atlas, Helium: i.e. both the Chromium family and the WebKit/Arc family. Detect which are actually installed and list those first; ~~grey the rest~~ leave the rest out.
  > **Built, with one thing changed.** Greying the rest put eight rows of "isn't installed on this Mac" around the two that are. The screen lists what is installed; an installed browser Luna cannot read yet keeps its place and its reason.
  > **Copy warning:** the reference promises "bookmarks, history, and **extensions**". We cannot import extensions — §16.2 has no store and §16.5 has no parity guarantee. Word our copy as "bookmarks and history" or we ship a promise we break in the first five minutes.

### From `iphone-mac-sync.png`

- [x] ~~**30.19 New Tab page**~~ — **cut.** It shipped as a centred "Search or type a URL" pill over a Favorites grid, and every route into it already opened §9.1's Command Bar: `⌘T`, §3.4's New Tab row, §4's `+`, and the pill itself, which handed off rather than taking a second line of input. What was left was a page whose only job was to be somewhere to stand while the bar was open. `luna://newtab` no longer routes, a tab with no address is `about:blank`, an empty Space opens no tab, and §3.3a's two wells are what the column says instead. Schema `v9` rewrites the tabs that were standing on it.
  > The gap that killed it: the "Add Favorite" slot had nowhere to go — it opened the Command Bar, which makes a **Today** tab — so the grid's one affordance of its own was already broken, and §3.3a now says the same thing in the sidebar where the tiles actually are.
- [ ] **30.20 Voice input** — mic affordance in the Command Bar. Needs `SFSpeechRecognizer` + a mic usage string; prefer on-device recognition and say so in the Privacy Policy (§24.7).
- [ ] **30.21 Cross-device tabs surface** — an "open on my other devices" button, backed by §31.6. It had a home on §30.19's page; it needs a new one.
- [ ] **30.22 iOS companion shape** — bottom-anchored URL bar (back · tab switcher · domain · reload · overflow) and an "Added to ★ Favorites" confirmation chip. Reinforces §25.5: keep `BrowserKit` free of AppKit types so the model layer ports as-is.

### From `refresh-animation-ui.mov`

- [~] **30.23 Reload motion — DEFERRED 2026-09-17 by Martin.** Transcribed and built; `Features/Reload/`
  exists, is tested, and is intentionally **not wired into the app**. The prismatic arc
  (white → amber → mint → lavender, sampled from the clip) is recorded in `docs/UI-SPEC.md` §7. Do not
  reconnect it without asking. Original note follows.
- [ ] **30.23a (original wording)** — watch the clip and transcribe the reload/refresh animation into the §8.5 motion table before building the reload control. Not yet transcribed; it's a video and this document only covers the stills.

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
> **The constraint is on the output, not the input.** What lands in Luna has to fit Luna: Swift 6 strict concurrency (D1), the AppKit/SwiftUI split (D2), the §8 token system, the §19 budgets, and our own Tab/Space model. Nook's ~3,000-line `BrowserManager` and ~4,000-line `Tab.swift` solve their architecture's problems; transplanting them imports a design §0.3 and §19 exist to prevent. Arriving at the same solution because it is the correct one is fine and expected — that is convergence, not copying.
>
> **Verbatim reuse is legal (D12) and occasionally right.** When it is — a gnarly well-tested algorithm, a non-obvious API call sequence — take it, add a header naming the source repo, file path, commit and licence, add an entry to `THIRD_PARTY_NOTICES.md`, and note it in the milestone report. No approval round-trip; this must never stall a milestone.

### What they answer well

Confirming an approach is possible at all (Ora's keychain autofill, for §14.1) · naming the API that solves something WebKit documents badly · the edge case you would otherwise hit in week three · on-disk paths and data formats (Dia's layout, for §23.2) · and, for Zen, how an interaction should feel.

### Immediate leads (evidence, not answers — verify each yourself)

- **§14.1 password spike** — Ora ships iCloud Keychain autofill and Nook ships native messaging with Bitwarden biometric unlock. That is strong evidence both §14.2 and §14.7 are achievable from a Developer ID app. It is *not* proof of what Apple permits us specifically; still build the throwaway signed build and write `docs/PASSWORDS.md`.
- **§23.2 Dia importer** — done that way: the paths in §23.2 were read off the running install, not off Nook's source. Ora's own importer supplied the concepts (copy-with-sidecars, the 1601 epoch and its guards, `JSONSerialization` over `Decodable`, loose bookmarks-bar URLs are Favorites, keyset paging); its `ImportAccessService` was dropped whole, since entitlements and security-scoped bookmarks are dead weight for an unsandboxed app (D8).
- **§17.1 blocking pipeline** — both Swift browsers already do fetch → convert → compile → cache against the rule cap, which confirms the approach scales at our size. Ours is written from the WebKit documentation and the measurements in §17.1.
- **§30 interaction detail** — Zen's spaces, Glance and compact-mode behaviour are the closest shipping analogue to §13 and §7.2. Watch them run; read §30 for what we actually build.
