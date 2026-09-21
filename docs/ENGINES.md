# Other browser engines (§0.2) — the research behind the "no"

**Status: closed, with evidence. Nothing here proposes work.** §0.2 already
listed "Chromium/Blink fallback rendering" and "bundling or patching a custom
WebKit build" as non-goals. This file is why, so the question can be reopened
on facts rather than re-argued from scratch.

Researched 2026-09-21 against `4a3d4a0`. Four parallel investigations: this
codebase's WebKit coupling, engine embedding on macOS, the hybrid per-tab
design, and prior art.

---

## The two questions asked

1. **Separate builds** — a Luna-on-Chromium, a Luna-on-WebKit, a Luna-on-Gecko.
2. **Per-tab engines** — Luna stays WebKit, but one tab renders in Chromium,
   for a site that needs it or an extension that only runs there.

## The answer

Question 1 is two-thirds impossible and one-third a different company.
Question 2 defeats its own motivation twice over. Both stated motivations are
better served by things already in `TODO.md`: **§4.6** (per-site UA override)
and **§16** (`WKWebExtension`).

---

## 1. What is actually embeddable on macOS in 2026

| Engine | Embeddable? | Verdict |
|---|---|---|
| **WebKit (`WKWebView`)** | Yes — what we ship | 0 bytes, Apple patches it, FairPlay/HEVC/H.264/AAC free |
| **Chromium (CEF)** | Yes, and only via CEF | +322 MB, 5 helper bundles, no App Store, no DRM. See §2 |
| **Gecko** | **No** | Embedding killed 2011; XULRunner dead 2015; GeckoView is Android-only |
| **Servo** | Technically yes | Cleanest API of the lot, but 66.4% WPT test score, no DRM, no H.264/AAC |
| **Ladybird** | No public embedding API | Pre-alpha; alpha not shipped; contributions closed June 2026. Revisit 2028 |
| **Own WebKit build** | Legally yes, practically no | Apple DTS says contact Legal; `WKWebView` actively resists it |

`//content` directly is not an option — Chromium's own README states it is not
a stable API. WebView2 does not exist on macOS and Microsoft has confirmed it
never will.

**Gecko is closed, not hard.** Benjamin Smedberg announced the end of Gecko
embedding on 2011-03-31, citing the coming multi-process move and the desire to
prioritise Firefox. Nothing replaced it. The only routes are a forked Firefox
(which means throwing away Luna's entire Swift/AppKit layer and becoming
Waterfox) or a puppeted Firefox window driven over Juggler/Marionette — and
macOS has no public API to host another process's window inside your view
hierarchy, so that is a detached window, not a tab.

---

## 2. The four things that end the Chromium conversation

Not the engineering. The engineering is merely expensive — CEF 152 has good
macOS arm64 prebuilt binaries and thousands of apps ship it. These four are
structural:

1. **No Mac App Store, permanently.** Guideline 2.5.6 requires WebKit for apps
   that browse the web, with no macOS carve-out. The EU alternative-engine
   entitlement is iOS/iPadOS-only and EU-only. Separately, a JCEF app was
   rejected under 2.5.1 in Jan 2021 for Chromium's private-API use
   (`CAContext`, `CALayerHost`, `_dyld_dynamic_interpose`). *Note: §22.1
   already rules out MAS for v1 because App Sandbox blocks default-browser
   registration — so this one costs us nothing today, but it makes the
   exclusion permanent rather than a v1 choice.*
2. **No Netflix, Disney+, Prime Video, or Spotify web.** Widevine requires a
   signed agreement with Google, and indie browsers have documented being
   stonewalled for months and then denied without explanation. CEF's own
   Widevine path is reported broken (cef#3820, CEF 127–130) and the issue was
   **closed as not planned**. `WKWebView` plays all of these today via FairPlay.
3. **Codec licensing becomes ours.** Chromium builds ship with proprietary
   codecs off; turning them on makes the patent licence our problem — H.264 is
   free for the first 100k units then $0.20/unit, AAC is $0.98/unit plus a
   $15,000 setup fee. The escape is hardware decode via VideoToolbox and never
   shipping FFmpeg's patented software decoders, which CEF's maintainers state
   carries no added licensing cost. That needs a lawyer, not a GitHub issue.
4. **The CVE treadmill is permanent and it is ours.** Chromium moved to a
   two-week release cycle on 2026-09-08. CEF tracks it well — stable was 3 days
   behind Chrome Extended Stable when measured. The lag that kills you is your
   own: **VS Code, with a full release-engineering org, ships Chromium 148 while
   Chrome stable is 153 — five milestones, ~4.5 months behind.** Whoever ships
   the engine owns its zero-days.

Size, for the record: `Chromium Embedded Framework.framework` is **322 MB** on
arm64 Release (224 MB dylib + 82 MB locales + 16 MB ANGLE/SwiftShader), roughly
550 MB universal. A dual-engine Luna is ~350–380 MB arm64. Today Luna ships
**zero** engine bytes.

---

## 3. Why per-tab engines defeat their own purpose

### The extension motivation is self-cancelling

CEF only supports extensions in **Chrome-style windows that show part of
Chrome's own toolbar**. Embedding a browser into our own `NSView` forces
**Alloy style**, where `chrome://extensions` is blocked — and the request to
unblock it was closed *not planned*. Programmatic `LoadExtension` belonged to
the Alloy bootstrap, deprecated at M125 and **deleted at M128**. The only
remaining load paths are the `--load-extension` command line and
`chrome://extensions`, and extension popups open as detached browsers that lose
tab context.

So the 322 MB buys a Chromium tab **without** the extension that was the reason
for wanting it.

### The session cannot follow the tab

Two engines are two cookie jars. Cookies can be hand-synced
(`WKHTTPCookieStore` ↔ CDP `Network.setCookie`) but:

- **Modern sessions aren't cookies.** Refresh tokens live in `localStorage` or
  IndexedDB, which have no sync path at all — not even a bad one.
- **Partitioning means "the same cookie" isn't.** CHIPS and WebKit's storage
  partitioning key state differently; a copied cookie can land in the wrong
  partition and simply not be sent.
- **ITP** caps script-written cookies at 7 days, so a synced cookie silently
  expires early on our side.
- **Device-bound sessions** (Chrome's DBSC) bind sessions to a TPM/Secure
  Enclave key. A copied cookie is worthless *by design*, and this trend grows.

Every prior implementation landed in the same place. Edge IE mode requires
hand-authored per-cookie XML (`<shared-cookie domain= name= source-engine=>`,
exact domain, no subdomain matching), cannot share persistent cookies at all,
and its official SSO debugging procedure is *capture an `edge://net-export`
netlog and read it in the netlog viewer*. Chinese dual-core browsers share
cookies but **not** localStorage or sessionStorage — switching kernel is
switching browsers.

### The irony that settles it

The sites that genuinely need Chromium's *engine* — WebUSB firmware flashers,
WebSerial config tools, WebHID remappers — are mostly **login-free**, so losing
the session costs nothing and a plain "Open in Chrome" serves them perfectly.
Logged-in Chrome-only web apps are exactly the case a hybrid **cannot** serve.
The need and the capability are disjoint.

### What it would cost us specifically

From the coupling audit: 16 files outside `BrowserKit` name `WK*` types, plus
~25 call sites reaching `controller.webView` without naming it. Worst leaks:
`WKDownload` travels four layers (`TabController+Delegates` →
`TabControllerDelegate` → `BrowserSession.onDownload` → `AppDelegate`);
`SiteMenu.swift:131` holds a `WKWebView` and reaches into its data store;
`BrowserSession+Lifecycle.swift:298` injects its own scripts behind
`TabController`'s back; `ReloadBloomView.swift:263` downcasts `NSView` to
`WKWebView`.

Already engine-agnostic and worth protecting: `TabState`, `NavigationPolicy`,
`HibernationPolicy`/`AutoArchive`, `TabList`, and the view seam
(`BrowserSession.webView(for:) -> NSView?` → `ContentCardView.setContent(NSView?)`).

Two things in the tree have **no CEF equivalent at all**:

- **`Tab.interactionState`** — the opaque WebKit blob carrying the back/forward
  list, scroll positions and form state, persisted to SQLite
  (`Models.swift:62`, `Schema.swift:188`). §19.2's entire invisible
  hibernate/restore strategy rests on it. CEF's `GetNavigationEntries` is
  read-only with no restore API.
- **`WKContentRuleList`** — §17's whole pipeline, including
  `FilterListConverter.swift`, becomes dead code. A Chromium tab would need a
  separate blocking engine, and §17.4's blocked count would differ per engine
  for the same page.

Estimates, honestly wide: ~2 days to clean up the leaks (worth doing on its own
merits); 8–12 days to extract a `WebEngine` protocol (**don't** — it is an
interface with one implementation unless a second engine is actually funded);
60–120 engineer-days for a Chromium variant at feature parity; 16–24 weeks plus
~1 week/month forever for per-tab, and extensions still don't work.

---

## 4. Prior art: nobody does this, and the ones who did are dead

| Product | Engines | Status 2026 |
|---|---|---|
| **Lunascape** | Trident + Gecko + WebKit, per-tab | **Dead** (last release 2018) |
| **Avant Browser** | Trident + Gecko + WebKit | Abandoned 2020 |
| **Maxthon** | Trident + Blink, per-site | Gone — MX7 is Chromium-only |
| **Edge IE mode** | Blink + real `iexplore.exe` | **Alive**, enterprise only, ≥2029 |
| **360 / QQ / Sogou** | Chromium + system Trident | **Alive**, ActiveX banking |
| **Orion (Kagi)** | WebKit only | Alive — *not* multi-engine |

Four lessons, each paid for by someone else:

1. **The secondary engine goes stale, and stale is your security floor.**
   Lunascape's Gecko froze at ESR 24 in 2014 and never moved. In **August 2025,
   attackers used Edge's IE mode as an attack path** via an unpatched Chakra
   zero-day — lure the user, prompt "reload in IE mode", get RCE. Microsoft
   removed the consumer entry points two months later and wrote that IE "was not
   designed with the robust architecture and defence-in-depth mitigations that
   we have come to expect from modern Chromium-based browsers."
2. **Upstream removes the API out from under you.** Mozilla killed Gecko
   embedding in 2011 for precisely the reason a multi-engine browser needs it.
   That single decision ended tri-core browsers on Windows.
3. **It was never a good compatibility tool anyway.** Lunascape's WebKit was
   WebCore+JavaScriptCore, so it never reproduced Chrome (Blink+V8) — and its
   own hosting layer added bugs no real browser had.
4. **The surviving niches are not ours.** Per-tab switching lives where a
   specific, enumerable set of sites is business-critical, permanently broken on
   modern engines, and someone else's problem to fix: enterprise IE ledgers and
   Chinese ActiveX banking. macOS in 2026 has neither.

**There is no 2024–2026 project doing per-tab engine choice.** Searched HN,
Reddit and the web. Even at Lunascape's peak, HN stories drew 1–7 points.

Two worth stealing *if we ever reopen this*: Edge's **auto-exit rule** (in-page
navigation stays in the alternate engine; address bar, back button or a bookmark
returns to the default — the only model in this space that doesn't strand
users), and its **30-day expiry** on the local site list, which stops a
compatibility list calcifying into permanent debt.

---

## 5. What this confirms, and what it doesn't change

The research produced **no new work items.** Both motivations were already
planned for:

- **"A site needs Chrome"** → **§4.6**, per-site UA override. Already specified,
  already carries the verified `applicationNameForUserAgent` gotcha. Most
  "please use Chrome" walls are string-matching on the UA, not real engine
  gaps. §26 already names this as the mitigation for inheriting Safari's
  web-compat profile.
- **"An extension only works in Chrome"** → **§16**, `WKWebExtension`. Apple's
  API (macOS 15.4+; D9 put us on macOS 26, so availability is not a constraint)
  runs Chrome-format MV2/MV3 extensions in a `WKWebView` app, loading from a
  directory or ZIP — and a `.crx` is a ZIP with a 16-byte header. No Apple
  gatekeeping; it is our own controller. §16.5's compatibility reality check
  stands: the known-fails are blocking `webRequest` (classic uBlock Origin —
  but §17 already gives us that capability natively), `chrome.identity` OAuth,
  native messaging (which is what §14.7 exists to bridge), and anything needing
  WebUSB/WebHID/WebSerial.

For the genuine engine gaps that UA spoofing cannot fix, the honest answer is a
one-key **"Open in Chrome"** handoff — `NSWorkspace.open(urls:withApplicationAt:)`
to whatever Chromium-family browser the user already has. It is not integration
and never will be, but for a WebSerial flasher it beats 322 MB of fake Chrome
that still can't load the extension. Not currently a TODO item; it is a few
hours if we want it.

**Benchmark for §16's ceiling:** Kagi's Orion built its own WebExtensions shim
over WebKit — six years to 1.0 — and publishes the number: *"about 70%"* of
APIs, with the note that one missing API is enough to break an extension. Using
Apple's implementation starts us where Orion spent six years arriving, and it
improves with every OS release.

---

## 6. What would justify reopening this

Not "a site broke". Specifically:

- A **login-bearing** site that is business-critical, that UA override does not
  fix, and that recurs — and even then the right move is a better Chrome
  handoff (named profile, return focus on close), not an embedded engine.
- Apple abandoning `WKWebExtension`, or §16.5's compatibility testing coming
  back materially worse than Orion's 70%.
- Ladybird shipping a stable third-party embedding API — they have not stated
  this as a goal, and stable is targeted 2028.

None of these are on any horizon we can see.

---

## 7. Not verified

Carried forward honestly from the research rather than dropped:

- Whether Orion on macOS ships a patched WebKit or uses the system one. Its
  cache path (`~/Library/WebKit/com.kagi.kagimacOS`) says system; Kagi's FAQ
  says "forking WebKit". No definitive statement found.
- Whether Widevine works at all in CEF 152. Last data point is cef#3820
  reporting it broken in 127–130, closed as not planned.
- Whether Apple's 2.5.1 private-API rejection of CEF still stands — the
  documented rejection is from January 2021.
- HEVC licensing terms (two competing pools, not researched).
- Cold-start RAM for any of these. Not benchmarked; third-party blog figures put
  Chromium at roughly 2× WKWebView, but naive measurement over-counts Chromium's
  shared read-only pages. Measure before quoting.
- The exact 2026 Chrome zero-day count (six per secondary sources, not checked
  against Google's release blog).
- Maxthon 6's dual-core claim (vendor copy only; their blog is AI-generated).

---

## 8. Sources

**Apple:** [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) (2.5.6, 2.5.1) ·
[alternative browser engines](https://developer.apple.com/support/alternative-browser-engines/) (iOS/EU only) ·
[WKWebExtension](https://developer.apple.com/documentation/webkit/wkwebextension) ·
[Safari extension compatibility](https://developer.apple.com/documentation/safariservices/assessing-your-safari-web-extension-s-browser-compatibility) ·
[forums 700648](https://developer.apple.com/forums/thread/700648) (self-built WebKit) ·
[forums 680330](https://developer.apple.com/forums/thread/680330) (cross-process NSView) ·
[WebKit Features in Safari 18.4](https://webkit.org/blog/16574/webkit-features-in-safari-18-4/)

**CEF:** [cef#3859](https://github.com/chromiumembedded/cef/issues/3859) (chrome://extensions blocked in Alloy, not planned) ·
[cef#3685](https://github.com/chromiumembedded/cef/issues/3685) (Alloy bootstrap deleted M128) ·
[cef#3820](https://github.com/chromiumembedded/cef/issues/3820) (Widevine broken) ·
[cef#3559](https://github.com/chromiumembedded/cef/issues/3559) (codec licensing) ·
[cef#4114](https://github.com/chromiumembedded/cef/issues/4114) (two-week cadence response) ·
[branches_and_building](https://chromiumembedded.github.io/cef/branches_and_building.html) ·
[MAS rejection](https://magpcss.org/ceforum/viewtopic.php?start=10&t=16215)

**Chromium:** [two-week release cycle](https://developer.chrome.com/blog/chrome-two-week-release) ·
[content/README.md](https://chromium.googlesource.com/chromium/src/+/main/content/README.md) (not a stable API)

**Gecko:** [LWN 2011, embedding removed](https://lwn.net/Articles/436412/) ·
[mozilla/geckoview](https://github.com/mozilla/geckoview) (Android-only) ·
[mozilla/platform-tilt#1](https://github.com/mozilla/platform-tilt/issues/1) (2.5.6 blocks Firefox from macOS MAS)

**Prior art:** [Edge IE mode](https://learn.microsoft.com/en-us/deployedge/edge-ie-mode) ·
[shared-cookie guidance](https://learn.microsoft.com/en-us/deployedge/edge-ie-mode-add-guidance-cookieshare) ·
[IE mode restricted after zero-days, Oct 2025](https://microsoftedge.github.io/edgevr/posts/Changes-to-Internet-Explorer-Mode-in-Microsoft-Edge/) ·
[Lunascape](https://en.wikipedia.org/wiki/Lunascape) ·
[360 dual-core help](https://browser.360.cn/se/help/feature-detail_hxgn_shll.html) ·
[Kagi Orion, ~70% WebExtensions](https://help.kagi.com/orion/browser-extensions/macos-extensions.html)

**DRM/codecs:** [Widevine blocked my browser](https://blog.samuelmaddock.com/posts/google-widevine-blocked-my-browser/) ·
[The End of Indie Web Browsers](https://blog.samuelmaddock.com/posts/the-end-of-indie-web-browsers/) ·
[Via LA AVC](https://www.via-la.com/licensing-programs/avc-h-264/) ·
[Via LA AAC](https://www.via-la.com/licensing-programs/aac/)

**Servo / Ladybird:** [servo.org](https://servo.org/) ·
[WPT scores](https://wpt.servo.org/scores.json) ·
[ladybird.org](https://ladybird.org/) ·
[Aug 2026 newsletter](https://ladybird.org/newsletter/2026-08-31)
