# Architecture

How Luna is put together, and the words it uses for things. Why each choice was
made is in [DECISIONS.md](DECISIONS.md).

## What Luna is

A **native macOS web browser** that uses **Apple's WebKit (WKWebView)** as its engine — *not* Chromium, *not* Electron, *not* a bundled WebKit build — and that copies the **interaction model and visual polish of Arc Browser** (The Browser Company) while being its own product.

The three sentences that define the product:
1. **The chrome disappears.** No horizontal tab strip, no persistent toolbar. A vertical sidebar holds everything; the page gets the rest.
2. **Tabs are disposable, Spaces are permanent.** Tabs auto-archive; the user's structure lives in Spaces, Pinned tabs and Favorites.
3. **Everything is one keystroke away.** A single Command Bar (`⌘T`) does URL entry, search, tab switching, history search, and app commands.

## Non-goals

Not built without asking first:

- Cross-platform (Windows/Linux). macOS only. Do not add abstraction layers "for later portability".
- Bundling or patching a custom WebKit build. We ship against the system framework.
- Chromium/Blink fallback rendering for broken sites. **Also: no second engine at all** — not as a separate build, not per-tab. Researched 2026-09-21 and closed; `docs/research/ENGINES.md` has the evidence and the conditions that would justify reopening it. Short version: Gecko has had no desktop embedding API since 2011, and a bundled Chromium costs +322 MB, permanent App Store exclusion, no Widevine (so no Netflix/Spotify), our own codec licensing, and a two-week CVE treadmill — while CEF **cannot run Chrome extensions** in the only mode we could embed, which was the main reason to want it.
- A custom account system, our own sync servers, or telemetry-by-default. Sync is **iCloud only** (§31) — no logins, no backend of ours.
- ~~A password manager of our own.~~ **Reversed 2026-09-24 — now priority P2 (★).** The original line: we write into **Apple's** Passwords / iCloud Keychain instead — see §14, and read §14.1 before promising anything.
- Mac App Store distribution for v1 (sandbox blocks default-browser registration; see §22).
- Monetisation of any kind — no licence keys, no payments, no accounts (D15).
- Telemetry or analytics, even opt-in (D16).
- AI features in v1. §30.4 reserves the layout slot and nothing else.
- ~~General extension support in v1 — only the §14.7 password bridge. See §16.~~ **Reversed 2026-09-24 — now priority P4 (★).**

## The layout of the repo

```
Luna/                    the app (AppKit)
├── App/                 AppDelegate and its extensions, Info.plist, menus, URL handling
├── UI/                  the chrome: Window, Sidebar, TopBar, Browser (session and page bar),
│                        CommandBar, History, Popout, Passwords, Toast, TabSwitcher, Quit…
├── Features/            Settings, Extensions, Downloads, Import, Sync, SafariFavorites,
│                        Control (Luna Control), Search, InternalPages, Updates, Onboarding…
├── Design/              tokens (colours, metrics, motion), Liquid Glass, icons
└── Helpers/luna-control the stdio server an AI app talks to, shipped inside Luna.app
BrowserKit/              the engine, a Swift package with no AppKit in it
├── Sources/BrowserKit/  Engine (TabController, one WKWebView per tab), Model, Store (SQLite
│                        via GRDB), Blocking, Passwords, Extensions (WKWebExtension), Sync
├── Sources/LunaControl/ Luna Control's protocol, socket and page scripts (Foundation only)
└── Tests/               the package's tests, runnable with `swift test`
Tests/                   the app's tests (XCTest), one folder per area
Config/                  Signing/ (entitlements; the provisioning profile stays local) and
                         CloudKit/Schema.ckdb
Tools/                   checks run by CI, the DMG script, the performance harness
assets/                  the app icon, the in-app mark, Luna Control's app icons, DMG art
docs/                    specs, feature notes, plans and research (see docs/README.md)
```

`Luna.xcodeproj` is generated from `project.yml` by XcodeGen (`make gen`) and is
not committed.

## How the parts fit

- **One `BrowserSession`** owns the tabs, Spaces and windows' state
  (`Luna/UI/Browser/`). Views observe it; they do not hold tab state of their own.
- **One `TabController` per tab** (`BrowserKit/Sources/BrowserKit/Engine/`) owns
  that tab's `WKWebView`, its delegates and the scripts it injects. A tab that has
  not been used lately is hibernated: the controller keeps its state and gives up
  the web view and its process (§19.2).
- **Each Space has its own `WKWebsiteDataStore`**, so logins and cookies never
  cross between Spaces (§5, [SPACES-SPEC.md](SPACES-SPEC.md)).
- **Storage is SQLite through GRDB** (`BrowserKit/Sources/BrowserKit/Store/`):
  tabs, history, Spaces, settings that sync.
- **iCloud sync** is CloudKit's private database, opt-in, with no Luna server
  ([SYNC.md](SYNC.md)).
- **Extensions** run in WebKit's `WKWebExtensionController`, with a shim for the
  Chrome APIs WebKit lacks ([EXTENSIONS.md](EXTENSIONS.md)).
- **Luna Control** lets an AI app drive tabs through `luna-control`, an MCP server
  over stdio that reaches the running Luna over a local socket
  ([LUNA-CONTROL.md](LUNA-CONTROL.md)).
- **The chrome's look** comes from `Luna/Design/`: every colour, length and timing
  is a token, and `Glass.swift` is the only file that touches Liquid Glass
  ([UI-SPEC.md](UI-SPEC.md)).

## Glossary

Use these exact names in code.

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
