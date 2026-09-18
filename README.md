<div align="center">
  <img width="150" height="150" src="assets/icon/final/luna-icon-light.png" alt="Luna">
  <h1>Luna</h1>
  <p><strong>Browse the dark side.</strong></p>
  <p>A native WebKit browser for macOS.</p>
</div>
<br/>
<p align="center">
  <a href="https://www.apple.com/macos/"><img src="https://badgen.net/badge/macOS/26+/blue" alt="macOS 26+"></a>
  <a href="https://swift.org"><img src="https://badgen.net/badge/Swift/6.0/orange" alt="Swift 6.0"></a>
  <a href="https://developer.apple.com/documentation/webkit"><img src="https://badgen.net/badge/Engine/WebKit/purple" alt="WebKit"></a>
  <a href="TODO.md"><img src="https://badgen.net/badge/Status/in%20development/yellow" alt="Status: in development"></a>
</p>

## Overview

Luna is a macOS browser built on AppKit and WebKit — one `WKWebView` per tab, SQLite for
history, and macOS 26's Liquid Glass for the chrome. It favours a quiet, keyboard-driven
interface over breadth of features.

It builds and runs today. [`TODO.md`](TODO.md) is the plan of record for the rest.

## Highlights

- **Native chrome.** AppKit windows and sidebar, real Liquid Glass, and a `Clear` /
  `Opaque` setting for how much desktop comes through.
- **One web view per tab.** Cold tabs hibernate and restore from their own session state.
- **Spaces and Profiles.** Named, coloured workspaces backed by real storage containers
  (`WKWebsiteDataStore(forIdentifier:)`), so logins stay genuinely separate.
- **Pinned tiles and Today tabs.** Per-Profile favourites; Today tabs auto-archive and
  come back with `⇧⌘T`.
- **Blocking and privacy.** EasyList, EasyPrivacy and Fanboy Annoyance as native
  `WKContentRuleList`s, plus HTTPS-Only, local-network blocking and per-site permissions.
- **Command Bar.** `⌘T` for URL, search, open tabs and ranked history in one input, with
  live suggestions from DuckDuckGo, Google or Bing — or any custom `%s` template.
- **Import** from Safari, Arc, Dia, Chrome, Chromium, Brave, Edge, Vivaldi, Opera, Atlas
  and Helium.
- **Accessibility is a first-class path.** Reduce Transparency, Increase Contrast and
  Reduce Motion each have a real design, not a degraded one.

## Quick start

```sh
git clone https://github.com/ziadmyassine/luna-browser.git
cd luna-browser
brew install xcodegen swiftlint swiftformat
make gen
make run
```

`Luna.xcodeproj` is generated from [`project.yml`](project.yml) and never committed, so
run `make gen` after cloning and after adding any file. Then `make build`, `make test`,
`make lint`, `make fmt`, or `open Luna.xcodeproj` to work in Xcode.

## Repository

| Path | |
|---|---|
| `App/` | Delegate, main menu, commands |
| `UI/` | Window, sidebar, top bar, Command Bar, History |
| `Design/` | Tokens, type, motion, glass, and the token self-checks |
| `Features/` | Settings, Downloads, Import, Search, internal pages |
| `BrowserKit/` | The engine package — tabs, store, content blocking (no AppKit) |
| `Tests/`, `BrowserKit/Tests/` | The two suites |
| `Tools/` | Layering check and the performance harness |
| [`TODO.md`](TODO.md) | The full specification and plan of record |
| `assets/icon/` | Icon sources and the exported `.icon` |

## Docs

- [UI specification](docs/UI-SPEC.md) — the build contract for the visual layer
- [Settings specification](docs/SETTINGS-SPEC.md) — the Settings window's contract
- [Spaces specification](docs/SPACES-SPEC.md) — Spaces, Profiles and the sidebar hierarchy
- [Performance](docs/PERF.md) — the budgets, measured rather than assumed

## License

**GNU General Public License v3.0 or later** — see [`LICENSE`](LICENSE). The source of
every released build has to be available, in-app updates included, because shipping an
update is distribution. Check any new dependency for compatibility (today's one, GRDB, is
MIT).
