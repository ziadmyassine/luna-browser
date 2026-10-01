# Decisions

Why Luna is built the way it is. Settled questions live here so they are not
re-argued; reopen one with new evidence, not preference. The work itself is on
the [project board](https://github.com/users/ziadmyassine/projects/2) as issues, each
titled with its old plan number (`§6.4`, `§31.2`), which is what the `§` numbers
in comments and docs point at.

## §1 Architecture decisions

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
| | | **Exception, 2026-09-28, decided by Martin: the Web Inspector.** WebKit has no public way to open its inspector inside the app; `isInspectable` only lets Safari's Develop menu attach, and adds nothing to the right-click menu (measured). `BrowserKit/Engine/WebInspector.swift` sends `developerExtrasEnabled` (Inspect Element) and `_inspector` show / showConsole / showResources / toggleElementSelection / close, each checked with `responds(to:)` first, so a WebKit without them loses the commands, not the app. Only while Settings ▸ Advanced ▸ Web Inspector is on. Nothing else is covered by this exception. | |
| | | **Exception, 2026-09-28, decided by Martin: Picture in Picture.** Native PiP is off in every `WKWebView` but Safari's: a video reports `webkitSupportsPresentationMode('picture-in-picture')` false and `requestPictureInPicture()` throws NotSupportedError, so §3.2's automatic PiP had never floated anything. The public `allowsPictureInPictureMediaPlayback` is iOS-only (set on the configuration it raises). `WebViewFactory.makeConfiguration` sets the private `WKPreferences` key of the same name, checked with `responds(to:)` first. Measured with it on: the system PiP window opens from app-run script with no click, also from a page already out of the window (the tab switch). Only this one preference. The clipboard needed none: see "Clipboard reads ask, like the camera" below (§18.8). | |
| D11 | **Sync over iCloud (CloudKit private database, `CKSyncEngine`)** | No servers, no accounts, no support burden, data stays in the user's own iCloud; matches the Apple-native positioning | Custom sync backend (cost + privacy surface + an account system we said we wouldn't build) |
| D12 | **Open source under GPL-3.0-or-later**, licence file added at publication *(revised 2026-09-17, was: closed source)* | Matches Nook and Ora exactly, which makes reuse of their work legal instead of forbidden (§33), and makes "audit us yourself" the strongest form of the zero-telemetry claim (D16). GPL also forces anyone who forks Luna to stay open. Note that copyright does not stop a fork using the **name** — trademark does, and that is a separate, later decision. | MIT/Apache-2.0 (no reuse of GPL prior art); proprietary (rejected) |
| D13 | **Both layouts ship in v1** — sidebar layout *and* top-bar layout (§30.12) | It is a core part of Martin's reference, not a stretch goal | Sidebar-only v1 |
| D14 | **Blocklists are fetched at runtime, never bundled** | The licence reason disappeared when D12 became GPL — EasyList would now be compatible. The **operational** reason stands and is the better one: blocking improves without shipping an app update, and the binary stays small | Bundling EasyList |
| D15 | **Free. No monetisation.** | No licence keys, no payment processor, no VAT handling, no dunning, no entitlement checks in Sparkle | Paid one-off / subscription |
| D16 | **Zero telemetry.** Opt-in crash reports only, URLs scrubbed | A privacy-positioned browser that phones home has no story to tell. Deletes a Privacy Policy section and an SDK | Opt-in analytics |

> **Gotcha — D9 changed on 2026-09-17 (§32).** It was 15.4; it is now **macOS 26**, and Liquid Glass is the reason. **Verify the exact API surface and availability against the shipping SDK before designing around it** (§0.3) — a guessed API name spreading through the Design layer is exactly the failure §0.3 exists to prevent. If it does not behave as §30 needs, the fallback is hand-built `NSVisualEffectView` stacks, *not* a lower deployment target.

## §27 Questions answered by the owner (2026-09-17)

Every question here was answered on 2026-09-17. The answers and their consequences live in **§32**, and the decisions themselves are folded into §1's table and the relevant sections. This section is kept as a record of what was once uncertain, not as a live list.

| # | Question | Answer |
|---|---|---|
| 1 | The "other browser" you like — name it | **It is a concept, not a shipping browser.** There is no live app to check behaviour against, so §30's written transcription is authoritative and we own every interaction it doesn't specify. |
| 2 | Minimum macOS | **macOS 26+** (D9) |
| 3 | Name, bundle ID, icon direction | **Luna**, `dev.novapps.luna`, new namespace. Icon direction still open (§8.9, M6). |
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

## §32 Decision log

Sixteen questions, answered in one sitting. **Where this log contradicts an older section, this log wins**, and the section gets corrected when someone next touches it.

#### Product shape

| Decision | Consequence |
|---|---|
| **Name is Luna**, bundle `dev.novapps.luna`, internal scheme `luna://` | "ARCWK" is dead everywhere — doc, code, scheme, repo. |
| **Free forever, no monetisation** (D15) | No licensing code, no store integration, no VAT or refund policy, no entitlement checks in Sparkle. |
| **Zero telemetry**, opt-in scrubbed crash reports only (D16) | §24.3 becomes a paragraph of copy instead of a feature. One less SDK, one less Privacy Policy section, one fewer thing to defend. |
| **Open source, GPL-3.0-or-later** (D12) *(revised same day — this row supersedes the original "closed source" answer)* | `LICENSE` lands at publication. Unlocks legal reuse of Nook and Ora (§33) and obliges us to publish source for every released build. |
| **No AI in v1** | §30.4 reserves the layout slot and ships nothing behind it. §25.6 stays in the backlog with its privacy story unwritten. |
| **No Safe Browsing** (§17.7) | Must be stated honestly in Settings and in the Privacy Policy rather than quietly omitted. |

#### Platform & scope

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

## Section notes

The introductions that stood at the head of these plan sections.

### §★ — Top priority

These four come before everything else, in this order. Two of them reverse earlier decisions (§32a).
### §5 — 5. Spaces (storage isolation)

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
>
> **Per-Space site answers (#25, 2026-10-01, decided by Martin).** The camera,
> the microphone, the location, the local network and pop-ups are answered per
> Space: a yes to a call site in Work is not a yes in Personal. They live in
> `spaceSitePermissions`, keyed on `(spaceID, host)` and deleted with the Space.
> Zoom, the user agent, the blocking exemption, the HTTPS exception, the password
> offer and automatic Picture in Picture are about how Luna behaves rather than
> what a site may do, and stay one answer per site in `siteSettings`. `v14` copied every
> answer already given into every Space, so the upgrade changed nothing anyone
> had said. A private window keeps its own answers in memory and reads the shared
> ones, but no Space's: it is no Space's jar.
>
> **The per-Space answers do not sync.** Pop-ups and the local network did, as
> fields of `SiteSetting`. Carrying them per Space needs a new CloudKit record
> type, which is a Production schema deploy that can never be taken back, and it
> would sit in the Sites zone pointing at a Space in the Spaces zone, so a Mac
> that syncs one and not the other would park it forever. The camera, the
> microphone and the location never synced. `SiteSetting` keeps declaring the two
> retired fields; an older Luna still writes them and this one leaves them alone.
> If they should follow the user after all, the shape is a `SpaceSiteSetting`
> record in the Spaces zone.
>
> **Clipboard reads ask, like the camera (#118, 2026-10-01, decided by Martin).**
> A page reading the clipboard (`navigator.clipboard.readText()` and `read()`,
> `document.execCommand('paste')`) is asked about with the camera's toast, "Read
> the clipboard?", Allow and Don't Allow, and the answer is kept per site per
> Space (`SitePermission.clipboard`, `v16`). It shows as a switch in the site
> pop-out once given. Writing on a click is not asked about, and neither is the
> user's own ⌘V. No private preference was needed. Measured on macOS 27 in a
> plain `WKWebView`: all three reads pop WebKit's own one-item "Paste" menu at the
> page and hand over nothing unless it is clicked, every time, with nothing the
> app can hear or remember, and text the same site copied is read back with no
> menu at all. The SDK has no clipboard preference, no `WKUIDelegate` method and
> no permission query for it (`navigator.permissions.query({name:
> 'clipboard-read'})` throws). `javaScriptCanAccessClipboard` and
> `DOMPasteAllowed` are private and would only remove the menu. So Luna replaces
> the three calls in the page (`TabController+Clipboard.swift`) with ones that ask
> it through a reply handler, and reads the pasteboard itself for a site that may,
> only for the tab in front in the key window. `execCommand('paste')` cannot wait
> for a question, so it returns false and Luna performs Edit ▸ Paste on the page
> once the site may. A page that reaches the originals some other way gets
> WebKit's menu, which still asks every time.
### §14 — 14. Apple Passwords, autofill & forms

**Goal:** the user keeps using **Apple's Passwords / iCloud Keychain** — we do not build a password manager and we do not become a second place their secrets live. What we build is the bridge. Read §14.1 before writing any UI copy: part of this is blocked by Apple, and which part decides what we can promise.
### §16 — 16. Extensions (`WKWebExtension`)

> **Decided 2026-09-17 (§32):** general extension support is **out of v1**. The only extension-adjacent thing we build now is the **native-messaging bridge in §14.7**, so 1Password and Bitwarden work. Everything below waits for M5/v2 — do not start §16.2–§16.6 without explicit go-ahead.
> **Confirmed 2026-09-21:** this section is the *only* route to Chrome extensions, and it is a good one. Embedding Chromium is not an alternative — CEF supports extensions only in Chrome-style windows showing Chrome's own toolbar, so a browser hosted in our own `NSView` (Alloy style) has `chrome://extensions` blocked and `LoadExtension` deleted at M128. `WKWebExtension` loads Chrome-format MV2/MV3 from a directory or ZIP, and a `.crx` is a ZIP with a 16-byte header — no Apple gatekeeping, it is our own controller. Benchmark for §16.5: Kagi's Orion spent six years on its own WebKit shim and publishes *"about 70%"* API coverage; Apple's implementation starts there and improves each OS release. See `docs/research/ENGINES.md` §5.
### §31 — 31. iCloud sync (CloudKit)

Everything the user *structures* follows them between Macs — and later, iPhone — through **their own iCloud account**. No Luna account, no Luna server, no password to forget. Local-first: the app is fully usable with iCloud off or unavailable, and sync is an accelerator, never a dependency.
